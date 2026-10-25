"""Minimal SWF reader for the fapwall tools: tags, bit-packed records,
PlaceObject parsing, a sprite's display list per frame, and bounds."""
import struct

SHAPES = (2, 22, 32, 83)
SPRITE = 39
IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)


def read_tags(b, p, end):
	out = []
	while p < end:
		h = struct.unpack_from('<H', b, p)[0]
		code, ln = h >> 6, h & 63
		hp = p
		p += 2
		if ln == 63:
			ln = struct.unpack_from('<I', b, p)[0]
			p += 4
		out.append((code, hp, p, ln))
		p += ln
		if code == 0:
			break
	return out


def header(b):
	nbits = b[8] >> 3
	return 8 + (5 + nbits * 4 + 7) // 8 + 4


def load(path):
	b = open(path, 'rb').read()
	assert b[:3] == b'FWS', 'uncompressed SWF expected'
	return b


def mktag(code, body):
	if len(body) < 63:
		return struct.pack('<H', (code << 6) | len(body)) + body
	return struct.pack('<HI', (code << 6) | 63, len(body)) + body


class Bits:
	def __init__(self, b, p):
		self.b, self.p, self.bit = b, p, 0

	def u(self, n):
		v = 0
		for _ in range(n):
			v = (v << 1) | ((self.b[self.p] >> (7 - self.bit)) & 1)
			self.bit += 1
			if self.bit == 8:
				self.bit, self.p = 0, self.p + 1
		return v

	def s(self, n):
		v = self.u(n)
		return v - (1 << n) if n and v & (1 << (n - 1)) else v

	def align(self):
		if self.bit:
			self.bit, self.p = 0, self.p + 1
		return self.p


def rect(b, p):
	r = Bits(b, p)
	n = r.u(5)
	xmin, xmax, ymin, ymax = (r.s(n) for _ in range(4))
	return (xmin / 20, ymin / 20, xmax / 20, ymax / 20), r.align()


def matrix(b, p):
	"""(a, b, c, d, tx, ty) in pixels: x' = a*x + c*y + tx, y' = b*x + d*y + ty."""
	r = Bits(b, p)
	a = d = 1.0
	bb = c = 0.0
	if r.u(1):
		n = r.u(5)
		a, d = r.s(n) / 65536, r.s(n) / 65536
	if r.u(1):
		n = r.u(5)
		bb, c = r.s(n) / 65536, r.s(n) / 65536
	n = r.u(5)
	tx, ty = r.s(n) / 20, r.s(n) / 20
	return (a, bb, c, d, tx, ty), r.align()


def cxform(b, p):
	"""[mult r g b a, add r g b a]: mults 0..1, adds -255..255."""
	r = Bits(b, p)
	has_add, has_mult = r.u(1), r.u(1)
	n = r.u(4)
	mult = [r.s(n) / 256 for _ in range(4)] if has_mult else [1.0] * 4
	add = [r.s(n) for _ in range(4)] if has_add else [0] * 4
	return mult + add, r.align()


def place(b, code, s):
	"""A PlaceObject2/3: depth, move, and whichever of char, matrix, cx, clip it sets."""
	f = b[s]
	p = s + 1
	f2 = 0
	if code == 70:
		f2 = b[p]
		p += 1
	o = {'depth': struct.unpack_from('<H', b, p)[0], 'move': bool(f & 1)}
	p += 2
	if code == 70 and (f2 & 8 or (f2 & 16 and f & 2)):
		p = b.index(b'\0', p) + 1
	if f & 2:
		o['char'] = struct.unpack_from('<H', b, p)[0]
		p += 2
	if f & 4:
		o['matrix'], p = matrix(b, p)
	if f & 8:
		o['cx'], p = cxform(b, p)
	if f & 16:
		p += 2
	if f & 32:
		p = b.index(b'\0', p) + 1
	if f & 64:
		o['clip'] = struct.unpack_from('<H', b, p)[0]
	return o


def place_char(b, code, s, ln):
	"""(depth, char id or None, None) of any PlaceObject."""
	if code == 4:
		cid, depth = struct.unpack_from('<HH', b, s)
		return depth, cid, None
	o = place(b, code, s)
	return o['depth'], o.get('char'), None


def index(b):
	"""Character tags by id: (code, body_start, length)."""
	out = {}
	for code, hp, s, ln in read_tags(b, header(b), len(b)):
		if ln >= 2 and (code in SHAPES or code == SPRITE):
			out[struct.unpack_from('<H', b, s)[0]] = (code, s, ln)
	return out


def replay(b, s, ln):
	"""A sprite's display list after each frame: [{depth: {char, matrix, cx, clip}}]."""
	frames = []
	disp = {}
	for code, hp, s2, l2 in read_tags(b, s + 4, s + ln):
		if code == 1:
			frames.append({d: dict(o) for d, o in disp.items()})
		elif code in (26, 70):
			o = place(b, code, s2)
			d = o['depth']
			if not o['move'] or d not in disp:
				disp[d] = {'char': None, 'matrix': IDENTITY, 'cx': None, 'clip': 0}
			for k in ('char', 'matrix', 'cx', 'clip'):
				if k in o:
					disp[d][k] = o[k]
		elif code == 28:
			disp.pop(struct.unpack_from('<H', b, s2)[0], None)
		elif code == 5:
			disp.pop(struct.unpack_from('<HH', b, s2)[1], None)
	return frames


def transform_rect(m, r):
	pts = [(m[0] * x + m[2] * y + m[4], m[1] * x + m[3] * y + m[5]) for x in (r[0], r[2]) for y in (r[1], r[3])]
	xs, ys = [p[0] for p in pts], [p[1] for p in pts]
	return (min(xs), min(ys), max(xs), max(ys))


def union(a, b):
	if a is None:
		return b
	if b is None:
		return a
	return (min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]))


def bounds(b, idx, cid, frame=None, cache=None):
	"""Pixel bounds of a character: one frame of a sprite, or all of them (frame=None)."""
	cache = {} if cache is None else cache
	key = (cid, frame)
	if key in cache:
		return cache[key]
	cache[key] = None
	code, s, ln = idx.get(cid, (None, 0, 0))
	r = None
	if code in SHAPES:
		r, _ = rect(b, s + 2)
	elif code == SPRITE:
		frames = replay(b, s, ln)
		for disp in (frames if frame is None else frames[frame - 1:frame]):
			for o in disp.values():
				if o['clip'] or o['char'] is None:
					continue
				cb = bounds(b, idx, o['char'], None, cache)
				if cb is not None:
					r = union(r, transform_rect(o['matrix'], cb))
	cache[key] = r
	return r

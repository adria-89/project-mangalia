"""Export fapwall's rear-view body parts as pixel sprites for the after-hours
rig (PLACEHOLDER art, replace before any release).

    python parts.py <fapwall.swf> <ffdec-cli.jar> <out_dir>

Every part becomes one atlas, <out_dir>/<part>.png, holding all its variants
(skin details, types, outfits...). rig.json says, per part, where it sits
(its container's place in fapwall's act space and its own matrix inside it,
already scaled to rig pixels) and, per variant, its rect in the atlas and its
offset from the part's pivot.

Recolourable parts ("skin" mode) are encoded: R = shade (0 dark .. 1 light),
G = region (0 skin, 64 flesh, 192 cum, 255 line), A = coverage;
afterhours/skin.gdshader colours them with the girl's ramps. "plain" parts
(clothing, cum drips) keep fapwall's colours.

Variant keys: "N" for frame N; "S_N" for skin detail S, frame (type) N.
"""
import colorsys
import json
import os
import shutil
import subprocess
import sys
import tempfile

from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from swflib import bounds, index, load, replay

SCALE = 0.85  # fapwall px to ours: the butt comes out about half the 540 px screen wide, like fapwall frames it
# Where flesh is told apart from skin: the green skin (green vs pink is easy).
# Other skins borrow its flesh mask for the same type.
REFERENCE_SKIN = 14
# Skin details (fapwall's 1-52) whose holes and futa are exported; the body
# parts keep all 52. A skin not here uses REFERENCE_SKIN's holes (body_rig.gd's
# BASE_SKIN), so it must stay in. The others are the girls' skins, and 26
# (dark, heavy outline), which looks unlike the rest.
HOLE_SKINS = (1, REFERENCE_SKIN, 26, 32, 34)
# Clothing frames exported (the rest of fapwall's are left out). An outfit is
# the same frame on all four outfit parts; body_rig.gd's OUTFIT_RIGHT swaps a
# few for the right side, keep those pairs together.
OUTFITS = (139,)
FRAMES = {
	"outfit_butt": OUTFITS, "outfit_back": OUTFITS, "outfit_thigh": OUTFITS, "outfit_shin": OUTFITS,
	"over": (16,),
}
PAD = 2  # transparent pixels between atlas cells

IDENTITY = (1.0, 0.0, 0.0, 1.0, 0.0, 0.0)

# name: {
#   src: a sprite id (every frame a variant), or ("skins", container, depth):
#        per skin detail the container's child at that depth, every frame of it,
#   pos: the container's place in fapwall's act space (rig.json "pos"),
#   matrix: the part inside its container (default: read from the container
#           for skinned parts, identity otherwise),
#   flip_y, mode: "skin" (default) / "skin_only" (no flesh) / "plain" / "soft",
#   space: what it hangs off in the rig ("act", "butt", "back", "thigh",
#          "shin", "leg")
# }
PARTS = {
	# Her body. Each skin detail is one frame of these.
	"back": {"src": 6757, "pos": (0.0, -17.4), "mode": "skin_only", "space": "back"},
	"butt": {"src": 3618, "pos": (-78.3, 0.0), "mode": "skin_only", "space": "butt"},
	"thigh": {"src": 6401, "matrix": (1, 0, 0, 1, -0.2, 0), "mode": "skin_only", "space": "thigh"},
	"shin": {"src": 5946, "mode": "skin_only", "space": "shin"},
	"foot": {"src": 6049, "matrix": (1, 0, 0, 1, -2.1, 0.4), "mode": "skin_only", "space": "shin"},
	"shadow": {"src": 10639, "pos": (-0.5, 16.9), "mode": "soft", "space": "act"},
	"tail": {"src": 10230, "pos": (0.0, -17.4), "mode": "skin_only", "space": "act"},
	# Holes: closed, open (stretched), and with cum in them. Every skin detail.
	"pussy": {"src": ("skins", 2498, 4), "pos": (0.0, 68.0)},
	"pussy_open": {"src": ("skins", 2967, 4), "pos": (0.0, 66.0)},
	"pussy_cum": {"src": ("skins", 1975, 4), "pos": (0.1, 65.8)},
	"pussy_hole": {"src": 6938, "pos": (0.2, 58.4)},
	"anus": {"src": ("skins", 729, 4), "pos": (0.0, -7.0)},
	"anus_open": {"src": ("skins", 985, 4), "pos": (0.0, -5.2), "flip_y": True},
	"anus_cum": {"src": ("skins", 1447, 4), "pos": (0.1, -5.3), "flip_y": True},
	"anus_hole": {"src": 6941, "pos": (0.1, -5.8)},
	# Her own penis (futa), where the pussy is.
	"futa": {"src": ("skins", 3325, 1), "pos": (0.0, 68.0)},
	# Pubic hair, in each hole state's container (the bottom tuft is wider when open).
	"hair_pussy_bot": {"src": 1453, "matrix": (1, 0, 0, 1, -32.1, -49.2), "mode": "skin_only", "space": "pussy"},
	"hair_pussy_top": {"src": 1997, "matrix": (1, 0, 0, 1, -32.1, -49.2), "mode": "skin_only", "space": "pussy"},
	"hair_pussy_open_bot": {"src": 1453, "matrix": (1.44, 0, 0, 1, -46.5, -44.25), "mode": "skin_only", "space": "pussy_open"},
	"hair_pussy_open_top": {"src": 2516, "matrix": (1, 0, 0, 1, -32.1, -49.2), "mode": "skin_only", "space": "pussy_open"},
	"hair_pussy_cum_bot": {"src": 1453, "matrix": (1.22, 0, 0, 1, -38.85, -48.5), "mode": "skin_only", "space": "pussy_cum"},
	"hair_pussy_cum_top": {"src": 1472, "matrix": (1, 0, 0, 1, -32.1, -49.2), "mode": "skin_only", "space": "pussy_cum"},
	"hair_anus": {"src": 370, "matrix": (1, 0, 0, 1, -0.05, -0.05), "mode": "skin_only", "space": "anus"},
	"hair_anus_open": {"src": 370, "matrix": (1.66, 0, 0, 1, -0.05, -0.05), "mode": "skin_only", "space": "anus_open"},
	"hair_anus_cum": {"src": 370, "matrix": (1.33, 0, 0, 1, -0.05, -0.05), "mode": "skin_only", "space": "anus_cum"},
	# Cum: over the hole after a creampie, and running down the butt halves.
	"cream_pussy": {"src": 1474, "matrix": (1, 0, 0, 1, 0.0, -4.35), "mode": "plain", "space": "pussy_cum"},
	"cream_anus": {"src": 996, "matrix": (1, 0, 0, 1, -1.85, 7.95), "mode": "plain", "space": "anus_cum"},
	"cream_butt_pussy": {"src": 3337, "matrix": (1, 0, 0, 1, -8.55, 29.7), "mode": "plain", "space": "butt"},
	"cream_butt_anus": {"src": 3339, "matrix": (1, 0, 0, 1, 8.3, -55.9), "mode": "plain", "space": "butt"},
	# The penis: from below (pussy) and fapwall's own art for from above (anus).
	"penis": {"src": 362, "pos": (0.0, 179.7)},
	"penis_back": {"src": 331, "pos": (0.0, 179.7)},
	# Clothing, in fapwall's colours. An outfit is the same frame on all four.
	"outfit_butt": {"src": 3892, "mode": "plain", "space": "butt"},
	"outfit_back": {"src": 6859, "mode": "plain", "space": "back"},
	"outfit_thigh": {"src": 6655, "matrix": (1, 0, 0, 1, -0.2, 0), "mode": "plain", "space": "thigh"},
	"outfit_shin": {"src": 6295, "mode": "plain", "space": "shin"},
	"over": {"src": 4082, "mode": "plain", "space": "butt"},
}
# Animation_ViewAss_Leg: thigh and shin per leg pose (frames), and where the
# left leg sits (the right one is it mirrored, 1 px off like the butt).
LEG_CLIP = 10647
LEG_POS = (-91.5, 50.2)
LEG_PARTS = {10643: "thigh", 10646: "shin"}

REGION = {"skin": 0, "flesh": 64, "cum": 192, "line": 255}


def classify(r, g, b, flesh_ok, cum_ok):
	h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
	lum = (0.299 * r + 0.587 * g + 0.114 * b) / 255
	if lum < 0.16:
		return "line"
	if cum_ok and lum > 0.78 and s < 0.12:
		return "cum"
	if flesh_ok and s > 0.15 and (h * 360 >= 300 or h * 360 <= 15):
		return "flesh"
	return "skin"


def encode(im, mode, flesh_mask=None, cum_ok=False):
	"""Colours to shade/region. flesh_mask: (image, dx, dy) of the reference
	skin's regions for the same type, used instead of telling flesh by colour.
	cum_ok: near-white counts as cum (only the parts with cum in them)."""
	px = im.load()
	w, h = im.size
	regions = {}
	for y in range(h):
		for x in range(w):
			r, g, b, a = px[x, y]
			if not a:
				continue
			reg = classify(r, g, b, mode == "skin" and flesh_mask is None, cum_ok)
			if reg == "skin" and mode == "skin" and flesh_mask is not None:
				mask, dx, dy = flesh_mask
				mx, my = x + dx, y + dy
				if 0 <= mx < mask.width and 0 <= my < mask.height and mask.getpixel((mx, my))[1] == REGION["flesh"]:
					reg = "flesh"
			if mode == "skin_only" and reg in ("flesh", "cum"):
				reg = "skin"
			regions[(x, y)] = (reg, (0.299 * r + 0.587 * g + 0.114 * b) / 255)
	if mode == "skin" and flesh_mask is None:
		# Pale highlights on flesh read as skin: a skin pixel mostly surrounded by flesh is flesh.
		for _ in range(2):
			flip = []
			for (x, y), (reg, lum) in regions.items():
				if reg != "skin":
					continue
				near = [regions.get((x + dx, y + dy), (None,))[0] for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
				if near.count("flesh") >= 3 and near.count("flesh") > near.count("skin"):
					flip.append((x, y))
			for p in flip:
				regions[p] = ("flesh", regions[p][1])
	top = {}
	for reg, lum in regions.values():
		top[reg] = max(top.get(reg, 0.0), lum)
	out = Image.new("RGBA", im.size, (0, 0, 0, 0))
	po = out.load()
	for (x, y), (reg, lum) in regions.items():
		shade = lum / top[reg] if top[reg] > 0 else 0.0
		po[x, y] = (round(shade * 255), REGION[reg], 0, px[x, y][3])
	return out


def shrink(im, offset, hard_alpha=True):
	"""Scale down for the pixel look; snaps the offset to whole pixels.
	hard_alpha: every pixel fully in or out (off keeps soft shadows soft)."""
	ox, oy = offset[0] * SCALE, offset[1] * SCALE
	sx, sy = round(ox), round(oy)
	# Pad so the sub-pixel part of the offset is kept in the image.
	pad_x, pad_y = round((ox - sx) / SCALE), round((oy - sy) / SCALE)
	if pad_x or pad_y:
		canvas = Image.new("RGBA", (im.width + abs(pad_x), im.height + abs(pad_y)), (0, 0, 0, 0))
		canvas.paste(im, (max(pad_x, 0), max(pad_y, 0)))
		im = canvas
	w, h = max(1, round(im.width * SCALE)), max(1, round(im.height * SCALE))
	small = im.resize((w, h), Image.LANCZOS)
	if hard_alpha:
		small.putalpha(small.getchannel("A").point(lambda a: 255 if a >= 128 else 0))
	return small, [sx - (1 if pad_x < 0 else 0), sy - (1 if pad_y < 0 else 0)]


def leg_poses(b, idx):
	"""Each leg pose as the thigh's and shin's matrix [a, b, c, d, tx, ty] (rig pixels)."""
	code, s, ln = idx[LEG_CLIP]
	poses = []
	for disp in replay(b, s, ln):
		pose = {}
		for o in disp.values():
			name = LEG_PARTS.get(o["char"])
			if name:
				pose[name] = scaled(o["matrix"])
		poses.append(pose)
	return {"pos": [round(LEG_POS[0] * SCALE, 2), round(LEG_POS[1] * SCALE, 2)], "poses": poses}


def scaled(m):
	a, bb, c, d, tx, ty = m
	return [round(a, 4), round(bb, 4), round(c, 4), round(d, 4), round(tx * SCALE, 2), round(ty * SCALE, 2)]


def pack(cells):
	"""Shelf-pack images into one atlas. cells: {key: image}. Returns (atlas, {key: rect})."""
	if not cells:
		return Image.new("RGBA", (1, 1), (0, 0, 0, 0)), {}  # nothing kept (an outfit with no art on this part)
	keys = sorted(cells, key=lambda k: -cells[k].height)
	width = max(512, min(4096, max(cells[k].width for k in keys) + 2 * PAD))
	while True:
		x = y = row = 0
		rects = {}
		for k in keys:
			im = cells[k]
			if x + im.width + PAD > width:
				x, y, row = 0, y + row + PAD, 0
			rects[k] = [x, y, im.width, im.height]
			x += im.width + PAD
			row = max(row, im.height)
		height = y + row
		if height <= 4096 or width >= 8192:
			break
		width *= 2
	atlas = Image.new("RGBA", (width, height), (0, 0, 0, 0))
	for k, (x, y, w, h) in rects.items():
		atlas.paste(cells[k], (x, y))
	return atlas, rects


def ffdec(jar, swf, ids, out):
	subprocess.run(["java", "-jar", jar, "-format", "sprite:png", "-selectid", ",".join(map(str, sorted(set(ids)))),
		"-export", "sprite", out, swf], check=True, stdout=subprocess.DEVNULL)


def frames_of(root, cid):
	for d in os.listdir(root):
		if d.startswith(f"DefineSprite_{cid}_") or d == f"DefineSprite_{cid}":
			folder = os.path.join(root, d)
			return sorted((os.path.join(folder, f) for f in os.listdir(folder)), key=lambda f: int(os.path.basename(f)[:-4]))
	raise FileNotFoundError(cid)


def skin_children(b, idx, container, depth):
	"""Per skin detail: (child id, its matrix in the container)."""
	code, s, ln = idx[container]
	frames = replay(b, s, ln)
	out = {}
	for skin in HOLE_SKINS:
		if skin <= len(frames) and depth in frames[skin - 1]:
			o = frames[skin - 1][depth]
			out[skin] = (o["char"], o["matrix"])
	return out


def main(swf, jar, out_dir):
	b = load(swf)
	idx = index(b)
	tmp = tempfile.mkdtemp(prefix="fapwall_parts_")
	# Which sprites to render: plain ids, and every skin's child for skinned parts.
	children = {}
	ids = []
	for name, spec in PARTS.items():
		src = spec["src"]
		if isinstance(src, tuple):
			children[name] = skin_children(b, idx, src[1], src[2])
			ids += [cid for cid, m in children[name].values()]
		else:
			ids.append(src)
	ffdec(jar, swf, ids, tmp)
	# out_dir is all ours: start clean so old parts don't linger.
	shutil.rmtree(out_dir, ignore_errors=True)
	os.makedirs(out_dir)
	rig = {"scale": SCALE, "parts": {}}
	for name, spec in PARTS.items():
		mode = spec.get("mode", "skin")
		src = spec["src"]
		if isinstance(src, tuple):
			sources = {skin: cid for skin, (cid, m) in children[name].items()}
			matrix = children[name][REFERENCE_SKIN][1]
		else:
			sources = {None: src}
			matrix = spec.get("matrix", IDENTITY)
		cells, offsets = {}, {}
		reference = {}  # frame -> (encoded image, offset) of the reference skin, for flesh masks
		order = sorted(sources, key=lambda s: (s != REFERENCE_SKIN, s or 0))
		for skin in order:
			cid = sources[skin]
			origin = bounds(b, idx, cid)
			for i, f in enumerate(frames_of(tmp, cid)):
				if name in FRAMES and i + 1 not in FRAMES[name]:
					continue
				im = Image.open(f).convert("RGBA")
				box = im.getbbox()
				if box is None:
					continue  # an empty frame ("none")
				small, off = shrink(im.crop(box), (origin[0] + box[0], origin[1] + box[1]), mode != "soft")
				if mode in ("plain", "soft"):
					out = small
				elif skin is not None and skin != REFERENCE_SKIN and (i + 1) in reference:
					ref, ref_off = reference[i + 1]
					out = encode(small, mode, (ref, off[0] - ref_off[0], off[1] - ref_off[1]), "cum" in name)
				else:
					out = encode(small, mode, None, "cum" in name)
					if skin == REFERENCE_SKIN:
						reference[i + 1] = (out, off)
				key = f"{i + 1}" if skin is None else f"{skin}_{i + 1}"
				cells[key] = out
				offsets[key] = off
		atlas, rects = pack(cells)
		atlas.save(os.path.join(out_dir, f"{name}.png"), optimize=True)
		pos = spec.get("pos", (0.0, 0.0))
		rig["parts"][name] = {
			"space": spec.get("space", "act"),
			"pos": [round(pos[0] * SCALE, 2), round(pos[1] * SCALE, 2)],
			"matrix": scaled(matrix),
			"flip_y": spec.get("flip_y", False),
			"plain": mode in ("plain", "soft"),
			"variants": {k: {"rect": rects[k], "offset": offsets[k]} for k in sorted(cells, key=lambda k: [int(n) for n in k.split("_")])},
		}
		print(name, len(cells), "variants", atlas.size)
	rig["legs"] = leg_poses(b, idx)
	with open(os.path.join(out_dir, "rig.json"), "w") as f:
		json.dump(rig, f, indent="\t")
	shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
	main(sys.argv[1], sys.argv[2], sys.argv[3])

"""Draws the after hours belly in fapwall's encoding (see
afterhours/skin.gdshader): R = shade, G = region (0 skin, 255 line), A =
coverage. Cel shaded, lit from below-front, with a thick outline.

    python tools/belly.py

Writes assets/placeholder/afterhours/belly.png: FRAMES frames in a grid of
COLUMNS, row by row, flat (tucked under her butt) to fully bulged; enough of
them that each is about a pixel bigger than the last, so it grows smoothly. Each is one silhouette, a
narrow belly whose lower end swells and pushes down into a rounded bulge,
drawn at its real pixel size so the outline never stretches. The top
middle of a frame is where it hangs from (BodyRig.belly_pos).
"""
import math
from PIL import Image

OUT = "assets/placeholder/afterhours/belly.png"
FRAMES = 48  # BodyRig.BELLY_FRAMES
COLUMNS = 8  # BodyRig.BELLY_COLUMNS
WIDTH, HEIGHT = 112, 140
OUTLINE = 2.2
LIGHT = (-0.3, 0.45, 0.85)  # x right, y down (toward the floor), z at you
BANDS = [(0.4, 0.42), (0.86, 0.64), (0.96, 0.8), (2.0, 1.0)]


def ellipse(x, y, cx, cy, rx, ry):
	"""Roughly the signed distance to an ellipse (negative inside)."""
	return (math.hypot((x - cx) / rx, (y - cy) / ry) - 1.0) * min(rx, ry)


def smooth_min(a, b, k):
	h = max(k - abs(a - b), 0.0) / k
	return min(a, b) - h * h * k * 0.25


def frame(t):
	"""t: 0 = flat, 1 = fully bulged."""
	cx = WIDTH / 2 - 0.5
	belly_ry = 30 + 20 * t
	belly_rx = 30 + 18 * t
	belly_cy = 2 + belly_ry
	bulge_r = 10 + 16 * t
	bulge_cy = belly_cy + belly_ry - 10 + 14 * t

	def sdf(x, y):
		belly = ellipse(x, y, cx, belly_cy, belly_rx, belly_ry)
		bulge = ellipse(x, y, cx, bulge_cy, bulge_r, bulge_r * 1.2)
		return smooth_min(belly, bulge, 10.0)

	im = Image.new("RGBA", (WIDTH, HEIGHT))
	px = im.load()
	length = math.sqrt(sum(c * c for c in LIGHT))
	light = [c / length for c in LIGHT]
	for y in range(HEIGHT):
		for x in range(WIDTH):
			d = sdf(x, y)
			if d > 0.0:
				continue
			if d > -OUTLINE:
				px[x, y] = (0, 255, 0, 255)
				continue
			# A pseudo-normal: outward in 2D at the edge, facing you deep inside.
			gx = sdf(x + 0.5, y) - sdf(x - 0.5, y)
			gy = sdf(x, y + 0.5) - sdf(x, y - 0.5)
			g = math.hypot(gx, gy) or 1.0
			nz = min(-d / 14.0, 1.0)
			side = math.sqrt(max(1.0 - nz * nz, 0.0))
			lit = gx / g * side * light[0] + gy / g * side * light[1] + nz * light[2]
			shade = next(s for limit, s in BANDS if lit <= limit)
			px[x, y] = (int(shade * 255), 0, 0, 255)
	return im


rows = (FRAMES + COLUMNS - 1) // COLUMNS
sheet = Image.new("RGBA", (WIDTH * COLUMNS, HEIGHT * rows))
for i in range(FRAMES):
	sheet.paste(frame(i / (FRAMES - 1)), ((i % COLUMNS) * WIDTH, (i // COLUMNS) * HEIGHT))
sheet.save(OUT)
print("ok", sheet.size)

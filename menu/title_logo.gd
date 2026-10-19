extends Node2D

## The menu title as a thick slab, Hotline Miami style: copies of its
## silhouette are stacked behind it (darker toward the back) and the stack
## swings as the logo turns and tilts, so it reads as 3D while staying 2D art.
## Also rocks with the sea. The source art is shrunk and given the game's
## black outline here, so a new logo PNG just drops in.

@export var source: Texture2D = preload("res://assets/menu/title_mangaliene.png")
## Width of the logo on screen in pixels (the art is shrunk to this once).
@export var width: int = 315
## Height against the art's own proportions: below 1 stretches it wide.
@export var height_scale: float = 0.85
## Black outline around the art and around the slab, in pixels.
@export var outline_px: int = 2

@export_group("Slab")
## How thick the slab is, in pixels.
@export var depth_px: float = 22.0
## Slab color right behind the face, and at the back.
@export var slab_front := Color(0.42, 0.24, 0.07)
@export var slab_back := Color(0.16, 0.08, 0.03)
## How far it's turned down at rest, so the slab shows under the letters.
@export var rest_tilt_degrees: float = 28.0

@export_group("Motion")
## Peak turn left/right and tilt up/down (how much of the slab's sides show).
@export var turn_degrees: float = 24.0
@export var tilt_degrees: float = 12.0
## Rocking in the screen plane, on top of the ship's roll.
@export var rock_degrees: float = 3.0
## How much of the sea's roll and heave it follows.
@export var sea_roll: float = 0.6
@export var sea_heave: float = 0.5
## Seconds for one full swing left and right.
@export var period: float = 7.0
## Breathing in and out (0.03 = 3% bigger at its peak).
@export var pulse: float = 0.03

var _face: Texture2D
var _silhouette: Texture2D
var _slab_outline: Texture2D
var _time := 0.0
var _rest_position := Vector2.ZERO

func _ready() -> void:
	_rest_position = position
	texture_filter = TEXTURE_FILTER_LINEAR
	_build()

func _process(delta: float) -> void:
	_time += delta
	var t := _time * TAU / period
	rotation = deg_to_rad(rock_degrees) * sin(t * 0.6 + 2.0) + Sea.roll * sea_roll
	position = _rest_position + Vector2(0.0, -Sea.heave * sea_heave)
	queue_redraw()

func _draw() -> void:
	var t := _time * TAU / period
	var turn := deg_to_rad(turn_degrees) * sin(t)
	var tilt := deg_to_rad(tilt_degrees) * sin(t * 0.73 + 1.3)
	# Turned away it gets narrower; the back of the slab slides the other way.
	var size := Vector2(cos(turn), cos(tilt)) * (1.0 + pulse * sin(t * 2.0))
	var back := depth_px * Vector2(-sin(turn), sin(tilt + deg_to_rad(rest_tilt_degrees)))
	var corner := -_face.get_size() / 2.0
	var steps := maxi(ceili(back.length()), 1)
	# All the slab outlines first, so they make one outline around the slab.
	for i in range(steps, 0, -1):
		draw_set_transform((back * i / steps).round(), 0.0, size)
		draw_texture(_slab_outline, corner, Color.BLACK)
	for i in range(steps, 0, -1):
		draw_set_transform((back * i / steps).round(), 0.0, size)
		draw_texture(_silhouette, corner, slab_front.lerp(slab_back, float(i) / steps))
	draw_set_transform(Vector2.ZERO, 0.0, size)
	draw_texture(_face, corner)

## Shrinks the art, outlines it in black and makes the silhouettes for the
## slab (all on the same padded canvas so they line up).
func _build() -> void:
	var art := source.get_image()
	if art.is_compressed():
		art.decompress()
	art.clear_mipmaps()
	art.convert(Image.FORMAT_RGBA8)
	art.fix_alpha_edges() # no dark fringe from transparent pixels when shrinking
	var height := maxi(roundi(art.get_height() * float(width) / art.get_width() * height_scale), 1)
	art.resize(width, height, Image.INTERPOLATE_LANCZOS)
	var pad := outline_px * 2 + 1
	var w := width + pad * 2
	var h := height + pad * 2
	var canvas := Image.create_empty(w, h, false, Image.FORMAT_RGBA8)
	canvas.blit_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), Vector2i(pad, pad))
	var data := canvas.get_data()
	var alpha := PackedByteArray()
	alpha.resize(w * h)
	for i in w * h:
		alpha[i] = data[i * 4 + 3]
	var outlined := _grow(alpha, w, h, outline_px)
	var face := _mask(outlined, w, h, Color.BLACK)
	face.blend_rect(canvas, Rect2i(0, 0, w, h), Vector2i.ZERO)
	_face = ImageTexture.create_from_image(face)
	_silhouette = ImageTexture.create_from_image(_mask(outlined, w, h, Color.WHITE))
	_slab_outline = ImageTexture.create_from_image(_mask(_grow(outlined, w, h, outline_px), w, h, Color.WHITE))

## The alpha grown by radius pixels in every direction, with hard edges.
static func _grow(alpha: PackedByteArray, w: int, h: int, radius: int) -> PackedByteArray:
	var across := PackedByteArray()
	across.resize(w * h)
	for y in h:
		for x in w:
			var most := 0
			for nx in range(maxi(x - radius, 0), mini(x + radius, w - 1) + 1):
				most = maxi(most, alpha[y * w + nx])
			across[y * w + x] = most
	var grown := PackedByteArray()
	grown.resize(w * h)
	for y in h:
		for x in w:
			var most := 0
			for ny in range(maxi(y - radius, 0), mini(y + radius, h - 1) + 1):
				most = maxi(most, across[ny * w + x])
			grown[y * w + x] = 255 if most >= 128 else 0
	return grown

## A flat-colored image shaped like the alpha.
static func _mask(alpha: PackedByteArray, w: int, h: int, color: Color) -> Image:
	var bytes := PackedByteArray()
	bytes.resize(w * h * 4)
	for i in w * h:
		bytes[i * 4] = color.r8
		bytes[i * 4 + 1] = color.g8
		bytes[i * 4 + 2] = color.b8
		bytes[i * 4 + 3] = alpha[i]
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes)

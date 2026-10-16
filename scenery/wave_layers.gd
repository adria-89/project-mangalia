extends Sprite2D

## Flapjack-style sea: this sprite is the front wave, and it spawns copies of
## itself behind it, each a bit higher and darker. Every layer sways side to
## side and bobs on its own, neighbours moving in opposite directions.
## Each row is also shifted sideways so the crests don't line up; the texture
## repeats horizontally and every row is drawn a little wider than the sprite,
## so neither the shift nor the sway ever shows an edge.
## All distances are in screen pixels (the sprite's own scale is accounted for).

@export var layer_count: int = 3
## How much higher each layer behind sits than the one in front of it.
@export var layer_spacing: float = 9.0
## Brightness of the back-most layer (front layer is 1.0).
@export_range(0.0, 1.0) var back_brightness: float = 0.7
## Sideways shift of each row relative to the one in front (screen px), so the
## crests interleave instead of stacking. Around a third of a crest works well.
@export var row_shift_px: float = 23.0

@export_group("Motion")
@export var sway_px: float = 7.0
@export var bob_px: float = 2.5
@export var speed: float = 1.4
## Each layer behind moves this much slower/faster, so they never line up.
@export var speed_variation: float = 0.18

var _layers: Array[Sprite2D] = []
## Each layer's resting offset (unscaled px), from the widened strip.
var _base_offsets: Array[Vector2] = []
var _time := 0.0

func _ready() -> void:
	_layers.append(self)
	for i in range(1, layer_count):
		var layer := Sprite2D.new()
		layer.texture = texture
		layer.centered = centered
		layer.show_behind_parent = true
		var shade := lerpf(1.0, back_brightness, float(i) / maxf(layer_count - 1, 1))
		layer.self_modulate = Color(shade, shade, shade)
		add_child(layer)
		move_child(layer, 0) # deeper layers draw first, behind the shallower ones
		_layers.append(layer)
	for i in _layers.size():
		_tile(_layers[i], i)

## Repeat the texture sideways and draw a wider strip, shifted for this row.
func _tile(layer: Sprite2D, row: int) -> void:
	var margin := (absf(sway_px) + 4.0) / absf(scale.x)
	var shift := row * row_shift_px / absf(scale.x)
	var size := texture.get_size()
	layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	layer.region_enabled = true
	layer.region_rect = Rect2(fposmod(shift, size.x) - margin, 0.0, size.x + margin * 2.0, size.y)
	# With a wider region the sprite grows on both sides; pull it back so the
	# original area stays where it was placed.
	_base_offsets.append(Vector2(-margin, 0.0) if not centered else Vector2.ZERO)

func _process(delta: float) -> void:
	_time += delta
	for i in _layers.size():
		var layer := _layers[i]
		var direction := 1.0 if i % 2 == 0 else -1.0
		var t := _time * speed * (1.0 + speed_variation * i) + i * 1.7
		var screen_offset := Vector2(
			sin(t) * sway_px * direction,
			cos(t * 2.0) * bob_px - i * layer_spacing)
		# Layers are children of this sprite, so offsets are in its unscaled space.
		layer.offset = _base_offsets[i] + screen_offset / scale

extends Sprite2D

## One bubble out of a drunk customer's hiccup: swells out of her mouth,
## wobbles up, drifts with the ship's roll and pops. Click it to pop it early.

const BUBBLE: Texture2D = preload("res://assets/ui/bubble.png")
const POPPED: Texture2D = preload("res://assets/ui/bubble_popped.png")
const POP_SOUND: AudioStream = preload("res://audio/dialogue_tick.wav")

## Final size on screen (scale of the 64 px texture).
var size := 0.25
var rise_speed := 22.0
var life := 1.6
## How hard the ship's roll pushes it sideways (px/s at full roll).
var sea_drift := 60.0

var _age := 0.0
var _phase := randf() * TAU
var _popped := false
var _sound: AudioStreamPlayer

func _ready() -> void:
	texture = BUBBLE
	scale = Vector2.ONE * size * 0.2
	_sound = AudioStreamPlayer.new()
	_sound.stream = POP_SOUND
	_sound.volume_db = -6.0
	add_child(_sound)

func _process(delta: float) -> void:
	if _popped:
		return
	_age += delta
	var grow := clampf(_age / 0.25, 0.0, 1.0)
	# Wobbly, a bit wider than tall, like a soap bubble.
	var wobble := sin(_age * 9.0 + _phase) * 0.08
	scale = Vector2(1.0 + wobble, 1.0 - wobble) * size * lerpf(0.2, 1.0, ease(grow, 0.4))
	position += Vector2(sin(_age * 3.0 + _phase) * 10.0 + sin(Sea.roll) * sea_drift, -rise_speed) * delta
	if _age >= life:
		pop()

func pop() -> void:
	if _popped:
		return
	_popped = true
	texture = POPPED
	_sound.pitch_scale = randf_range(2.2, 2.6)
	_sound.play()
	var tween := create_tween()
	tween.tween_property(self, "scale", scale * 1.3, 0.12)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.12)
	await _sound.finished
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if _popped or not (event is InputEventMouseButton and event.pressed \
			and event.button_index == MOUSE_BUTTON_LEFT):
		return
	# In texture pixels (the ring is 64 px); a little forgiving, they're tiny.
	if to_local(event.position).length() <= 32.0 + 3.0 / scale.x:
		pop()
		get_viewport().set_input_as_handled()

extends TextureButton

## Menu button on the little scroll banner: wiggles when hovered, squashes
## and clacks when pressed.

const HOVER_SOUND: AudioStream = preload("res://audio/dialogue_tick.wav")
const PRESS_SOUND: AudioStream = preload("res://audio/typewriter_punch.wav")

@export var text: String = "Play":
	set(value):
		text = value
		if _label != null:
			_label.text = value

@onready var _label: Label = $Label

var _sound: AudioStreamPlayer
var _tween: Tween

func _ready() -> void:
	_label.text = text
	pivot_offset = size / 2.0
	_sound = AudioStreamPlayer.new()
	add_child(_sound)
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	button_down.connect(_on_down)

func _on_hover(hovered: bool) -> void:
	_animate(Vector2.ONE * (1.08 if hovered else 1.0), deg_to_rad(randf_range(-3.0, 3.0)) if hovered else 0.0)
	if hovered:
		_play(HOVER_SOUND, randf_range(1.1, 1.3))

func _on_down() -> void:
	scale = Vector2(1.12, 0.9)
	_animate(Vector2.ONE * 1.08, 0.0)
	_play(PRESS_SOUND, randf_range(0.95, 1.05))

func _animate(target_scale: Vector2, target_rotation: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "scale", target_scale, 0.25)
	_tween.tween_property(self, "rotation", target_rotation, 0.25)

func _play(stream: AudioStream, pitch: float) -> void:
	_sound.stream = stream
	_sound.pitch_scale = pitch
	_sound.play()

extends Node2D

## Money counter in the bottom-right corner. Collected coins arc up to it, flipping, with
## a golden ribbon trailing behind them; the counter ticks up when they land.

const COIN_TEXTURE: Texture2D = preload("res://assets/ui/lei_icon.png")
const COLLECT_SOUND: AudioStream = preload("res://audio/coins_collect.wav")

@export var flight_time: float = 0.55
@export var coin_size: float = 0.22
@export var trail_length: int = 16
@export var trail_color: Color = Color(1.0, 0.82, 0.25)

@onready var _icon: Sprite2D = $Icon
@onready var _label: Label = $Label
@onready var _sound: AudioStreamPlayer = $Sound

var money := 0

func _ready() -> void:
	_sound.stream = COLLECT_SOUND
	_update_label()

func fly_coin(from: Vector2) -> void:
	var trail := Line2D.new()
	trail.width = 5.0
	var width := Curve.new()
	width.add_point(Vector2(0.0, 0.1))
	width.add_point(Vector2(1.0, 1.0))
	trail.width_curve = width
	var gradient := Gradient.new()
	gradient.set_color(0, Color(trail_color, 0.0))
	gradient.set_color(1, trail_color)
	trail.gradient = gradient
	trail.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(trail)

	var coin := Sprite2D.new()
	coin.texture = COIN_TEXTURE
	coin.scale = Vector2.ONE * coin_size
	coin.position = from
	add_child(coin)

	var to := _icon.position
	# Pop up first, then swoop down into the counter.
	var control := from.lerp(to, 0.3) + Vector2(randf_range(-40.0, 40.0), -140.0)
	var tween := create_tween()
	tween.tween_method(_fly_step.bind(coin, trail, from, control, to), 0.0, 1.0, flight_time) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(func() -> void:
		coin.queue_free()
		_arrive())
	tween.tween_property(trail, "modulate:a", 0.0, 0.2)
	tween.tween_callback(trail.queue_free)

## One step along the arc (t = 0..1): move, flip, and extend the ribbon.
func _fly_step(t: float, coin: Sprite2D, trail: Line2D, from: Vector2, control: Vector2, to: Vector2) -> void:
	var pos := from.lerp(control, t).lerp(control.lerp(to, t), t)
	coin.position = pos
	coin.scale = Vector2(absf(cos(t * 14.0)) * coin_size + 0.02, coin_size)
	trail.add_point(pos)
	while trail.get_point_count() > trail_length:
		trail.remove_point(0)

func _arrive() -> void:
	money += 1
	_update_label()
	_sound.pitch_scale = randf_range(0.95, 1.1)
	_sound.play()
	_icon.scale = Vector2.ONE * 0.42
	create_tween().tween_property(_icon, "scale", Vector2.ONE * 0.3, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

## Set the amount directly (e.g. after paying the night's bills).
func set_money(amount: int) -> void:
	money = amount
	_update_label()

func _update_label() -> void:
	_label.text = str(money)

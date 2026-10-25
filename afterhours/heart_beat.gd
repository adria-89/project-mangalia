class_name HeartBeat
extends Sprite2D

## The rhythm cue and arousal display in one: beats at the pace she wants,
## grows as she gets closer, glows when you're on her pace.

const HEART: Texture2D = preload("res://assets/ui/heart.png")

## Beats per second (her wanted strokes per second).
var tempo := 1.0
## Arousal 0..1: how big the heart is.
var fill := 0.0

var _phase := 0.0
var _pulse := 0.0
var _glow := 0.0

func _ready() -> void:
	texture = HEART

func _process(delta: float) -> void:
	_phase += delta * tempo
	if _phase >= 1.0:
		_phase -= 1.0
		_pulse = 1.0
	_pulse = move_toward(_pulse, 0.0, delta * 5.0)
	_glow = move_toward(_glow, 0.0, delta * 2.0)
	scale = Vector2.ONE * (0.45 + 0.35 * fill) * (1.0 + 0.22 * _pulse)
	modulate = Color(1.0, 1.0, 1.0).lerp(Color(1.6, 1.3, 1.4), _glow)

## A stroke landed on her pace.
func glow() -> void:
	_glow = 1.0

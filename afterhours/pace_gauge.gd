@tool
class_name PaceGauge
extends Node2D

## Your rhythm against hers: a small bar, slow on the left, fast on the
## right, with her pace in the middle (the band is how far off she still
## takes it) and a marker where yours is. The middle of the bar is on the node.

@export var size := Vector2(64, 8):
	set(value):
		size = value
		queue_redraw()
@export var band_color := Color(1.0, 0.45, 0.65)
@export var marker_color := Color(1.0, 0.95, 0.85)
@export var back_color := Color(0.12, 0.08, 0.1, 0.85)
@export var line_color := Color(0.06, 0.04, 0.05)
## The ratio at the bar's ends (and 1 / it at the left end).
@export var span: float = 2.5
## Editor only: where the marker shows (your pace over hers), to lay it out.
@export_range(0.0, 3.0, 0.05) var preview_ratio: float = 1.3

## Your strokes per second over hers; 0 = no rhythm yet (no marker).
var ratio := 0.0
## Her pace_tolerance: the band covers what she takes as on her pace.
var tolerance := 0.35

var _shown := 0.0
var _visible_marker := 0.0

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		ratio = preview_ratio
	var to := _x_for(ratio) if ratio > 0.0 else _shown
	_shown = lerpf(_shown, to, 1.0 - exp(-delta * 8.0))
	_visible_marker = move_toward(_visible_marker, 1.0 if ratio > 0.0 else 0.0, delta * 4.0)
	queue_redraw()

## Ratio to x (log scale, so twice as fast is as far as half as fast).
func _x_for(r: float) -> float:
	return clampf(log(r) / log(span), -1.0, 1.0) * size.x / 2.0

func _draw() -> void:
	var half := size / 2.0
	draw_rect(Rect2(-half - Vector2.ONE, size + Vector2(2, 2)), line_color)
	draw_rect(Rect2(-half, size), back_color)
	# On her pace: the band.
	var left := _x_for(1.0 - tolerance * 0.8)
	var right := _x_for(1.0 + tolerance * 0.8)
	draw_rect(Rect2(Vector2(left, -half.y), Vector2(right - left, size.y)), band_color)
	draw_rect(Rect2(Vector2(left, -half.y), Vector2(right - left, 2)), band_color.lightened(0.35))
	if _visible_marker <= 0.0:
		return
	var color := marker_color
	color.a *= _visible_marker
	var x := roundf(_shown)
	draw_rect(Rect2(Vector2(x - 2, -half.y - 3), Vector2(4, size.y + 6)), Color(line_color, color.a))
	draw_rect(Rect2(Vector2(x - 1, -half.y - 2), Vector2(2, size.y + 4)), color)

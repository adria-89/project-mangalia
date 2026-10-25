@tool
class_name MeterBar
extends Node2D

## A vertical pixel meter that fills from the bottom: hers (how close she is)
## and yours. Glows and throbs when it's nearly full; the top is at the node.
## Drawn as a thick slab like the main menu logo (menu/title_logo.gd): copies
## of it stacked behind, darker toward the back, swinging as it turns and
## tilts, and it rocks with the sea.

@export var size := Vector2(10, 90):
	set(value):
		size = value
		queue_redraw()
@export var fill_color := Color(1.0, 0.45, 0.65):
	set(value):
		fill_color = value
		queue_redraw()
@export var back_color := Color(0.12, 0.08, 0.1, 0.85)
@export var line_color := Color(0.06, 0.04, 0.05)
## 0..1. Set in the editor to preview it.
@export_range(0.0, 1.0) var value: float = 0.5:
	set(new_value):
		value = clampf(new_value, 0.0, 1.0)
		queue_redraw()

@export_group("Slab")
## How thick the slab is, in pixels.
@export var depth_px: float = 6.0
## Slab color right behind the face, and at the back (the logo's).
@export var slab_front := Color(0.42, 0.24, 0.07)
@export var slab_back := Color(0.16, 0.08, 0.03)
## How far it's turned down at rest, so the slab shows under it.
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
## Where in the swing it starts (radians), so two meters can swing apart.
@export var phase: float = 0.0
## Breathing in and out (0.03 = 3% bigger at its peak).
@export var pulse: float = 0.03

var _time := 0.0
var _rest_position := Vector2.ZERO

func _ready() -> void:
	_rest_position = position

func _process(delta: float) -> void:
	_time += delta
	if not Engine.is_editor_hint():
		var t := _time * TAU / period + phase
		rotation = deg_to_rad(rock_degrees) * sin(t * 0.6 + 2.0) + Sea.roll * sea_roll
		position = _rest_position + Vector2(0.0, -Sea.heave * sea_heave)
	queue_redraw()

func _draw() -> void:
	var t := _time * TAU / period + phase
	var turn := deg_to_rad(turn_degrees) * sin(t)
	var tilt := deg_to_rad(tilt_degrees) * sin(t * 0.73 + 1.3)
	# Turned away it gets narrower; the back of the slab slides the other way.
	var squash := Vector2(cos(turn), cos(tilt)) * (1.0 + pulse * sin(t * 2.0))
	var back := depth_px * Vector2(-sin(turn), sin(tilt + deg_to_rad(rest_tilt_degrees)))
	var center := size / 2.0
	var outer := Rect2(Vector2(-1, -1), size + Vector2(2, 2))
	var steps := maxi(ceili(back.length()), 1)
	# All the slab outlines first, so they make one outline around the slab.
	for i in range(steps, 0, -1):
		_squashed(squash, center, (back * i / steps).round())
		draw_rect(outer.grow(1.0), line_color)
	for i in range(steps, 0, -1):
		_squashed(squash, center, (back * i / steps).round())
		draw_rect(outer, slab_front.lerp(slab_back, float(i) / steps))
	_squashed(squash, center, Vector2.ZERO)
	draw_rect(outer, line_color)
	draw_rect(Rect2(Vector2.ZERO, size), back_color)
	var height := roundf(size.y * value)
	if height <= 0.0:
		return
	var color := fill_color
	if value > 0.8:
		# Nearly there: it throbs brighter.
		color = color.lightened(0.25 * (0.5 + 0.5 * sin(_time * 12.0)))
	var fill := Rect2(Vector2(0, size.y - height), Vector2(size.x, height))
	draw_rect(fill, color)
	# A highlight down the left side, like the other pixel UI.
	draw_rect(Rect2(fill.position, Vector2(2, fill.size.y)), color.lightened(0.35))
	# Tick marks every quarter.
	for i in range(1, 4):
		var y := roundf(size.y * i / 4.0)
		draw_rect(Rect2(Vector2(0, y), Vector2(3, 1)), line_color)

## Draws from here on squashed about the meter's middle and moved by offset.
func _squashed(squash: Vector2, center: Vector2, offset: Vector2) -> void:
	draw_set_transform_matrix(Transform2D(0.0, squash, 0.0, center + offset) * Transform2D(0.0, -center))

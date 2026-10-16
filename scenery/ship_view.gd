extends Node

## Makes the room feel like it's on a rocking ship. We're aboard, so the room
## mostly stays put in view; the world outside (sky, waves) tilts against the
## roll around the porthole and rises and falls with the heave. On top of
## that, the whole view sways slightly, like a camera that lags behind.

## Things outside the ship, seen through the porthole.
@export var outside: Array[NodePath] = []
## Center of the porthole opening, in screen pixels.
@export var porthole_center := Vector2(123, 119.5)

@export_group("View sway")
## How much of the roll the whole view follows (0 = off). Rotating pixel art
## makes it shimmer a little, so keep it small.
@export var view_roll_factor: float = 0.25
## Zoom so the screen edges never show while swaying.
@export var view_zoom: float = 1.025

var _outside_nodes: Array[Node2D] = []
var _base_positions: Array[Vector2] = []
var _view: Node2D
var _shake := 0.0
var _shake_fade := 30.0 # pixels per second it dies down by
## Slapstick shakes (see shake()): the view swings smoothly left and right
## with a little bounce and eases out, rather than buzzing.
var _slapstick := false
var _slap_size := 0.0
var _slap_time := 0.0
const SLAP_SPEED := 32.0 # radians/s of the side-to-side swing

func _ready() -> void:
	_view = get_parent() as Node2D
	for path in outside:
		var node := get_node(path) as Node2D
		_outside_nodes.append(node)
		_base_positions.append(node.position)

## Jolt the whole view (e.g. a kiss smacking the screen). Fades out quickly.
## With fade_seconds it's a slapstick shake instead (e.g. something smashing):
## big side-to-side bangs that die down over that long.
func shake(pixels: float, fade_seconds: float = 0.0) -> void:
	if pixels < _shake:
		return
	_shake = pixels
	_slapstick = fade_seconds > 0.0
	_shake_fade = pixels / fade_seconds if _slapstick else 30.0
	_slap_size = pixels
	_slap_time = 0.0

func _process(delta: float) -> void:
	_shake = maxf(_shake - delta * _shake_fade, 0.0)
	var offset := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * _shake
	if _slapstick:
		_slap_time += delta
		# Ease out: big swings first, then they settle gently.
		var k := _shake / _slap_size if _slap_size > 0.0 else 0.0
		var size := _slap_size * k * k
		# Left and right, with a little bounce: it hops up on every swing.
		offset = Vector2(sin(_slap_time * SLAP_SPEED), -absf(sin(_slap_time * SLAP_SPEED)) * 0.25) * size
	# Outside: the true horizon stays level, so in the ship's frame it tilts the other way.
	var outside_angle := -Sea.roll
	var lift := Vector2(0.0, Sea.heave)
	for i in _outside_nodes.size():
		var node := _outside_nodes[i]
		node.rotation = outside_angle
		node.position = porthole_center + (_base_positions[i] - porthole_center).rotated(outside_angle) + lift

	# Whole view: a small lagging sway around the screen center, zoomed in a hair.
	var center := get_viewport().get_visible_rect().size / 2.0
	var angle := Sea.roll * view_roll_factor
	var zoom := view_zoom if view_roll_factor != 0.0 else 1.0
	_view.rotation = angle
	_view.scale = Vector2(zoom, zoom)
	_view.position = center - (center * zoom).rotated(angle) + offset

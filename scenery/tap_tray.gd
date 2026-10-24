extends Node2D

## Papers Please-style tap: hides off the left edge, slides in when the mouse
## goes near it, and pours while you hold the click on it: a trickle at first,
## more the further you drag down (a trickle lets a lighter drink float on
## top as its own layer, a gush mixes it in). A container dropped near the
## spout snaps under it. The stream itself is the PourStream child.

const SQUEAK_OPEN: AudioStream = preload("res://audio/metal_squeak_big1.wav")
const SQUEAK_CLOSE: AudioStream = preload("res://audio/metal_squeak_big3.wav")

@export var bar_props_path: NodePath
@export var drink: Drink = preload("res://props/drinks/beer.tres")

@export_group("Opening")
## Pressing the handle opens it this much (0..1); dragging down opens it further.
@export_range(0.0, 1.0) var min_open: float = 0.2
## Drag (px) from the press to all the way open.
@export var open_drag: float = 40.0
## How far the handle leans when all the way open (radians).
@export var open_lean: float = 0.08

@export_group("Tray")
## Mouse closer than this to the left edge brings the tap out.
@export var hover_zone_width: float = 50.0
@export var shown_x: float = 0.0
@export var hidden_x: float = -84.0
@export var hide_delay: float = 0.35
## Height of a container's rim above the counter (3D units): the snap lines
## the opening up under the spout, not the base.
@export var rim_height: float = 0.38

@export_group("Sound")
## Rapid clicks don't squeak again sooner than this (s).
@export var squeak_cooldown: float = 0.25

## Spout opening in tap.png, relative to the tray's origin.
const SPOUT := Vector2(75, 96)
## Pivot for squash/wobble: where the pipe enters on the left.
const PIVOT := Vector2(0, 60)
const TAP_RECT := Rect2(0, 0, 90, 98)

## Debug (F1, then T): switches what the tap pours, to try layers without the bottles.
const DEBUG_DRINKS: Array[Drink] = [
	preload("res://props/drinks/beer.tres"),
	preload("res://props/drinks/cola.tres"),
	preload("res://props/drinks/rum.tres"),
]

@onready var _tap: Sprite2D = $Tap
@onready var _stream: PourStream = $PourStream
@onready var _props: Node = get_node(bar_props_path)

var _shown := false
var _tween: Tween
var _hide_timer := 0.0
var _pouring := false
## How far open the tap is (0..1), see Opening; eases shut after letting go.
var _open := 0.0
var _press_y := 0.0

var _squash := 0.0
var _squash_velocity := 0.0
var _wobble := 0.0
var _wobble_velocity := 0.0

var _time := 0.0
var _mouse := Vector2(INF, INF)

var _squeak: AudioStreamPlayer
var _last_squeak := -INF

func _ready() -> void:
	position.x = hidden_x
	_tap.position = PIVOT
	_tap.offset = -PIVOT
	_stream.props = _props
	_squeak = AudioStreamPlayer.new()
	add_child(_squeak)

func _process(delta: float) -> void:
	_time += delta
	_update_tray(delta)
	_update_open(delta)
	_update_springs(delta)
	_stream.pouring = _pouring
	_stream.open = _open
	_stream.drink = drink
	_stream.spout = position + SPOUT

func _update_tray(delta: float) -> void:
	var mouse := _mouse
	var tap_rect := Rect2(TAP_RECT.position + position, TAP_RECT.size).grow(30.0)
	# Stay out while pouring, while the mouse is on it, or while carrying a prop to it.
	var wanted: bool = mouse.x < hover_zone_width or _pouring \
		or (_shown and (tap_rect.has_point(mouse) or _props.is_holding()))
	if wanted:
		_hide_timer = hide_delay
		if not _shown:
			_slide(true)
	elif _shown:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_slide(false)

func _slide(show: bool) -> void:
	_shown = show
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var tweener := _tween.tween_property(self, "position:x", shown_x if show else hidden_x, 0.3 if show else 0.22)
	tweener.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT if show else Tween.EASE_IN)
	if show:
		_tween.tween_callback(func() -> void:
			_squash_velocity -= 4.0
			_wobble_velocity += 3.0)
	_props.snap_point = _snap_point() if show else null

func _snap_point() -> Vector3:
	# Where a container must stand so its opening is right under the spout.
	var spout_x := shown_x + SPOUT.x
	return _props.counter_point_for_screen_x(spout_x, rim_height, _props.lane_z)

func _update_springs(delta: float) -> void:
	if _pouring:
		# Rattle while the tap runs.
		_wobble_velocity += randf_range(-30.0, 30.0) * delta
		_squash_velocity += sin(_time * 40.0) * 6.0 * delta
	_squash_velocity += (-_squash * 300.0 - _squash_velocity * 12.0) * delta
	_squash += _squash_velocity * delta
	_wobble_velocity += (-_wobble * 220.0 - _wobble_velocity * 10.0) * delta
	_wobble += _wobble_velocity * delta
	var stretch := 1.0 + clampf(_squash, -0.25, 0.25)
	_tap.scale = Vector2(1.0 / stretch, stretch)
	_tap.rotation = clampf(_wobble, -0.3, 0.3) * 0.25 + _open * open_lean

## While pouring, dragging down from where the handle was pressed opens it
## further; let go and it eases shut (the handle swings back).
func _update_open(delta: float) -> void:
	if _pouring:
		var drag := (_mouse.y - _press_y) / open_drag
		_open = clampf(min_open + drag * (1.0 - min_open), min_open, 1.0)
	else:
		_open = move_toward(_open, 0.0, delta * 6.0)

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		# In the parent's space: the whole view may be swaying (ship_view.gd).
		_mouse = get_parent().to_local(event.position)

func _unhandled_input(event: InputEvent) -> void:
	if Debug.key(event) and event.keycode == KEY_T:
		drink = DEBUG_DRINKS[(DEBUG_DRINKS.find(drink) + 1) % DEBUG_DRINKS.size()]
		Debug.note("Tap pours: " + drink.name)
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		var tap_rect := Rect2(TAP_RECT.position + position, TAP_RECT.size)
		if _shown and tap_rect.has_point(get_parent().to_local(event.position)):
			_pouring = true
			_press_y = _mouse.y
			_open = min_open
			_squash_velocity += 3.0
			_wobble_velocity -= 2.0
			_play_squeak(SQUEAK_OPEN)
			get_viewport().set_input_as_handled()
	elif _pouring:
		_pouring = false
		_squash_velocity -= 2.0
		_play_squeak(SQUEAK_CLOSE)
		get_viewport().set_input_as_handled()

## The handle turning. Skipped if it just squeaked, so fast clicking doesn't rattle.
func _play_squeak(sound: AudioStream) -> void:
	if _time - _last_squeak < squeak_cooldown:
		return
	_last_squeak = _time
	_squeak.stream = sound
	_squeak.pitch_scale = randf_range(0.92, 1.08)
	_squeak.play()

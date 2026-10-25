extends Node2D

## The naveta: a crate of cola bottles that hides below the bottom edge and
## jumps up when the mouse goes near it, like the tap does from the left. The
## bottles are 3D props rendered in their own little world and drawn between
## the crate's back and front sprites, so they stand inside it, in two rows.
## They rattle when the crate lands and with the sea, and the one under the
## mouse lifts a bit.
##
## Click a bottle to pick it up: it hangs from the mouse. Hold the click and
## drag down to tip it (like the tap's handle): a little pours a trickle, more
## a gush; moving left/right meanwhile aims it. It rights itself when you let
## go. Click on the crate (or right click anywhere) to be done with it: an
## opened one is thrown off screen, an unopened one goes back. Once they're
## all used up it comes back up full; it's also restocked every night (restock()).

const CLINKS: Array[AudioStream] = [
	preload("res://audio/bottles_clink1.wav"),
	preload("res://audio/bottles_clink2.wav"),
	preload("res://audio/bottles_clink3.wav"),
	preload("res://audio/bottles_clink4.wav"),
	preload("res://audio/bottles_clink5.wav"),
]
const SMASHES: Array[AudioStream] = [
	preload("res://audio/bottle_break1.wav"),
	preload("res://audio/bottle_break2.wav"),
	preload("res://audio/bottle_break3.wav"),
]

@export var bar_props_path: NodePath
## Mouse closer than this to the bottom edge (and over the crate) brings it up.
@export var hover_zone_height: float = 30.0
## The crate's left/right extent in naveta_back.png (screen x).
@export var crate_span := Vector2(148.0, 391.0)
## Screen y of the topmost bottle tip when shown: above this the mouse is off it.
@export var top_y: float = 255.0
## Screen y of the crate's top edge: clicking below it lets go of a bottle.
@export var crate_top_y: float = 321.0
@export var shown_y: float = 0.0
@export var hidden_y: float = 170.0
@export var hide_delay: float = 0.35

@export_group("Bottles")
@export var bottle_scene: PackedScene = preload("res://props/cola.tscn")
## Screen x of each bottle in the front row.
@export var slot_x: Array[float] = [185.0, 240.0, 295.0, 350.0]
## Screen y the bottles stand on (hidden behind the crate's front).
@export var base_y: float = 392.0
## Distance from the camera (3D units): further = smaller bottles.
@export var depth: float = 3.5
## The back row: between the front ones, a bit further and higher, so their
## necks show between them.
@export var back_slot_x: Array[float] = [212.0, 268.0, 323.0]
@export var back_base_y: float = 376.0
@export var back_depth: float = 3.9
## How high the bottle under the mouse lifts (3D units).
@export var hover_lift: float = 0.05
## How far (degrees) the resting bottles lean their tops toward the camera,
## so they face it more than its look down shows. Gone once picked up.
@export var rest_lean_deg: float = 10.0
## Kick to each bottle's wobble when the crate lands.
@export var landing_rattle: float = 2.5
## How much the ship's roll shakes the bottles.
@export var sea_rattle: float = 0.6

@export_group("Pouring")
## How quickly a carried bottle catches up with the mouse.
@export var follow_speed: float = 16.0
## How much it leans into being carried sideways.
@export var carry_lean: float = 0.02
## Holding the click tips it to trickle_deg (drink comes out past the bottle's
## pour_from_deg), dragging down open_drag px tips it all the way to full_deg.
@export var trickle_deg: float = 80.0
@export var full_deg: float = 125.0
@export var open_drag: float = 40.0
## How open the stream is (0..1, see PourStream) at trickle_deg.
@export_range(0.0, 1.0) var min_open: float = 0.2

@export_group("Cap")
## A bottle with a "Cap" mesh pops it the first time it pours: it shoots out
## along the neck (3D units/s) plus a kick up, spins, and falls off screen,
## drawn over everything (CapViewport). A fresh bottle comes capped.
@export var cap_speed: float = 2.2
@export var cap_kick: float = 3.0
@export var cap_gravity: float = 9.0
@export var cap_spin: float = 18.0

@export_group("Throwing")
## An opened bottle you're done with is flung off the nearer side of the
## screen (3D units/s sideways, plus a kick up), spinning, drawn over
## everything; it smashes somewhere off screen.
@export var throw_speed: float = 3.0
@export var throw_kick: float = 2.5
@export var throw_gravity: float = 9.0
@export var throw_spin: float = 9.0
@export var smash_volume_db: float = -8.0

@onready var _camera: Camera3D = $SubViewport/Camera3D
@onready var _bottles: Node3D = $SubViewport/Bottles
@onready var _display: Sprite2D = $Display
@onready var _stream: PourStream = $PourStream
@onready var _cap_pop: AudioStreamPlayer = $CapPop
@onready var _smash: AudioStreamPlayer = $Smash
@onready var _clink: AudioStreamPlayer = $Clink
@onready var _props: Node = get_node(bar_props_path)

## Put away until the bar serves its drink (main.gd sets it): it won't come out.
var locked := false
var _shown := false
var _tween: Tween
var _hide_timer := 0.0
var _mouse := Vector2(INF, INF)
## Per bottle: where it stands (and how far), its lift / wobble / tip springs
## and the current grip point (3D); whether it's been opened, or thrown (gone
## till restock) and its flight; and its cap (if it has one): resting
## transform, whether it's on, and its flight once popped.
var _slots: Array[Dictionary] = []
## The slot of the bottle hanging from the mouse, or empty.
var _carried := {}
var _tipping := false
var _press_y := 0.0
## Where the carried bottle hangs (screen, this node's space).
var _hang := Vector2.ZERO

func _ready() -> void:
	position.y = hidden_y
	_display.texture = $SubViewport.get_texture()
	# Flying caps and bottles: same world and camera, drawn on top (only render layer 2).
	$CapViewport.world_3d = $SubViewport.find_world_3d()
	var cap_camera: Camera3D = $CapViewport/Camera3D
	cap_camera.transform = _camera.transform
	cap_camera.fov = _camera.fov
	$CapDisplay.texture = $CapViewport.get_texture()
	_stream.props = _props
	_smash.volume_db = smash_volume_db
	for x in back_slot_x:
		_add_slot(x, back_base_y, back_depth)
	for x in slot_x:
		_add_slot(x, base_y, depth)
	restock()

func _add_slot(x: float, y: float, slot_depth: float) -> void:
	var bottle: Bottle = bottle_scene.instantiate()
	_bottles.add_child(bottle)
	var slot := {
		"bottle": bottle, "x": x, "base": _camera.project_position(Vector2(x, y), slot_depth),
		"lift": 0.0, "lift_velocity": 0.0,
		"wobble": 0.0, "wobble_velocity": 0.0, "lean": deg_to_rad(rest_lean_deg),
		"tip": 0.0, "tip_velocity": 0.0,
		"opened": false, "gone": false, "thrown": false,
		"throw_transform": Transform3D(), "throw_velocity": Vector3.ZERO, "throw_spin": 0.0,
	}
	var cap := bottle.find_child("Cap", true, false) as Node3D
	if cap:
		slot.merge({
			"cap": cap, "cap_parent": cap.get_parent(), "cap_rest": cap.transform,
			"capped": true, "cap_flying": false,
			"cap_transform": Transform3D(), "cap_velocity": Vector3.ZERO, "cap_axis": Vector3.UP,
		})
	_slots.append(slot)

## A full crate again: every bottle back in its place, full and capped.
func restock() -> void:
	_carried = {}
	_tipping = false
	if Bottle.in_hand != null and _slots.any(func(s: Dictionary) -> bool: return s.bottle == Bottle.in_hand):
		Bottle.in_hand = null
	for slot in _slots:
		var bottle: Bottle = slot.bottle
		bottle.get_node("Liquid").fill = 1.0
		bottle.visible = true
		slot.merge({"opened": false, "gone": false, "thrown": false, "tip": 0.0, "tip_velocity": 0.0,
			"lift": 0.0, "lift_velocity": 0.0, "wobble": 0.0, "wobble_velocity": 0.0,
			"lean": deg_to_rad(rest_lean_deg)}, true)
		slot.grip = slot.base + Vector3(0.0, bottle.grip_height, 0.0)
		if slot.has("cap"):
			var cap: Node3D = slot.cap
			# Popped caps fly loose in the world (_pop_cap): back on the bottle.
			if cap.get_parent() != slot.cap_parent:
				cap.reparent(slot.cap_parent, false)
			cap.transform = slot.cap_rest
			cap.visible = true
			slot.capped = true
			slot.cap_flying = false
		_set_layers(bottle, 1)

func _process(delta: float) -> void:
	_update_tray(delta)
	_update_bottles(delta)
	_update_stream(delta)
	_update_caps(delta)
	_update_thrown(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		# In the parent's space: the whole view may be swaying (ship_view.gd).
		_mouse = get_parent().to_local(event.position)
	# Clicks are taken here, before the props layer or the tap see them.
	if not event is InputEventMouseButton:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not _carried.is_empty():
		_let_go()
		get_viewport().set_input_as_handled()
	elif event.button_index != MOUSE_BUTTON_LEFT:
		return
	elif event.pressed:
		if not _carried.is_empty():
			if _mouse.y > crate_top_y + position.y:
				_let_go()
			else:
				_tipping = true
				_press_y = _mouse.y
			get_viewport().set_input_as_handled()
		else:
			var slot := _hovered_slot()
			if not slot.is_empty():
				_carried = slot
				Bottle.in_hand = slot.bottle
				_hang = _mouse - position
				get_viewport().set_input_as_handled()
	elif _tipping:
		_tipping = false
		get_viewport().set_input_as_handled()

## Done with the carried bottle: thrown away if opened, else back in its place.
func _let_go() -> void:
	if _carried.opened:
		_throw(_carried)
	_carried = {}
	Bottle.in_hand = null
	_tipping = false

func _throw(slot: Dictionary) -> void:
	var bottle: Bottle = slot.bottle
	slot.gone = true
	slot.thrown = true
	slot.throw_transform = bottle.global_transform
	# Off the side nearer to where it was held.
	var side := -1.0 if _hang.x < $SubViewport.size.x / 2.0 else 1.0
	slot.throw_velocity = Vector3(side * throw_speed, throw_kick, 0.0)
	slot.throw_spin = -side * throw_spin
	_set_layers(bottle, 2)

func _update_tray(delta: float) -> void:
	var over_span := _mouse.x > crate_span.x and _mouse.x < crate_span.y
	var crate_rect := Rect2(crate_span.x, top_y + position.y, crate_span.y - crate_span.x, 400.0)
	var wanted := not locked and ((over_span and _mouse.y > 400.0 - hover_zone_height) \
		or (_shown and crate_rect.has_point(_mouse)) or not _carried.is_empty())
	if wanted:
		_hide_timer = hide_delay
		if not _shown:
			_slide(true)
	elif _shown:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_slide(false)

func _slide(show: bool) -> void:
	# Every bottle used up (and done flying): it comes back up full.
	if show and _slots.all(func(s: Dictionary) -> bool: return s.gone and not s.thrown):
		restock()
	# The bottles clink as it sets off up (if there are any left).
	if show and _slots.any(func(s: Dictionary) -> bool: return not s.gone):
		_clink.stream = CLINKS.pick_random()
		_clink.pitch_scale = randf_range(0.95, 1.1)
		_clink.play()
	_shown = show
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var tweener := _tween.tween_property(self, "position:y", shown_y if show else hidden_y, 0.3 if show else 0.22)
	tweener.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT if show else Tween.EASE_IN)
	if show:
		_tween.tween_callback(func() -> void:
			for slot in _slots:
				slot.wobble_velocity += randf_range(-landing_rattle, landing_rattle))

func _update_bottles(delta: float) -> void:
	var hovered := _hovered_slot()
	var follow := 1.0 - exp(-follow_speed * delta)
	for slot in _slots:
		if slot.gone:
			continue
		var bottle: Bottle = slot.bottle
		var carried: bool = slot == _carried
		var target_lift := hover_lift if slot == hovered else 0.0
		slot.lift_velocity += ((target_lift - slot.lift) * 300.0 - slot.lift_velocity * 18.0) * delta
		slot.lift += slot.lift_velocity * delta
		slot.wobble_velocity += Sea.roll_velocity * sea_rattle * randf() * delta * 10.0
		slot.wobble_velocity += (-slot.wobble * 220.0 - slot.wobble_velocity * 9.0) * delta
		slot.wobble += slot.wobble_velocity * delta

		var target_tip := 0.0
		var target_grip: Vector3 = slot.base + Vector3(0.0, bottle.grip_height + slot.lift, 0.0)
		if carried:
			if not _tipping:
				_hang = _hang.lerp(_mouse - position, follow)
			else:
				# Up/down tips it; left/right still moves it, to aim the stream.
				_hang.x = lerpf(_hang.x, _mouse.x - position.x, follow)
				var drag := clampf((_mouse.y - _press_y) / open_drag, 0.0, 1.0)
				target_tip = deg_to_rad(lerpf(trickle_deg, full_deg, drag))
			# Carried at the front row's distance (one from the back comes forward).
			target_grip = _camera.project_position(_hang, depth)
		var previous: Vector3 = slot.grip
		slot.grip = previous.lerp(target_grip, follow)
		if carried:
			# Leans into being carried sideways.
			slot.wobble_velocity -= (slot.grip.x - previous.x) / delta * carry_lean
		slot.tip_velocity += ((target_tip - slot.tip) * 160.0 - slot.tip_velocity * 16.0) * delta
		slot.tip += slot.tip_velocity * delta

		# Turns around its grip point; positive tips the top to the left.
		var angle: float = slot.tip + clampf(slot.wobble, -0.4, 0.4) * 0.3
		slot.lean = lerpf(slot.lean, 0.0 if carried else deg_to_rad(rest_lean_deg), follow)
		var basis := Basis(Vector3.RIGHT, slot.lean) * Basis(Vector3.BACK, angle)
		bottle.transform = Transform3D(basis, slot.grip - basis * Vector3(0.0, bottle.grip_height, 0.0))

## Drink comes out of the carried bottle once it's tipped past its pour_from_deg
## (and until it's empty): the further over, the more open the stream.
func _update_stream(delta: float) -> void:
	if _carried.is_empty():
		_stream.pouring = false
		return
	var bottle: Bottle = _carried.bottle
	var tip_deg := rad_to_deg(_carried.tip as float)
	var liquid: Node = bottle.get_node("Liquid")
	if tip_deg > bottle.pour_from_deg:
		_carried.opened = true
		if _carried.get("capped", false):
			_pop_cap(_carried)
	_stream.pouring = tip_deg > bottle.pour_from_deg and liquid.fill > 0.002
	var amount := clampf(inverse_lerp(trickle_deg, full_deg, tip_deg), 0.0, 1.0)
	_stream.open = lerpf(min_open, 1.0, amount)
	if _stream.pouring:
		liquid.fill -= bottle.pour_rate * _stream.open * delta / bottle.glasses
	_stream.drink = bottle.drink
	_stream.pour_rate = bottle.pour_rate
	_stream.stream_width = bottle.stream_width
	_stream.glug_size = bottle.glug_size
	_stream.glug_spacing = bottle.glug_spacing
	_stream.pitch = bottle.pitch
	_stream.spout = position + _camera.unproject_position(bottle.global_transform * bottle.mouth)

func _pop_cap(slot: Dictionary) -> void:
	var cap: Node3D = slot.cap
	var bottle: Bottle = slot.bottle
	slot.capped = false
	slot.cap_flying = true
	slot.cap_transform = cap.global_transform
	slot.cap_velocity = bottle.global_basis.y.normalized() * cap_speed + Vector3.UP * cap_kick
	slot.cap_axis = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
	_set_layers(cap, 2)
	# Loose from the bottle, so it keeps flying if the bottle is thrown and hidden.
	cap.reparent(_bottles)
	if _cap_pop.stream:
		_cap_pop.pitch_scale = randf_range(0.95, 1.1)
		_cap_pop.play()

## Popped caps fly free of their bottle until they leave the screen.
func _update_caps(delta: float) -> void:
	for slot in _slots:
		if not slot.get("cap_flying", false):
			continue
		var cap: Node3D = slot.cap
		slot.cap_velocity.y -= cap_gravity * delta
		var t: Transform3D = slot.cap_transform
		t.origin += slot.cap_velocity * delta
		t.basis = Basis(slot.cap_axis, cap_spin * delta) * t.basis
		slot.cap_transform = t
		cap.global_transform = t
		if _off_screen(t.origin):
			cap.visible = false
			slot.cap_flying = false

## Thrown bottles fly until they leave the screen, then smash out there.
## They stay parked off screen until restock().
func _update_thrown(delta: float) -> void:
	for slot in _slots:
		if not slot.thrown:
			continue
		var bottle: Bottle = slot.bottle
		slot.throw_velocity.y -= throw_gravity * delta
		var t: Transform3D = slot.throw_transform
		t.origin += slot.throw_velocity * delta
		t.basis = Basis(Vector3.BACK, slot.throw_spin * delta) * t.basis
		slot.throw_transform = t
		bottle.global_transform = t
		# Its middle, well past the edge: the whole bottle is out of sight.
		if _off_screen(t * Vector3(0.0, bottle.grip_height, 0.0), 120.0):
			slot.thrown = false
			bottle.visible = false
			_smash.stream = SMASHES.pick_random()
			_smash.pitch_scale = randf_range(0.9, 1.1)
			_smash.play()

## margin: how far (px) past the screen's edge it must be.
func _off_screen(point: Vector3, margin: float = 60.0) -> bool:
	var size := Vector2($SubViewport.size)
	var on_screen := _camera.unproject_position(point) + Vector2(0.0, position.y)
	return on_screen.y > size.y + margin or on_screen.x < -margin or on_screen.x > size.x + margin

## Render layers of a node and everything under it (its outline too).
func _set_layers(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child in node.get_children(true):
		_set_layers(child, layers)

## The resting bottle the mouse is over (nearest slot within reach; the front
## row wins a tie), or an empty dict.
func _hovered_slot() -> Dictionary:
	if not _shown or Bottle.in_hand != null or _mouse.y < top_y + position.y:
		return {}
	var best := {}
	var best_distance := 40.0
	for slot in _slots:
		var distance := absf(_mouse.x - slot.x)
		if not slot.gone and distance <= best_distance:
			best = slot
			best_distance = distance
	return best

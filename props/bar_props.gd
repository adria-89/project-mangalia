extends Node2D

## The 3D layer over the 2D bar: a transparent SubViewport the same size as
## the screen, whose camera is matched to the drawn counter's perspective.
## Props on the counter can be dragged with the mouse: they lift while held,
## lean into the motion and land with a little bounce. Let go while moving
## fast and the prop slides across the counter on its own (Tapper-style).

## A prop landed after being dragged or flicked (it may still wobble a little).
signal item_settled(item: Node3D)
## A prop slammed down with slam() just hit the counter.
signal slammed_down(item: Node3D)
## A prop fell off an end of the counter and smashed (screen point of the smash).
## A fresh, empty one drops in from above a moment later.
signal item_broke(item: Node3D, at: Vector2)


## Counter top in 3D is the plane y = 0; these are its x/z limits,
## matched to bar_counter.png (z: back edge .. front edge).
@export var counter_min := Vector2(-1.6, -3.95)
@export var counter_max := Vector2(1.6, -3.15)
## Props only move left/right, along this depth (default: middle of the counter).
@export var lane_z: float = -3.45
@export_group("Sea drift")
## How much of the ship's lean pulls props along the counter (0 = they never drift).
@export var drift_strength: float = 1.0
## Props stick until the pull is stronger than this (3D units/s²).
@export var static_friction: float = 0.3
## How sluggishly they glide once moving.
@export var drift_friction: float = 3.0
@export_group("")

## Each bounce twists the prop by up to about this much (radians/s of spin).
@export var bounce_spin: float = 4.0
@export var lift_height: float = 0.12
@export var follow_speed: float = 18.0
@export var max_tilt_deg: float = 25.0
## How close (3D units) a dropped prop must be to the snap point to slide onto it.
@export var snap_radius: float = 0.45
## Release faster than this (3D units/s) to flick instead of setting it down.
@export var flick_speed: float = 2.0
@export var max_slide_speed: float = 5.0
## How quickly a flicked prop slows down.
@export var slide_friction: float = 2.0
@export_group("Drinking")
## How a raised tankard tips while she drinks (degrees; x tips the top back
## toward her, y sideways).
@export var drink_tilt_deg := Vector2(-55.0, 10.0)
## Springiness of the lift up to her mouth (lower = slower, floatier).
@export var drink_lift_stiffness: float = 70.0
@export var drink_lift_damping: float = 13.0
## How fast she swings the empty out to the side before slamming it.
@export var slam_carry_speed: float = 10.0
## How hard it comes down from there (3D units/s).
@export var slam_speed: float = 4.0
@export_group("Falling off")
## A prop that slides past the left/right end teeters this long (seconds)
## before it falls: grab it in time to save it.
@export var teeter_time: float = 0.6
## Sliding off faster than this (3D units/s) skips the teeter: straight over.
@export var fall_speed: float = 3.0
## Seconds between the smash and the new one dropping in from above.
@export var respawn_delay: float = 0.7
@export_group("")

const BREAK_SOUNDS: Array[AudioStream] = [
	preload("res://audio/bottle_break1.wav"),
	preload("res://audio/bottle_break2.wav"),
	preload("res://audio/bottle_break3.wav"),
]

## Where a dropped prop snaps to (e.g. under the tap), or null for nowhere.
var snap_point: Variant = null

@onready var _viewport: SubViewport = $SubViewport
@onready var _camera: Camera3D = $SubViewport/Camera3D
@onready var _display: Sprite2D = $Display
@onready var _items: Node3D = $SubViewport/Items
@onready var _droplets: Node2D = $Droplets
@onready var _coins: Node3D = $SubViewport/Coins
@onready var _shards: Node2D = $Shards
var _break_sound: AudioStreamPlayer

## Per item: its resting rotation, scale and how far its origin sits above its bottom.
var _rest := {}

var _active: Node3D # held, or still settling after being dropped
var _holding := false
var _grab_offset := Vector3.ZERO
var _target := Vector3.ZERO
var _flat := Vector3.ZERO
var _height := 0.0
var _height_velocity := 0.0
var _tilt := Vector2.ZERO
var _tilt_velocity := Vector2.ZERO
var _yaw_velocity := 0.0
var _velocity := Vector3.ZERO
var _sliding := false
var _landed_reported := false
## slam(): 0 = none, 1 = being lifted, 2 = coming down hard.
var _slam_stage := 0
## Jumps (jolts, slams) use the same springy lift as grabbing for this long.
var _pop_timer := 0.0
const POP_TIME := 0.22
## Friction of the current slide (flicks and pushes can differ).
var _friction := 2.0
var _slide_velocity := Vector3.ZERO
## Props that can't be picked up right now (e.g. someone is drinking from it).
var _locked := {}
## The active prop is raised to someone's mouth (see raise_to_drink()).
var _drinking := false
var _drink_height := 0.0
## How high it was raised: it tips in proportion to how far up it is.
var _drink_peak := 0.0
## The raised prop is being swung out to the side, to be slammed down there.
var _slam_carry := false
## Falling off an end (see teeter_time): time left teetering on the edge,
## which end (-1 left, +1 right), and the tumble once it goes over.
var _teeter := 0.0
var _edge_side := 0
var _falling := false
var _fall_velocity := Vector3.ZERO
## The smashed prop, hidden until it drops back in after respawn_delay.
var _broken: Node3D
var _respawn_left := 0.0

func _ready() -> void:
	_display.texture = _viewport.get_texture()
	_break_sound = AudioStreamPlayer.new()
	add_child(_break_sound)
	for item: Node3D in _items.get_children():
		_rest[item] = {
			"rotation": item.rotation,
			"scale": item.scale,
			"lift": item.global_position.y - _lowest_y(item),
			"yaw": 0.0, # turn around the vertical axis, changed by bounces
			"start_x": item.position.x,
		}
		_place(item, Vector3(item.position.x, 0.0, lane_z), 0.0, Vector2.ZERO)
		var liquid := liquid_of(item)
		if liquid != null:
			liquid.spilled.connect(_on_spilled.bind(liquid))

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouse:
		return
	# The view may be swaying (ship_view.gd): work in this layer's own pixels.
	var pos := to_local(event.position)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _coins.try_collect(pos):
				get_viewport().set_input_as_handled()
				return
			var item := _item_under(pos)
			if item == null or not _activate(item):
				return
			_teeter = 0.0 # caught it on the edge
			_holding = true
			_sliding = false
			_landed_reported = false
			_grab_offset = _flat - _counter_hit(pos)
			_target = _flat
			_height_velocity = 3.0
			get_viewport().set_input_as_handled()
		elif _holding:
			_holding = false
			_target = _flat
			var snapped := false
			if snap_point != null:
				# Line up the container's body (not its origin) with the snap point.
				var body_offset := _body_offset(_active)
				if (_flat + body_offset).distance_to(snap_point) < snap_radius:
					_target = (snap_point as Vector3) - body_offset
					_target.z = lane_z
					snapped = true
			var speed := absf(_velocity.x)
			if not snapped and speed > flick_speed:
				_sliding = true
				_friction = slide_friction
				_slide_velocity = Vector3(_velocity.x, 0.0, 0.0).limit_length(max_slide_speed)
				_tilt_velocity += Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _holding:
		var hit := _counter_hit(pos) + _grab_offset
		_target = Vector3(clampf(hit.x, counter_min.x, counter_max.x), 0.0, lane_z)
		get_viewport().set_input_as_handled()

func _physics_process(delta: float) -> void:
	if _broken != null:
		_respawn_left -= delta
		if _respawn_left <= 0.0:
			_respawn()
	_start_drifting()
	if _active == null:
		return
	if _falling:
		_update_fall(delta)
		return
	var previous := _flat
	if _teeter > 0.0:
		_teeter -= delta
		if _teeter <= 0.0:
			_fall_over(0.8)
			return
	elif _sliding:
		_update_slide(delta)
	else:
		# Follow the mouse while held (or ease onto a snap point).
		var speed := slam_carry_speed if _slam_carry else follow_speed
		_flat = _flat.lerp(_target, 1.0 - exp(-speed * delta))
		if _slam_carry and absf(_flat.x - _target.x) < 0.03:
			# Over the spot: bring it down hard from up here.
			_slam_carry = false
			_drinking = false
			_slam_stage = 2
			_height_velocity = -slam_speed
	var velocity := (_flat - previous) / delta
	_velocity = velocity

	# Lift while held (or popping up in a jump); fall and bounce when let go.
	_pop_timer -= delta
	if _drinking:
		_height_velocity += ((_drink_height - _height) * drink_lift_stiffness \
			- _height_velocity * drink_lift_damping) * delta
	elif _holding or _pop_timer > 0.0:
		_height_velocity += ((lift_height - _height) * 200.0 - _height_velocity * 20.0) * delta
	else:
		_height_velocity -= 9.0 * delta
	if _slam_stage == 1 and _pop_timer <= 0.0:
		_slam_stage = 2
		_height_velocity = -3.5 # bring it down hard
	_height += _height_velocity * delta
	if _drinking and _drink_height == 0.0 and _height < 0.02:
		_drinking = false # set back down: the normal landing takes over
	if _height < 0.0:
		_height = 0.0
		if _slam_stage == 2:
			_slam_stage = 0
			slammed_down.emit(_active)
		if _height_velocity < -0.4:
			# Twist a little on every bounce, harder for harder landings. Always
			# clockwise seen from above (negative around +Y), so it reads as one motion.
			_yaw_velocity -= bounce_spin * randf_range(0.4, 1.0) * clampf(-_height_velocity / 2.0, 0.3, 1.0)
			_tilt_velocity += Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * -_height_velocity * 2.0
			_height_velocity = -_height_velocity * 0.3
		else:
			_height_velocity = 0.0

	# Lean into the motion like a carried mug, spring back upright.
	var max_tilt := deg_to_rad(max_tilt_deg)
	var tilt_target := Vector2(velocity.z, -velocity.x) * 0.15 if _holding else Vector2.ZERO
	tilt_target = tilt_target.limit_length(max_tilt)
	if _teeter > 0.0:
		# Rocking on the edge, tipping further out the closer it gets to going over.
		var lean := lerpf(0.3, 0.55, 1.0 - _teeter / teeter_time) + sin(_teeter * 30.0) * 0.12
		tilt_target = Vector2(0.0, -_edge_side * lean)
	if _drinking:
		# Tipped toward her mouth, more the higher it is (tips up and back down).
		max_tilt = maxf(max_tilt, _drink_tilt().length() + 0.3)
		tilt_target = _drink_tilt() * clampf(_height / _drink_peak, 0.0, 1.0)
		if _slam_carry:
			# Upright again, leaning into the swing like a carried mug.
			tilt_target = (Vector2(velocity.z, -velocity.x) * 0.15).limit_length(deg_to_rad(max_tilt_deg))
	_tilt_velocity += ((tilt_target - _tilt) * 160.0 - _tilt_velocity * 9.0) * delta
	_tilt = (_tilt + _tilt_velocity * delta).limit_length(max_tilt)

	var rest: Dictionary = _rest[_active]
	rest.yaw += _yaw_velocity * delta
	_yaw_velocity *= exp(-5.0 * delta)
	_place(_active, _flat, _height, _tilt)

	var landed := not _holding and not _sliding and not _drinking and _flat.distance_to(_target) < 0.01 \
		and _height == 0.0 and _height_velocity == 0.0
	if landed and not _landed_reported:
		_landed_reported = true
		item_settled.emit(_active)

	var settled := not _holding and not _sliding and not _drinking and _flat.distance_to(_target) < 0.001 and _height == 0.0 and _height_velocity == 0.0 \
		and _tilt.length() < 0.001 and _tilt_velocity.length() < 0.01 and absf(_yaw_velocity) < 0.01
	if settled:
		_place(_active, _flat, 0.0, Vector2.ZERO)
		_active = null

## Make an item the one being simulated. Only one moves at a time: returns
## false if another item is still busy (held or settling).
func _activate(item: Node3D) -> bool:
	if item == _active:
		return true
	if _active != null:
		return false
	_active = item
	_flat = Vector3(item.position.x, 0.0, item.position.z)
	_target = _flat
	_height = 0.0
	_height_velocity = 0.0
	_tilt = Vector2.ZERO
	_tilt_velocity = Vector2.ZERO
	_yaw_velocity = 0.0
	_sliding = false
	return true

## Something hit the counter (a customer slamming down): resting props hop,
## more the closer they are to where it hit (3D x).
func jolt(origin_x: float, strength: float) -> void:
	for item: Node3D in _items.get_children():
		if item == _active and (_holding or _drinking):
			continue
		if not _activate(item):
			continue
		var near := clampf(1.0 - absf(item.position.x - origin_x) / 2.0, 0.3, 1.0)
		_pop()
		_tilt_velocity += Vector2(randf_range(-3.0, 3.0), randf_range(-3.0, 3.0)) * strength * near
		_landed_reported = true # a hop in place isn't a new delivery

## Lift a prop and bang it down on the counter (a happy customer). Emits
## slammed_down when it hits. Returns false if the prop is busy (e.g. held).
func slam(item: Node3D) -> bool:
	if (item == _active and (_holding or _drinking)) or not _activate(item):
		return false
	_slam_stage = 1
	_pop()
	_tilt_velocity += Vector2(randf_range(-2.0, 2.0), -3.0)
	_landed_reported = true
	return true

## Pop up exactly like when grabbed, then let it fall.
func _pop() -> void:
	_pop_timer = POP_TIME
	_height_velocity = maxf(_height_velocity, 3.0)

## Shove a prop along the counter (e.g. a customer setting her empty aside).
## It glides velocity / friction units before stopping.
func push(item: Node3D, velocity: Vector3, friction: float = -1.0) -> void:
	if (item == _active and (_holding or _drinking)) or not _activate(item):
		return
	_sliding = true
	_friction = friction if friction > 0.0 else slide_friction
	_slide_velocity = Vector3(velocity.x, 0.0, 0.0)
	_tilt_velocity += Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5))
	_landed_reported = true

## Someone drinks from a prop: it rises so its opening reaches mouth_screen
## (a screen position) and tips toward her. Returns false if it's busy (held).
func raise_to_drink(item: Node3D, mouth_screen: Vector2) -> bool:
	if (item == _active and _holding) or not _activate(item):
		return false
	var liquid := liquid_of(item)
	var rest: Dictionary = _rest[item]
	var mouth := world_point_at_depth(mouth_screen, item.position.z)
	# Where the origin must be for the tipped opening to sit at her mouth.
	var tilt := _drink_tilt()
	var tipped := Basis.from_euler(Vector3(tilt.x, 0.0, tilt.y)) * Basis(Vector3.UP, rest.yaw) \
		* Basis.from_euler(rest.rotation) * Basis.from_scale(rest.scale)
	var origin := mouth - tipped * (liquid.axis_local() as Vector3)
	_drinking = true
	_sliding = false
	_slam_stage = 0
	_drink_height = maxf(origin.y - (rest.lift as float), 0.05)
	_drink_peak = _drink_height
	_target = Vector3(clampf(origin.x, counter_min.x, counter_max.x), 0.0, item.position.z)
	_landed_reported = true
	liquid.drinking = true
	return true

## A gulp: the raised tankard tips a little further and back.
func gulp_nudge() -> void:
	if _drinking:
		_tilt_velocity += _drink_tilt().normalized() * 2.5
		_height_velocity += 0.4

## Done drinking, happy: swing the raised prop out to the side at the same
## height until its body is over counter x body_x, then slam it down there.
## Emits slammed_down when it hits.
func slam_from_drink(item: Node3D, body_x: float) -> void:
	if item != _active or not _drinking:
		return
	_slam_carry = true
	var x := clampf(body_x - _body_offset(item).x, counter_min.x, counter_max.x)
	_target = Vector3(x, 0.0, lane_z)
	liquid_of(item).drinking = false

## Done drinking: set the prop back down on the counter where it is.
func lower_from_drink(item: Node3D) -> void:
	if item != _active or not _drinking:
		return
	_slam_carry = false
	_drink_height = 0.0
	_target = Vector3(_flat.x, 0.0, lane_z)
	liquid_of(item).drinking = false

## Is this prop still up at someone's mouth (or on its way back down)?
func is_drinking(item: Node3D) -> bool:
	return item == _active and _drinking

func _drink_tilt() -> Vector2:
	return Vector2(deg_to_rad(drink_tilt_deg.x), deg_to_rad(drink_tilt_deg.y))

## The ship leans hard enough: a resting prop starts gliding downhill.
func _start_drifting() -> void:
	if _active != null or absf(_drift_pull()) <= static_friction:
		return
	for item: Node3D in _items.get_children():
		if _locked.has(item) or not _activate(item):
			continue
		_sliding = true
		_friction = drift_friction
		_slide_velocity = Vector3.ZERO
		_landed_reported = true
		return

## Sideways pull on the active prop from the ship's lean (none while someone drinks from it).
func _drift_pull() -> float:
	if _active != null and _locked.has(_active):
		return 0.0
	return Sea.counter_pull() * drift_strength

## Flicked, pushed or drifting: glide with friction, bounce off the counter's ends.
func _update_slide(delta: float) -> void:
	var pull := _drift_pull()
	if absf(pull) > static_friction:
		_slide_velocity.x += pull * delta
	_flat += _slide_velocity * delta
	_slide_velocity *= exp(-_friction * delta)
	if _flat.x < counter_min.x or _flat.x > counter_max.x:
		# Off an end: teeter on the edge (or go straight over if it came in fast).
		var side := 1 if _flat.x > counter_max.x else -1
		_flat.x = clampf(_flat.x, counter_min.x, counter_max.x)
		_target = _flat
		_edge_side = side
		var speed := absf(_slide_velocity.x)
		_sliding = false
		_landed_reported = true
		if speed > fall_speed:
			_fall_over(speed)
		else:
			_teeter = teeter_time
		return
	if _flat.z < counter_min.y or _flat.z > counter_max.y:
		_flat.z = clampf(_flat.z, counter_min.y, counter_max.y)
		_slide_velocity.z *= -0.4
	_target = _flat
	if _slide_velocity.length() < 0.05 and absf(pull) <= static_friction:
		_sliding = false

## Over the edge at _edge_side: it tumbles off, out of reach.
func _fall_over(speed: float) -> void:
	_teeter = 0.0
	_falling = true
	_fall_velocity = Vector3(_edge_side * maxf(speed, 0.8), 0.6, 0.0)
	_locked[_active] = true

## Tumbling off the counter: flies out and down, spinning outward, until
## it's past the screen's edge, then smashes there.
func _update_fall(delta: float) -> void:
	_fall_velocity.y -= 9.0 * delta
	_flat += Vector3(_fall_velocity.x, 0.0, 0.0) * delta
	_height += _fall_velocity.y * delta
	_tilt.y -= _edge_side * 9.0 * delta
	_place(_active, _flat, _height, _tilt)
	var screen := _viewport.get_visible_rect().size
	var at := _camera.unproject_position(_active.global_position)
	if at.y > screen.y + 20.0 or at.x < -30.0 or at.x > screen.x + 30.0:
		_smash(Vector2(clampf(at.x, 0.0, screen.x), screen.y))

func _smash(at: Vector2) -> void:
	var item := _active
	_falling = false
	_active = null
	item.visible = false
	var liquid := liquid_of(item)
	if liquid != null:
		liquid.fill = 0.0
		liquid.spilled_total = 0.0
	#_shards.burst(at + Vector2(_edge_side * 12.0, 24.0), 18, -_edge_side)
	_break_sound.stream = BREAK_SOUNDS.pick_random()
	_break_sound.pitch_scale = randf_range(0.92, 1.08)
	_break_sound.play()
	_broken = item
	_respawn_left = respawn_delay
	item_broke.emit(item, at)

## A fresh one drops in from above the screen at the prop's starting spot,
## lands with the usual bounce.
func _respawn() -> void:
	var item := _broken
	if _active != null:
		return # something else is moving: try again next frame
	_broken = null
	_locked.erase(item)
	var rest: Dictionary = _rest[item]
	rest.yaw = randf_range(-0.5, 0.5)
	_activate(item)
	_flat = Vector3(rest.start_x, 0.0, lane_z)
	_target = _flat
	# High enough that the whole prop starts above the top of the screen.
	var above := world_point_at_depth(Vector2(_camera.unproject_position(_flat).x, -10.0), lane_z)
	_height = above.y
	_height_velocity = 0.0
	_tilt_velocity = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	_landed_reported = true
	_place(item, _flat, _height, _tilt)
	item.visible = true

func _place(item: Node3D, flat: Vector3, height: float, tilt: Vector2) -> void:
	var rest: Dictionary = _rest[item]
	item.basis = Basis.from_euler(Vector3(tilt.x, 0.0, tilt.y)) * Basis(Vector3.UP, rest.yaw) \
		* Basis.from_euler(rest.rotation) * Basis.from_scale(rest.scale)
	item.position = Vector3(flat.x, height + (rest.lift as float), flat.z)

## Where the mouse ray meets the counter plane (y = 0).
func _counter_hit(screen: Vector2) -> Vector3:
	var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(
		_camera.project_ray_origin(screen), _camera.project_ray_normal(screen))
	return hit if hit != null else _flat

## The item whose on-screen box contains the point, front-most first.
func _item_under(screen: Vector2) -> Node3D:
	var best: Node3D
	for item: Node3D in _items.get_children():
		if _locked.has(item):
			continue
		if _screen_rect(item).has_point(screen):
			if best == null or item.position.z > best.position.z:
				best = item
	return best

func _screen_rect(item: Node3D) -> Rect2:
	var box := _world_aabb(item)
	var rect := Rect2(_camera.unproject_position(box.position), Vector2.ZERO)
	for i in 8:
		rect = rect.expand(_camera.unproject_position(box.get_endpoint(i)))
	return rect.grow(3.0)

## Lowest actual vertex (world y). Mesh AABBs can't be used: rotating a box inflates it.
func _lowest_y(item: Node3D) -> float:
	var lowest := INF
	for node in item.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if String(mi.name).begins_with("_") or mi.mesh == null:
			continue
		for surface in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				lowest = minf(lowest, (mi.global_transform * v).y)
	return lowest

func _world_aabb(item: Node3D) -> AABB:
	var result := AABB()
	var first := true
	for node in item.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if String(mi.name).begins_with("_"):
			continue # the drink (its foam can pile up over the rim)
		var box := mi.global_transform * mi.get_aabb()
		result = box if first else result.merge(box)
		first = false
	return result

## Offset on the counter from the item's origin to the middle of its body,
## measured upright (the tilt while carrying would skew it).
func _body_offset(item: Node3D) -> Vector3:
	var liquid := liquid_of(item)
	if liquid == null:
		return Vector3.ZERO
	var rest: Dictionary = _rest[item]
	var upright := Basis(Vector3.UP, rest.yaw) * Basis.from_euler(rest.rotation) * Basis.from_scale(rest.scale)
	var axis: Vector3 = upright * (liquid.axis_local() as Vector3)
	return Vector3(axis.x, 0.0, axis.z)

func _on_spilled(world_point: Vector3, amount: float, is_foam: bool, liquid: Node) -> void:
	var color: Color = liquid.foam_color if is_foam else liquid.liquid_color
	var count := clampi(int(amount * 300.0), 1, 12)
	_droplets.burst(_camera.unproject_position(world_point), color, count)

## Fresh start (a new night): every prop back on its spot, upright and empty.
func reset_props() -> void:
	_active = null
	_holding = false
	_sliding = false
	_slam_stage = 0
	_pop_timer = 0.0
	_drinking = false
	_slam_carry = false
	_teeter = 0.0
	_falling = false
	_broken = null
	_locked.clear()
	for item: Node3D in _items.get_children():
		item.visible = true
		var rest: Dictionary = _rest[item]
		rest.yaw = 0.0
		_place(item, Vector3(rest.start_x, 0.0, lane_z), 0.0, Vector2.ZERO)
		var liquid := liquid_of(item)
		if liquid != null:
			liquid.fill = 0.0
			liquid.spilled_total = 0.0
			liquid.drinking = false

func is_sliding(item: Node3D) -> bool:
	return item == _active and _sliding

func is_holding() -> bool:
	return _holding

## The drink inside a prop, if it holds one.
func liquid_of(item: Node3D) -> Node:
	return item.get_node_or_null("Liquid")

## The resting (not held) prop whose body is under this screen x, if any.
func item_under_screen_x(x: float) -> Node3D:
	for item: Node3D in _items.get_children():
		if item == _active and _holding:
			continue
		var rect := _screen_rect(item)
		var margin := rect.size.x * 0.2
		if x > rect.position.x + margin and x < rect.end.x - margin:
			return item
	return null

## Is the container see-through (the stream shows all the way down inside)?
func is_glass(item: Node3D) -> bool:
	return item is ToonProp and (item as ToonProp).glass

## Screen y of the front rim: below it, a stream is inside the container.
func stream_rim_y(item: Node3D) -> float:
	return _camera.unproject_position(liquid_of(item).front_rim_world_point(_camera.global_position)).y

## Screen y where a stream falling into this container disappears: the drink's
## surface, or the front rim if that hides the stream first. In glass it runs
## on down to the top of the head.
func stream_end_y(item: Node3D) -> float:
	var liquid := liquid_of(item)
	if is_glass(item):
		return _camera.unproject_position(liquid.head_world_point()).y
	var surface_y := _camera.unproject_position(liquid.surface_world_point()).y
	var rim_y := stream_rim_y(item)
	return minf(surface_y, rim_y)

## Does a stream at screen x go into this container's opening (not the rim or handle)?
func opening_contains_screen_x(item: Node3D, x: float) -> bool:
	var liquid := liquid_of(item)
	if liquid == null:
		return false
	var top: Vector3 = liquid.opening_world_center()
	var center_x := _camera.unproject_position(top).x
	var edge_x := _camera.unproject_position(top + Vector3(liquid.opening_world_radius(), 0.0, 0.0)).x
	return absf(x - center_x) < absf(edge_x - center_x) * 0.9

## Top of an item on screen (for streams pouring into it).
func screen_top(item: Node3D) -> float:
	return _screen_rect(item).position.y

func screen_point(world: Vector3) -> Vector2:
	return _camera.unproject_position(world)

## Counter point (y = 0) at depth z whose spot height above it shows at screen x.
## Used to line up a container's opening (not its base) under something.
func counter_point_for_screen_x(screen_x: float, height: float, z: float) -> Vector3:
	var x0 := _camera.unproject_position(Vector3(0.0, height, z)).x
	var x1 := _camera.unproject_position(Vector3(1.0, height, z)).x
	return Vector3((screen_x - x0) / (x1 - x0), 0.0, z)

## The 3D point at depth z that shows at a screen position (e.g. something
## in front of the customer, who stands at the back of the counter).
func world_point_at_depth(screen: Vector2, z: float) -> Vector3:
	var origin := _camera.project_ray_origin(screen)
	var dir := _camera.project_ray_normal(screen)
	return origin + dir * ((z - origin.z) / dir.z)

## The point on the counter under a screen position.
func counter_point(screen: Vector2) -> Vector3:
	return _counter_hit(screen)

## Splash droplets at a screen position (e.g. a stream hitting the counter).
func splash(at: Vector2, color: Color, count: int) -> void:
	_droplets.burst(at, color, count, 40.0, 50.0)

## Small splash jumping up out of a drink a stream lands in: the drops
## vanish again when they fall back below the surface.
func splash_in_drink(at: Vector2, color: Color) -> void:
	_droplets.burst(at, color, 1, 22.0, 90.0, at.y + 1.0, 0.7)

## Where a prop's body sits on the counter (3D, y = 0).
func counter_position(item: Node3D) -> Vector3:
	return Vector3(item.position.x, 0.0, item.position.z) + _body_offset(item)

func set_locked(item: Node3D, locked: bool) -> void:
	if locked:
		_locked[item] = true
	else:
		_locked.erase(item)

## All props on the counter.
func items() -> Array[Node]:
	return _items.get_children()

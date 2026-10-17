extends Node2D

## The rum: a bundle of bottles hanging from the ceiling by the porthole (left
## of the customer), each on its own elastic cord tied round its neck, so it
## hangs below it and swings from there. It hides above the top edge and drops
## in when the mouse goes near it (like the tap from the left and the crate
## from the bottom). The bundle swings like a pendulum and leans with the
## ship's roll.
##
## Click a bottle to pull it out: it follows the mouse on its cord (which
## stretches straight, or bends when slack), tugged back a little, and the sea
## sways it. Hold the click to tip it around its neck (to the right, toward
## the counter: tip_side) and drag down to tip it further, like the crate's
## bottles: a little pours a trickle, more a gush;
## moving left/right meanwhile aims it. Right click
## (or click up by the bundle) to let go: it snaps back on its cord and clinks
## into the others. An empty one is thrown off screen instead. Once they're all
## used up it comes back down full; it's also restocked every night (restock()).

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
## Points along each cord (its bend).
const CORD_POINTS := 10
## The rope's look (_make_rope_texture): its colors, how slanted the strands
## are, and how much they bulge at its edges.
const ROPE_LIGHT := Color(0.88, 0.73, 0.5)
const ROPE_DARK := Color(0.45, 0.31, 0.17)
const ROPE_TWIST := 0.35
const ROPE_BUMP := 0.22


static var _rope_texture: ImageTexture
static var _knot_texture: ImageTexture

@export var bar_props_path: NodePath
## The beer tap (tap_tray.gd): out of the way of each other, see _update_reveal.
@export var tap_path: NodePath
@export var bottle_scene: PackedScene = preload("res://props/rum.tscn")
## Where the rope hangs from the ceiling (above the top edge), and the knot at
## its end where the bottles' cords are tied together, in screen space when
## shown. The bundle swings from the ceiling.
@export var ceiling := Vector2(110.0, -160.0)
@export var anchor := Vector2(110.0, 0.0)
## Each bottle's neck (where its cord is tied) hanging at rest, in screen
## space when shown, and its distance from the camera (3D units): alternating
## them layers the bundle. Necks close under the knot = a tight bundle, the
## bottles splaying out below it.
@export var slots: Array[Vector3] = [
	Vector3(97.0, 28.0, 3.75), Vector3(105.0, 24.0, 3.5),
	Vector3(115.0, 24.0, 3.75), Vector3(123.0, 28.0, 3.5),
]
## Height of the neck, where the cord is tied and it pivots (3D units, bottle space).
@export var tie_height: float = 0.52
## Mouse closer than this to the top edge (and within reveal_half_width of
## the anchor) brings it down.
@export var hover_zone_height: float = 30.0
@export var reveal_half_width: float = 70.0
@export var shown_y: float = 0.0
@export var hidden_y: float = -170.0
@export var hide_delay: float = 0.35
## Distance from the camera (3D units) of a bottle pulled out.
@export var depth: float = 3.5
## Clicks this far (px) from a bottle's body grab it.
@export var pick_radius: float = 14.0
## While pulling one out, clicking above this screen y lets go.
@export var let_go_y: float = 60.0
## How far (px) the bottle under the mouse dips, as if tugged.
@export var hover_dip: float = 5.0

@export_group("Swing")
## Bundle pendulum: stiffness (higher = faster swings) and damping.
@export var swing_stiffness: float = 18.0
@export var swing_damping: float = 1.2
## How far it leans with the ship's roll (x the roll angle).
@export var roll_lean: float = 1.5
## Kick to the swing when it drops into view.
@export var drop_kick: float = 0.5
## Swing kick when the tap slides in and knocks the bundle aside, and how
## soon (s) after the bundle goes up out of its way.
@export var tap_knock: float = 1.5
@export var tap_knock_hide: float = 0.25

@export_group("Cord")
## Each bottle's cord (px wide), and the knot round its neck (times its pixel size).
@export var cord_width: float = 7.5
@export var knot_scale: float = 1.5
## Each bottle springs back to its place in the bundle on its cord: stiffness
## and damping (low damping = it overshoots and bounces).
@export var cord_stiffness: float = 220.0
@export var cord_damping: float = 9.0
## How much a stretched cord tugs a pulled-out bottle back (0 = not at all).
@export var cord_pull: float = 0.1
## Sag of a slack cord (px/s²).
@export var cord_gravity: float = 900.0
## Coming back faster than this (px/s), it clinks into the others: how hard
## it knocks them (px/s per px/s) and the clink's pitch.
@export var clink_speed: float = 120.0
@export var clink_knock: float = 0.35
@export var clink_pitch: float = 1.0

@export_group("Pouring")
## How quickly the pulled-out bottle catches up with the mouse.
@export var follow_speed: float = 16.0
## How much the sea sways it while you hold it (px per degree of roll).
@export var sea_sway: float = 8.0
## Holding the click tips it to trickle_deg (drink comes out past the bottle's
## pour_from_deg), dragging down open_drag px tips it all the way to full_deg.
@export var trickle_deg: float = 80.0
@export var full_deg: float = 125.0
## Which way it tips: 1 = its top to the left, -1 = to the right (toward
## the counter, away from the wall it hangs by).
@export var tip_side: float = -1.0
@export var open_drag: float = 40.0
## How open the stream is (0..1, see PourStream) at trickle_deg.
@export_range(0.0, 1.0) var min_open: float = 0.2

@export_group("Throwing")
## An empty bottle let go of is flung off the nearer side of the screen (3D
## units/s sideways, plus a kick up), spinning; it smashes off screen.
@export var throw_speed: float = 3.0
@export var throw_kick: float = 2.5
@export var throw_gravity: float = 9.0
@export var throw_spin: float = 9.0
@export var smash_volume_db: float = -8.0

@onready var _camera: Camera3D = $SubViewport/Camera3D
@onready var _bottles: Node3D = $SubViewport/Bottles
@onready var _display: Sprite2D = $Display
@onready var _stream: PourStream = $PourStream
@onready var _clink: AudioStreamPlayer = $Clink
@onready var _smash: AudioStreamPlayer = $Smash
@onready var _props: Node = get_node(bar_props_path)
@onready var _tap: Node = get_node_or_null(tap_path)

var _shown := false
var _tween: Tween
var _hide_timer := 0.0
var _tap_was_out := false
## Mouse in this node's space.
var _mouse := Vector2(INF, INF)
## The bundle's swing angle (0 = straight down, positive = to the right) and
## its speed.
var _swing := 0.0
var _swing_velocity := 0.0
## Per bottle: its rest spot and distance, its neck (screen) and angle with
## their speeds, its cord (points, previous points, outline + rope lines),
## and whether it's coming back (to clink), thrown (and its flight) or gone.
var _slots: Array[Dictionary] = []
## The slot of the bottle pulled out, or empty; where it's held from (its
## neck relative to the mouse), and whether the click is held (tipping it).
var _carried := {}
## The rope from the ceiling down to the knot.
var _main_rope: Line2D
var _grab_offset := Vector2.ZERO
var _tipping := false
var _press_y := 0.0

func _ready() -> void:
	position.y = hidden_y
	_display.texture = $SubViewport.get_texture()
	_stream.props = _props
	_smash.volume_db = smash_volume_db
	_main_rope = _rope_line(10.0)
	for spot in slots:
		_add_slot(spot)
	restock()

## A rope (textured, see _make_rope_texture). Drawn behind the bottles, so a
## cord's end disappears behind the neck, unless in front (the knot's wraps).
func _rope_line(width: float, in_front := false) -> Line2D:
	if _rope_texture == null:
		_rope_texture = _make_rope_texture()
	var line := Line2D.new()
	line.width = width
	line.texture = _rope_texture
	line.texture_mode = Line2D.LINE_TEXTURE_TILE
	line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	add_child(line)
	if not in_front:
		move_child(line, _display.get_index())
	return line

## Twisted rope, tiled along a line: slanted strands, each shaded round
## (light in the middle, dark at the seams between them), with a black
## outline that bulges where each strand meets the edge.
static func _make_rope_texture() -> ImageTexture:
	var size := Vector2i(7, 8) # one twist along, across
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		var across := (y + 0.5) / size.y * 2.0 - 1.0
		for x in size.x:
			# Where it is in the strand it's in (0 and 1 = the seams).
			var strand := fposmod((x + 0.5) / size.x + across * ROPE_TWIST, 1.0)
			var bulge := sin(PI * strand)
			var edge := 1.0 - ROPE_BUMP * (1.0 - bulge)
			var from_middle := absf(across)
			if from_middle > edge:
				image.set_pixel(x, y, Color.TRANSPARENT)
			elif from_middle > edge - 0.25:
				image.set_pixel(x, y, Color.BLACK)
			else:
				var shade := bulge * (1.0 - from_middle * 0.5)
				image.set_pixel(x, y, ROPE_DARK.lerp(ROPE_LIGHT, shade))
	return ImageTexture.create_from_image(image)

## The knot round a neck: two wraps of the same rope across it, outlined.
static func _make_knot_texture() -> ImageTexture:
	var size := Vector2i(16, 12)
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	for y in size.y:
		for x in size.x:
			var p := Vector2(x + 0.5, y + 0.5)
			var color := Color.TRANSPARENT
			# The wraps (the lower one drawn over the upper).
			for wrap_y: float in [5.0, 8.0]:
				var across := (p.y - wrap_y) / 2.0
				if absf(across) < 1.0 and p.x > 1.0 and p.x < 15.0:
					if absf(across) > 0.5 or p.x < 2.0 or p.x > 14.0:
						color = Color.BLACK
					else:
						var strand := fposmod(p.x / 4.0 + across * ROPE_TWIST, 1.0)
						color = ROPE_DARK.lerp(ROPE_LIGHT, sin(PI * strand))
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _add_slot(spot: Vector3) -> void:
	var bottle: Bottle = bottle_scene.instantiate()
	_bottles.add_child(bottle)
	var lines: Array[Line2D] = [_rope_line(cord_width)]
	# The knot round its neck, over the glass (placed in _update_cords).
	if _knot_texture == null:
		_knot_texture = _make_knot_texture()
	var knot := Sprite2D.new()
	knot.texture = _knot_texture
	add_child(knot)
	var rest := Vector2(spot.x, spot.y)
	_slots.append({
		"bottle": bottle, "rest": rest, "depth": spot.z,
		"cord_length": anchor.distance_to(rest),
		"lines": lines, "knot": knot, "cord": PackedVector2Array(), "cord_previous": PackedVector2Array(),
		"pos": rest, "velocity": Vector2.ZERO, "angle": 0.0, "angle_velocity": 0.0,
		"returning": false, "gone": false, "thrown": false,
		"throw_transform": Transform3D(), "throw_velocity": Vector3.ZERO, "throw_spin": 0.0,
	})

## A full bundle again: every bottle back in its place, full.
func restock() -> void:
	if not _carried.is_empty():
		Bottle.in_hand = null
	_carried = {}
	_tipping = false
	for slot in _slots:
		var bottle: Bottle = slot.bottle
		bottle.get_node("Liquid").fill = 1.0
		bottle.visible = true
		slot.merge({"pos": _rest_of(slot), "velocity": Vector2.ZERO, "angle": _swing,
			"angle_velocity": 0.0, "returning": false, "gone": false, "thrown": false}, true)
		var cord := PackedVector2Array()
		for i in CORD_POINTS:
			cord.append(_knot().lerp(slot.pos, i / float(CORD_POINTS - 1)))
		slot.cord = cord
		slot.cord_previous = cord.duplicate()

func _process(delta: float) -> void:
	_update_reveal(delta)
	_update_swing(delta)
	_update_bottles(delta)
	_update_cords(delta)
	_update_stream(delta)
	_update_thrown(delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		# In the parent's space: the whole view may be swaying (ship_view.gd).
		_mouse = get_parent().to_local(event.position) - position
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
			if _mouse.y + position.y < let_go_y:
				_let_go()
			else:
				_tipping = true
				_press_y = _mouse.y
			get_viewport().set_input_as_handled()
		else:
			var slot := _hovered_slot()
			if not slot.is_empty():
				_carried = slot
				slot.returning = false
				Bottle.in_hand = slot.bottle
				_grab_offset = slot.pos - _mouse
				get_viewport().set_input_as_handled()
	elif _tipping:
		_tipping = false
		get_viewport().set_input_as_handled()

## Done with the pulled-out bottle: it snaps back on its cord, or is thrown
## away if it's empty.
func _let_go() -> void:
	var slot := _carried
	_carried = {}
	_tipping = false
	Bottle.in_hand = null
	if (slot.bottle as Node).get_node("Liquid").fill <= 0.002:
		_throw(slot)
	else:
		slot.returning = true

func _throw(slot: Dictionary) -> void:
	var bottle: Bottle = slot.bottle
	slot.gone = true
	slot.thrown = true
	slot.throw_transform = bottle.global_transform
	# Off the side nearer to where it was held.
	var side := -1.0 if slot.pos.x < $SubViewport.size.x / 2.0 else 1.0
	slot.throw_velocity = Vector3(side * throw_speed, throw_kick, 0.0)
	slot.throw_spin = -side * throw_spin
	for line: Line2D in slot.lines:
		line.visible = false
	(slot.knot as Sprite2D).visible = false

func _update_reveal(delta: float) -> void:
	var screen_mouse := _mouse + position
	var near_anchor := absf(screen_mouse.x - anchor.x) < reveal_half_width
	# One at a time with the tap: it knocks the bundle aside coming in, and
	# the bundle stays up while it's out (unless a bottle is in hand or flying).
	var tap_out: bool = _tap != null and _tap._shown
	if tap_out and not _tap_was_out and _shown:
		_knock_aside()
	_tap_was_out = tap_out
	var busy := not _carried.is_empty() or _slots.any(func(s: Dictionary) -> bool: return s.thrown)
	var wanted := busy or (not tap_out and ((near_anchor and screen_mouse.y < hover_zone_height) \
		or (_shown and _over_any(40.0)) or _slots.any(func(s: Dictionary) -> bool: return s.returning)))
	if wanted:
		_hide_timer = hide_delay
		if not _shown:
			_slide(true)
	elif _shown:
		_hide_timer -= delta
		if _hide_timer <= 0.0:
			_slide(false)

## The tap slid in: the bundle swings away from it with a clink, and goes up
## soon after.
func _knock_aside() -> void:
	_swing_velocity += tap_knock
	for slot in _slots:
		if not slot.gone and slot != _carried:
			slot.velocity.x += tap_knock * 60.0 * randf_range(0.7, 1.0)
			slot.angle_velocity += randf_range(-1.0, 1.0)
	_hide_timer = minf(_hide_timer, tap_knock_hide)
	_clink.stream = CLINKS.pick_random()
	_clink.pitch_scale = clink_pitch * randf_range(0.95, 1.1)
	_clink.volume_db = 0.0
	_clink.play()

func _slide(show: bool) -> void:
	# Every bottle used up: it comes back down full.
	if show and _slots.all(func(s: Dictionary) -> bool: return s.gone and not s.thrown):
		restock()
	# The bottles clink as it sets off down (if there are any left).
	if show and _slots.any(func(s: Dictionary) -> bool: return not s.gone):
		_clink.stream = CLINKS.pick_random()
		_clink.pitch_scale = clink_pitch * randf_range(0.95, 1.1)
		_clink.volume_db = 0.0
		_clink.play()
	_shown = show
	if _tween:
		_tween.kill()
	_tween = create_tween()
	var tweener := _tween.tween_property(self, "position:y", shown_y if show else hidden_y, 0.3 if show else 0.22)
	tweener.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT if show else Tween.EASE_IN)
	if show:
		_tween.tween_callback(func() -> void:
			_swing_velocity += randf_range(-drop_kick, drop_kick))

## The whole bundle is a pendulum leaning with the ship.
func _update_swing(delta: float) -> void:
	var rest := Sea.roll * roll_lean
	_swing_velocity += (-sin(_swing - rest) * swing_stiffness - _swing_velocity * swing_damping) * delta
	_swing += _swing_velocity * delta

## A bottle's place in the bundle, swung with it.
func _rest_of(slot: Dictionary) -> Vector2:
	return ceiling + (slot.rest - ceiling).rotated(-_swing)

## The knot, swung with the bundle.
func _knot() -> Vector2:
	return ceiling + (anchor - ceiling).rotated(-_swing)

func _update_bottles(delta: float) -> void:
	var hovered := _hovered_slot()
	var follow := 1.0 - exp(-follow_speed * delta)
	for slot in _slots:
		if slot.gone:
			continue
		var bottle: Bottle = slot.bottle
		var pos: Vector2 = slot.pos
		var velocity: Vector2 = slot.velocity
		if slot == _carried:
			var target := _mouse + _grab_offset + Vector2(rad_to_deg(Sea.roll) * sea_sway, 0.0)
			if _tipping:
				# Up/down tips it; left/right still moves it, to aim the stream.
				target.y = _press_y + _grab_offset.y
			# The stretched cord tugs it back toward the bundle a little.
			var from_anchor := target - _knot()
			var stretch: float = from_anchor.length() - slot.cord_length
			if stretch > 0.0:
				target -= from_anchor.normalized() * stretch * cord_pull
			var previous := pos
			pos = pos.lerp(target, follow)
			velocity = (pos - previous) / delta
		else:
			# Springs back to its place (bouncing a little past it).
			var rest := _rest_of(slot)
			if slot == hovered:
				rest.y += hover_dip
			# Small steps: a stiff spring blows up over a long (hitching) frame.
			var steps := ceili(delta * 240.0)
			for _step in steps:
				velocity += ((rest - pos) * cord_stiffness - velocity * cord_damping) * delta / steps
				pos += velocity * delta / steps
			if slot.returning and pos.distance_to(rest) < 12.0:
				slot.returning = false
				if velocity.length() > clink_speed:
					_clink_into_others(slot, velocity.length())
		slot.pos = pos
		slot.velocity = velocity
		# Knotted tight at the neck: it carries on in the line from the knot to
		# its neck (fanning out from the knot, turning as it swings). Held, it's
		# upright (tipped to pour), its base trailing behind when it moves.
		var from_knot := pos - _knot()
		var target_angle := atan2(from_knot.x, from_knot.y)
		if slot == _carried:
			var drag := clampf((_mouse.y - _press_y) / open_drag, 0.0, 1.0)
			target_angle = deg_to_rad(lerpf(trickle_deg, full_deg, drag)) * tip_side if _tipping else 0.0
			target_angle += clampf(-velocity.x * 0.0015, -0.5, 0.5)
		var angle_steps := ceili(delta * 240.0)
		for _step in angle_steps:
			slot.angle_velocity += ((target_angle - slot.angle) * 160.0 - slot.angle_velocity * 10.0) * delta / angle_steps
			slot.angle += slot.angle_velocity * delta / angle_steps
		var slot_depth: float = depth if slot == _carried else slot.depth
		# Turns around its neck; positive tips the top to the left.
		var neck := _camera.project_position(pos, slot_depth)
		var basis := Basis(Vector3.BACK, slot.angle)
		bottle.transform = Transform3D(basis, neck - basis * Vector3(0.0, tie_height, 0.0))

## It hit the bundle: the others get knocked aside and swing, with a clink.
func _clink_into_others(slot: Dictionary, speed: float) -> void:
	for other in _slots:
		if other == slot or other.gone or other == _carried:
			continue
		var away := signf(other.pos.x - slot.pos.x)
		var knock := speed * clink_knock * randf_range(0.6, 1.0)
		other.velocity += Vector2(away * knock, randf_range(-0.2, 0.2) * knock)
		other.angle_velocity += -away * knock * 0.02
	_clink.stream = CLINKS.pick_random()
	_clink.pitch_scale = clink_pitch * randf_range(0.9, 1.1)
	_clink.volume_db = linear_to_db(clampf(speed / 600.0, 0.3, 1.0))
	_clink.play()

## Each cord is a chain of points (verlet): pinned at the knot and the
## bottle's base, sagging when slack, straight when stretched.
func _update_cords(delta: float) -> void:
	var knot := _knot()
	_main_rope.points = PackedVector2Array([ceiling, knot])
	for slot in _slots:
		if slot.gone:
			continue
		var cord: PackedVector2Array = slot.cord
		var previous: PackedVector2Array = slot.cord_previous
		var last := CORD_POINTS - 1
		for i in range(1, last):
			var p := cord[i]
			cord[i] = p + (p - previous[i]) * 0.96 + Vector2(0.0, cord_gravity) * delta * delta
			previous[i] = p
		cord[0] = knot
		cord[last] = slot.pos
		var segment: float = slot.cord_length / last
		for _iteration in 12:
			for i in last:
				var a := cord[i]
				var b := cord[i + 1]
				var gap := b - a
				var length := gap.length()
				if length < 0.001:
					continue
				var fix := gap * (1.0 - segment / length) * 0.5
				if i > 0:
					cord[i] = a + fix
				if i + 1 < last:
					cord[i + 1] = b - fix
		slot.cord = cord
		slot.cord_previous = previous
		var lines: Array[Line2D] = slot.lines
		for line in lines:
			line.visible = true
		lines[0].points = cord
		# The knot sits on the neck, turned with the bottle, smaller further back.
		var bottle: Bottle = slot.bottle
		var knot_sprite: Sprite2D = slot.knot
		knot_sprite.visible = true
		knot_sprite.position = _camera.unproject_position(bottle.global_transform * Vector3(0.0, tie_height, 0.0))
		knot_sprite.rotation = -slot.angle
		knot_sprite.scale = Vector2.ONE * knot_scale * depth / (depth if slot == _carried else slot.depth)

## Drink comes out of the pulled-out bottle once it's tipped past its
## pour_from_deg (and until it's empty): the further over, the more open the stream.
func _update_stream(delta: float) -> void:
	if _carried.is_empty():
		_stream.pouring = false
		return
	var bottle: Bottle = _carried.bottle
	var liquid: Node = bottle.get_node("Liquid")
	var tip_deg := rad_to_deg(_carried.angle as float) * tip_side
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

## Thrown bottles fly until they're out of sight, then smash out there.
## They stay hidden until restock().
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
		var middle := _camera.unproject_position(t * Vector3(0.0, bottle.grip_height, 0.0)) + Vector2(0.0, position.y)
		var size := Vector2($SubViewport.size)
		if middle.y > size.y + 120.0 or middle.x < -120.0 or middle.x > size.x + 120.0:
			slot.thrown = false
			bottle.visible = false
			_smash.stream = SMASHES.pick_random()
			_smash.pitch_scale = randf_range(0.9, 1.1)
			_smash.play()

## The hanging bottle the mouse is over (nearest within reach), or an empty dict.
func _hovered_slot() -> Dictionary:
	if not _shown or Bottle.in_hand != null:
		return {}
	var best := {}
	var best_distance := pick_radius
	for slot in _slots:
		if slot.gone:
			continue
		var distance := _distance_to(slot)
		if distance < best_distance:
			best = slot
			best_distance = distance
	return best

func _over_any(reach: float) -> bool:
	return _slots.any(func(s: Dictionary) -> bool: return not s.gone and _distance_to(s) < reach)

## Mouse distance (px) to a bottle's body, from its base to its mouth.
func _distance_to(slot: Dictionary) -> float:
	var bottle: Bottle = slot.bottle
	var base := _camera.unproject_position(bottle.global_transform * Vector3.ZERO)
	var mouth := _camera.unproject_position(bottle.global_transform * bottle.mouth)
	return Geometry2D.get_closest_point_to_segment(_mouse, base, mouth).distance_to(_mouse)

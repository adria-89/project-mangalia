extends Node2D

## Papers Please-style tap: hides off the left edge, slides in when the mouse
## goes near it, and pours while you hold the click on it. A container dropped
## near the spout snaps under it. The stream is drawn here, over the 3D layer,
## and stops at the drink's surface or where the front rim hides it. Glass
## doesn't hide it: below the rim it's tinted, as if seen through the wall.

@export var bar_props_path: NodePath
@export var drink_color: Color = Color(0.9, 0.62, 0.15)
## Fill per second (1.0 = full).
@export var pour_rate: float = 0.22

@export_group("Tray")
## Mouse closer than this to the left edge brings the tap out.
@export var hover_zone_width: float = 50.0
@export var shown_x: float = 0.0
@export var hidden_x: float = -84.0
@export var hide_delay: float = 0.35
## Height of a container's rim above the counter (3D units): the snap lines
## the opening up under the spout, not the base.
@export var rim_height: float = 0.38

@export_group("Stream")
@export var stream_speed: float = 700.0
## Width at the spout; it thins to stream_taper of that as it speeds up.
@export var stream_width: float = 6.0
@export_range(0.1, 1.0) var stream_taper: float = 0.65
## How far the stream falls (px) before it's fully thinned out.
@export var taper_length: float = 120.0
@export var stream_outline: Color = Color(0.16, 0.08, 0.03)
## Bulges that slide down the stream, like glugs from the tap.
@export var glug_size: float = 1.6
@export var glug_speed: float = 260.0
@export var glug_spacing: float = 34.0
## Radius of the blob leading the stream when the tap opens.
@export var head_radius: float = 2.5
## Chance per frame of a drop jumping out where the stream lands in a drink.
@export_range(0.0, 1.0) var splash_chance: float = 0.35
## Color the stream is mixed toward behind a glass wall, and how much.
@export var glass_tint: Color = Color(0.82, 0.95, 1.0)
@export_range(0.0, 1.0) var glass_tint_amount: float = 0.3

## Spout opening in tap.png, relative to the tray's origin.
const SPOUT := Vector2(75, 96)
## Pivot for squash/wobble: where the pipe enters on the left.
const PIVOT := Vector2(0, 60)
const TAP_RECT := Rect2(0, 0, 90, 98)

@onready var _tap: Sprite2D = $Tap
@onready var _props: Node = get_node(bar_props_path)

var _shown := false
var _tween: Tween
var _hide_timer := 0.0
var _pouring := false

var _squash := 0.0
var _squash_velocity := 0.0
var _wobble := 0.0
var _wobble_velocity := 0.0

var _stream_top := 0.0 # screen y of the stream's top / bottom; equal = no stream
var _stream_bottom := 0.0
var _glass_y := INF # screen y below which the stream is behind glass
var _end_y := 0.0 # where the stream currently ends (surface, rim or counter)
var _landing_in_drink := false
var _ripples := false # the landing point is on a visible drink surface
var _ripple_color := Color.WHITE
var _time := 0.0
var _mouse := Vector2(INF, INF)
var _slant := 0.0

func _ready() -> void:
	position.x = hidden_x
	_tap.position = PIVOT
	_tap.offset = -PIVOT
	_stream_top = SPOUT.y + position.y
	_stream_bottom = _stream_top

func _process(delta: float) -> void:
	_time += delta
	_update_tray(delta)
	_update_springs(delta)
	_update_stream(delta)
	queue_redraw()

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
	_tap.rotation = clampf(_wobble, -0.3, 0.3) * 0.25

func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		# In the parent's space: the whole view may be swaying (ship_view.gd).
		_mouse = get_parent().to_local(event.position)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if event.pressed:
		var tap_rect := Rect2(TAP_RECT.position + position, TAP_RECT.size)
		if _shown and tap_rect.has_point(get_parent().to_local(event.position)):
			_pouring = true
			_squash_velocity += 3.0
			_wobble_velocity -= 2.0
			get_viewport().set_input_as_handled()
	elif _pouring:
		_pouring = false
		_squash_velocity -= 2.0
		get_viewport().set_input_as_handled()

func _update_stream(delta: float) -> void:
	var spout := position + SPOUT
	# The ship's lean bends the stream: it falls along the true vertical, so in
	# the ship's frame it drifts sideways the further it drops.
	_slant = tan(Sea.roll)
	var item: Node3D = _props.item_under_screen_x(_stream_x(spout, 250.0))
	var liquid: Node = _props.liquid_of(item) if item != null else null
	# Where the stream ends: the drink's surface, or the counter if it misses.
	var end_y := 286.0
	_glass_y = INF
	if liquid != null:
		end_y = _props.stream_end_y(item)
		# On a big lean it can miss the opening and splash beside the tankard.
		if not _props.opening_contains_screen_x(item, _stream_x(spout, end_y)):
			liquid = null
			end_y = 286.0
		elif _props.is_glass(item):
			_glass_y = _props.stream_rim_y(item)

	if _pouring:
		_stream_top = spout.y
		_stream_bottom = minf(_stream_bottom + stream_speed * delta, end_y)
		_stream_bottom = maxf(_stream_bottom, _stream_top)
	else:
		# The tail falls away after the tap closes.
		_stream_top = minf(_stream_top + stream_speed * delta, _stream_bottom)
		if _stream_bottom < end_y:
			_stream_bottom = minf(_stream_bottom + stream_speed * delta, end_y)
	_stream_bottom = minf(_stream_bottom, end_y)

	var landing := _stream_bottom >= end_y - 0.5 and _stream_bottom > _stream_top + 0.5
	var land_point := Vector2(_stream_x(spout, end_y), end_y)
	_end_y = end_y
	_landing_in_drink = landing and liquid != null
	if landing:
		if liquid != null:
			liquid.add(pour_rate * delta)
			# Ripples a bit darker than the pale top (head or surface), to show on it.
			var top: Color = liquid.foam_color if liquid.foam > 0.01 else liquid.surface_color
			_ripple_color = drink_color.lerp(top, 0.35)
			# Behind a wooden rim the stream ends at the rim, the surface is hidden.
			_ripples = _props.is_glass(item) or end_y < _props.stream_rim_y(item) - 1.0
			if randf() < splash_chance:
				_props.splash_in_drink(land_point, drink_color)
		elif randf() < 0.5:
			_props.splash(land_point, drink_color, 1)

## Where the stream is horizontally at height y (parent space).
func _stream_x(spout: Vector2, y: float) -> float:
	return spout.x + (y - spout.y) * _slant

func _draw() -> void:
	if _stream_bottom <= _stream_top + 0.5:
		return
	# Drawn in the parent's space, so the stream hangs from the spout wherever
	# the tray currently is.
	draw_set_transform(-position)
	var spout := position + SPOUT
	if _landing_in_drink and _ripples:
		_draw_ripples(Vector2(_stream_x(spout, _end_y), _end_y))
	var segments := _stream_segments(spout)
	# Separate passes, so no segment's outline covers its neighbour's fill.
	var falling := _stream_bottom < _end_y - 0.5
	for i in segments.size():
		var rect: Rect2 = segments[i].rect
		var bottom := 1.0 if falling and i == segments.size() - 1 else 0.0
		draw_rect(rect.grow_individual(1.0, 0.0, 1.0, bottom), _behind(stream_outline, segments[i].glass))
	for s in segments:
		draw_rect(s.rect, _behind(drink_color, s.glass))
	var shine := drink_color.lightened(0.45)
	for s in segments:
		var rect: Rect2 = s.rect
		if rect.size.x >= 3.0:
			draw_rect(Rect2(rect.position + Vector2(1.0, 0.0), Vector2(1.0, rect.size.y)), _behind(shine, s.glass))
	if not _pouring:
		_draw_tail_drops(spout)
	draw_set_transform(Vector2.ZERO)

## The stream cut into short pixel-snapped strips, top to bottom: each has its
## rect (parent space) and whether it's behind glass.
func _stream_segments(spout: Vector2) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var falling := _stream_bottom < _end_y - 0.5
	var y := _stream_top
	while y < _stream_bottom:
		var step := minf(2.0, _stream_bottom - y)
		if y < _glass_y:
			step = minf(step, maxf(_glass_y - y, 0.5)) # switch color right at the rim
		var mid := y + step / 2.0
		var fall := mid - spout.y
		var width := lerpf(stream_width, stream_width * stream_taper, clampf(fall / taper_length, 0.0, 1.0))
		width += sin(mid * 0.2 + _time * 9.0) * 0.4
		width += pow(maxf(sin((fall - _time * glug_speed) * TAU / glug_spacing), 0.0), 6.0) * glug_size
		if falling:
			# Round blob leading the stream down.
			var d := _stream_bottom - head_radius - mid
			if absf(d) < head_radius:
				width = maxf(width, 2.0 * sqrt(head_radius * head_radius - d * d))
		if not _pouring:
			# The tail end thins to a point as it lets go.
			width *= clampf((mid - _stream_top) / 5.0 + 0.3, 0.0, 1.0)
		width = maxf(roundf(width), 1.0)
		var wobble := sin(mid * 0.35 - _time * 18.0) * 0.6
		var x := roundf(_stream_x(spout, mid) + wobble - width / 2.0)
		segments.append({"rect": Rect2(x, y, width, step), "glass": y >= _glass_y})
		y += step
	return segments

## A few drops trailing the tail once the tap closes, as it breaks off.
func _draw_tail_drops(spout: Vector2) -> void:
	var radius := 1.5
	for k in 3:
		var y := _stream_top - 5.0 - 6.0 * k
		radius -= 0.25
		if y <= spout.y + 1.0 or y >= _stream_bottom:
			continue
		var center := Vector2(roundf(_stream_x(spout, y)), y)
		draw_circle(center, radius + 1.0, _behind(stream_outline, y >= _glass_y))
		draw_circle(center, radius, _behind(drink_color, y >= _glass_y))

## Rings spreading out over the surface where the stream goes in.
func _draw_ripples(center: Vector2) -> void:
	for k in 2:
		var t := fposmod(_time * 2.5 + k * 0.5, 1.0)
		var radius := lerpf(2.0, 8.0, t)
		var points := PackedVector2Array()
		for i in 17:
			var a := TAU * i / 16.0
			points.append(center + Vector2(cos(a) * radius, sin(a) * radius * 0.35))
		var color := _ripple_color
		color.a = 1.0 - t
		draw_polyline(points, color, 1.0)

## A stream color as seen through the glass wall (or not).
func _behind(color: Color, glass: bool) -> Color:
	return color.lerp(glass_tint, glass_tint_amount) if glass else color

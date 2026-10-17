class_name PourStream
extends Node2D

## A stream of drink falling from a spout (the tap, a tipped bottle) into
## whatever container is under it. Put it as a child of the tool; the tool
## sets spout, drink, open and pouring every frame. Points are in the tool's
## parent's space (the bar), so it hangs from the spout wherever the tool is.
##
## It is drawn over the 3D layer and stops at the drink's surface or where the
## front rim hides it. Glass doesn't hide it: below the rim it's tinted, as if
## seen through the wall. It fills the container: a trickle (barely open) lets
## a lighter drink float on top as its own layer, a gush mixes it in, and
## puffs of it swirl down into the glass to show that.

const POUR_SOUND: AudioStream = preload("res://audio/beer_pour.wav")

## Set by the tool every frame.
var pouring := false
## How far open (0..1): sets how much flows, how thick and how rough it is.
var open := 0.0
var drink: Drink = preload("res://props/drinks/beer.tres")
## Where it comes out, in the tool's parent's space.
var spout := Vector2.ZERO
## BarProps: the containers it can land in.
var props: Node

## Fill per second (1.0 = full) when all the way open.
@export var pour_rate: float = 0.22

@export_group("Gentleness")
## Up to this much open the drink lands gently enough to float on a heavier
## one as its own layer; past it, more and more mixes in (container_liquid.gd),
## down to full_gentleness all the way open.
@export_range(0.0, 1.0) var layer_up_to: float = 0.4
@export_range(0.0, 1.0) var full_gentleness: float = 0.3

@export_group("Look")
@export var stream_speed: float = 700.0
## Width at the spout; it thins to stream_taper of that as it speeds up.
@export var stream_width: float = 6.0
## Width of a trickle (barely open) as a fraction of the full stream's.
@export_range(0.1, 1.0) var trickle_width: float = 0.45
@export_range(0.1, 1.0) var stream_taper: float = 0.65
## How far the stream falls (px) before it's fully thinned out.
@export var taper_length: float = 120.0
@export var stream_outline: Color = Color(0.16, 0.08, 0.03)
## Bulges that slide down the stream, like glugs.
@export var glug_size: float = 1.6
@export var glug_speed: float = 260.0
@export var glug_spacing: float = 34.0
## Radius of the blob leading the stream when it starts.
@export var head_radius: float = 2.5
## Chance per frame of a drop jumping out where the stream lands in a drink.
@export_range(0.0, 1.0) var splash_chance: float = 0.35
## Color the stream is mixed toward behind a glass wall, and how much.
@export var glass_tint: Color = Color(0.82, 0.95, 1.0)
@export_range(0.0, 1.0) var glass_tint_amount: float = 0.3
## Pouring too hard onto a different drink: puffs of it swirl down into the
## glass from where the stream lands. Puffs per second when it all mixes.
@export var swirl_rate: float = 40.0
@export var swirl_life: float = 0.6

@export_group("Sound")
## The pour clip's glugging part (s): an empty glass starts at 0, a full one
## at the end, so picking a pour back up continues where the glass is.
@export var pour_sound_end: float = 2.6
## Past pour_sound_end it loops back here while you keep pouring (overflow).
@export var pour_loop_start: float = 1.2
## Stream missing the drink and hitting the counter: quieter and duller.
@export var miss_volume_db: float = -9.0
@export var miss_pitch: float = 0.85
## Pitch of the whole pour (a bottle can sound different from the tap).
@export var pitch: float = 1.0

## Screen y of the counter top where a stream that misses lands.
const COUNTER_Y := 286.0

var _stream_top := 0.0 # y of the stream's top / bottom; equal = no stream
var _stream_bottom := 0.0
var _glass_y := INF # y below which the stream is behind glass
var _end_y := 0.0 # where the stream currently ends (surface, rim or counter)
var _landing_in_drink := false
var _ripples := false # the landing point is on a visible drink surface
var _ripple_color := Color.WHITE
var _time := 0.0
var _slant := 0.0
## Mixing puffs (see swirl_rate): position, velocity, age and color each.
var _swirls: Array[Dictionary] = []
var _pour_sound: AudioStreamPlayer
var _was_pouring := false

func _ready() -> void:
	_pour_sound = AudioStreamPlayer.new()
	_pour_sound.stream = POUR_SOUND
	add_child(_pour_sound)

func _process(delta: float) -> void:
	_time += delta
	if pouring and not _was_pouring and _stream_bottom <= _stream_top + 0.5:
		_stream_top = spout.y
		_stream_bottom = spout.y
	if _was_pouring and not pouring:
		_pour_sound.stop()
	_was_pouring = pouring
	_update_swirls(delta)
	_update_stream(delta)
	queue_redraw()

## How softly the stream lands at the current opening (see layer_up_to).
func gentleness() -> float:
	var rough := smoothstep(layer_up_to, 1.0, open)
	return lerpf(1.0, full_gentleness, rough)

## The pour clip follows the glass: it starts at the spot matching how full
## the drink is, glugs on while it pours and loops its end on overflow.
func _update_pour_sound(liquid: Node) -> void:
	if not pouring:
		return
	if not _pour_sound.playing:
		var at := 0.0
		if liquid != null:
			at = clampf(liquid.fill, 0.0, 1.0) * pour_sound_end
		_pour_sound.play(minf(at, pour_sound_end - 0.05))
	elif _pour_sound.get_playback_position() >= pour_sound_end:
		_pour_sound.seek(pour_loop_start)
	var missing := liquid == null
	# A trickle is quieter than the full glug.
	var open_db := linear_to_db(lerpf(0.4, 1.0, open))
	_pour_sound.volume_db = (miss_volume_db if missing else 0.0) + open_db
	_pour_sound.pitch_scale = (miss_pitch if missing else 1.0) * pitch

func _update_stream(delta: float) -> void:
	# The ship's lean bends the stream: it falls along the true vertical, so in
	# the ship's frame it drifts sideways the further it drops.
	_slant = tan(Sea.roll)
	var item: Node3D = props.item_under_screen_x(_stream_x(spout, 250.0))
	var liquid: Node = props.liquid_of(item) if item != null else null
	# Where the stream ends: the drink's surface, or the counter if it misses.
	var end_y := COUNTER_Y
	_glass_y = INF
	if liquid != null:
		end_y = props.stream_end_y(item)
		# On a big lean it can miss the opening and splash beside the container.
		if not props.opening_contains_screen_x(item, _stream_x(spout, end_y)):
			liquid = null
			end_y = COUNTER_Y
		elif props.is_glass(item):
			_glass_y = props.stream_rim_y(item)
	# A bottle dipped in below the surface (or the counter) pours straight there.
	end_y = maxf(end_y, spout.y + 1.0)

	if pouring:
		_stream_top = spout.y
		_stream_bottom = minf(_stream_bottom + stream_speed * delta, end_y)
		_stream_bottom = maxf(_stream_bottom, _stream_top)
	elif _stream_bottom <= _stream_top + 0.5:
		_stream_top = end_y # nothing falling
		_stream_bottom = end_y
	else:
		# The tail falls away after it stops.
		_stream_top = minf(_stream_top + stream_speed * delta, _stream_bottom)
		if _stream_bottom < end_y:
			_stream_bottom = minf(_stream_bottom + stream_speed * delta, end_y)
	_stream_bottom = minf(_stream_bottom, end_y)

	var landing := _stream_bottom >= end_y - 0.5 and _stream_bottom > _stream_top + 0.5
	var land_point := Vector2(_stream_x(spout, end_y), end_y)
	_end_y = end_y
	_landing_in_drink = landing and liquid != null
	_update_pour_sound(liquid)
	if landing:
		if liquid != null:
			var mixing: float = liquid.add(pour_rate * open * delta, drink, gentleness())
			if props.is_glass(item) and randf() < mixing * swirl_rate * delta:
				_swirls.append({
					"position": land_point,
					"velocity": Vector2(randf_range(-14.0, 14.0), randf_range(12.0, 30.0)),
					"age": 0.0,
					"color": drink.color,
				})
			# Ripples a bit darker than the pale top (head or surface), to show on it.
			var top: Color = liquid.foam_color if liquid.foam > 0.01 else liquid.surface_color
			_ripple_color = drink.stream_color.lerp(top, 0.35)
			# Behind a wooden rim the stream ends at the rim, the surface is hidden.
			_ripples = props.is_glass(item) or end_y < props.stream_rim_y(item) - 1.0
			if randf() < splash_chance:
				props.splash_in_drink(land_point, drink.stream_color)
		elif randf() < 0.5:
			props.splash(land_point, drink.stream_color, 1)

## Where the stream is horizontally at height y.
func _stream_x(from: Vector2, y: float) -> float:
	return from.x + (y - from.y) * _slant

func _draw() -> void:
	# In the tool's parent's space (see spout).
	draw_set_transform_matrix(get_parent().transform.affine_inverse())
	_draw_swirls() # they keep sinking for a moment after it stops
	if _stream_bottom <= _stream_top + 0.5:
		return
	var color := drink.stream_color
	if _landing_in_drink and _ripples:
		_draw_ripples(Vector2(_stream_x(spout, _end_y), _end_y))
	var segments := _stream_segments()
	# Separate passes, so no segment's outline covers its neighbour's fill.
	var falling := _stream_bottom < _end_y - 0.5
	for i in segments.size():
		var rect: Rect2 = segments[i].rect
		var bottom := 1.0 if falling and i == segments.size() - 1 else 0.0
		draw_rect(rect.grow_individual(1.0, 0.0, 1.0, bottom), _behind(stream_outline, segments[i].glass))
	for s in segments:
		draw_rect(s.rect, _behind(color, s.glass))
	var shine := color.lightened(0.45)
	for s in segments:
		var rect: Rect2 = s.rect
		if rect.size.x >= 3.0:
			draw_rect(Rect2(rect.position + Vector2(1.0, 0.0), Vector2(1.0, rect.size.y)), _behind(shine, s.glass))
	if not pouring:
		_draw_tail_drops()

## The stream cut into short pixel-snapped strips, top to bottom: each has its
## rect and whether it's behind glass.
func _stream_segments() -> Array[Dictionary]:
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
		width *= lerpf(trickle_width, 1.0, open)
		width += sin(mid * 0.2 + _time * 9.0) * 0.4
		width += pow(maxf(sin((fall - _time * glug_speed) * TAU / glug_spacing), 0.0), 6.0) * glug_size
		if falling:
			# Round blob leading the stream down.
			var d := _stream_bottom - head_radius - mid
			if absf(d) < head_radius:
				width = maxf(width, 2.0 * sqrt(head_radius * head_radius - d * d))
		if not pouring:
			# The tail end thins to a point as it lets go.
			width *= clampf((mid - _stream_top) / 5.0 + 0.3, 0.0, 1.0)
		width = maxf(roundf(width), 1.0)
		var wobble := sin(mid * 0.35 - _time * 18.0) * 0.6
		var x := roundf(_stream_x(spout, mid) + wobble - width / 2.0)
		segments.append({"rect": Rect2(x, y, width, step), "glass": y >= _glass_y})
		y += step
	return segments

## A few drops trailing the tail once it stops, as it breaks off.
func _draw_tail_drops() -> void:
	var radius := 1.5
	for k in 3:
		var y := _stream_top - 5.0 - 6.0 * k
		radius -= 0.25
		if y <= spout.y + 1.0 or y >= _stream_bottom:
			continue
		var center := Vector2(roundf(_stream_x(spout, y)), y)
		draw_circle(center, radius + 1.0, _behind(stream_outline, y >= _glass_y))
		draw_circle(center, radius, _behind(drink.stream_color, y >= _glass_y))

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

## The puffs drift down and spread out, slowing as they go.
func _update_swirls(delta: float) -> void:
	for swirl in _swirls:
		swirl.position += swirl.velocity * delta
		swirl.velocity *= 1.0 - 3.0 * delta
		swirl.age += delta
	for i in range(_swirls.size() - 1, -1, -1):
		if _swirls[i].age >= swirl_life:
			_swirls.remove_at(i)

## Behind the glass wall, so tinted like the stream below the rim. They grow
## and fade as they go.
func _draw_swirls() -> void:
	for swirl in _swirls:
		var t: float = swirl.age / swirl_life
		var color: Color = _behind(swirl.color, true)
		color.a = 0.85 * (1.0 - t)
		var center: Vector2 = swirl.position
		draw_circle(center.round(), lerpf(1.0, 3.5, t), color)

## A stream color as seen through the glass wall (or not).
func _behind(color: Color, glass: bool) -> Color:
	return color.lerp(glass_tint, glass_tint_amount) if glass else color

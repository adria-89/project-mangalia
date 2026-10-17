extends Node2D

## Test customer: walks in standing, sits down so the chest lands on the
## counter, hops when talking or clicked, then stands up and walks out.
## The body uses volume-preserving squash and stretch; the chest is a damped
## spring that lags behind the body. While seated, the counter acts as a
## floor: downward jiggle turns into squish instead of sinking through.
##
## The sprite is drawn twice: Body behind the counter, Front (masked chest
## only) in front of it.

signal seated
## Her chest hit the counter hard (1.0 = sitting down): things on it should jump.
signal slammed(strength: float)
signal left
## Her kiss just hit the screen (see blow_kiss()).
signal kiss_landed

const TICK_SOUND: AudioStream = preload("res://audio/dialogue_tick.wav")
## Per CustomerData.Bust (small, medium, large): the sound her chest makes,
## and its pitch.
const BOING_SOUNDS: Array[AudioStream] = [
	preload("res://audio/boing_small.wav"),
	preload("res://audio/boing.wav"),
	preload("res://audio/boing_large.wav"),
]
const BOING_PITCHES: Array[float] = [1.0, 1.0, 1.0]
const KISS_SOUND: AudioStream = preload("res://audio/kiss_love.wav")
## The eyes shutting and opening again in the dark (see blink()).
const BLINK_SOUNDS: Array[AudioStream] = [
	preload("res://audio/blink1.wav"),
	preload("res://audio/blink2.wav"),
]
const HICCUP_SOUNDS: Array[AudioStream] = [
	preload("res://audio/hiccup1.wav"),
	preload("res://audio/hiccup2.wav"),
	preload("res://audio/hiccup3.wav"),
]
const HiccupBubble := preload("res://customer/hiccup_bubble.gd")

@export var data: CustomerData

@export var display_scale: float = 1.1
## Screen Y of the counter surface the chest rests on.
@export var rest_line: float = 292.0
@export var sit_drop: float = 24.0
@export var stop_x: float = 270.0
@export var exit_x: float = 680.0
@export var walk_duration: float = 1.6
@export var step_frequency: float = 4.0
@export var step_height: float = 6.0

## How much she leans against the ship's roll while seated (1 = stays upright).
@export var sea_lean: float = 0.6

@export_group("Nervous")
## How long the blue gloom stays before it fades (seconds).
@export var nervous_hold: float = 1.8
## When she gets nervous a ripple runs through her like through water:
## how far the rows shift (sprite pixels) and how long it takes to calm down.
@export var nervous_ripple: float = 3.0
@export var nervous_ripple_time: float = 0.7
@export_group("")

@export_group("Squash & stretch")
@export var squash_stiffness: float = 260.0
@export var squash_damping: float = 11.0

@export_group("Counter")
## Squish while just resting on the counter.
@export var resting_squish: float = 0.05
## Extra squish per pixel the chest is pushed into the counter.
@export var squish_per_pixel: float = 0.035
@export var max_squish: float = 0.35

@export_group("Drunk")
## Beers she's had tonight (set by main). From hiccup_from on she hiccups,
## more often the more she's had.
@export var drunk: float = 0.0
@export var hiccup_from: float = 1.0
## Seconds between hiccups right at hiccup_from; divided by how drunk she is.
@export var hiccup_interval: Vector2 = Vector2(3.0, 7.0)
@export var min_hiccup_interval: float = 1.5
@export var bubbles_per_hiccup: Vector2i = Vector2i(2, 4)
## Slow wobble while drunk (sprite pixels): this much at hiccup_from, more per
## extra beer, up to max_drunk_sway. Eases in and out.
@export var drunk_sway: float = 1.5
@export var drunk_sway_per_beer: float = 0.75
@export var max_drunk_sway: float = 3.0
@export_group("")

@onready var _body: Sprite2D = $Body
@onready var _front: Sprite2D = $Body/Front
@onready var _voice: AudioStreamPlayer = $Voice
var _boing: AudioStreamPlayer
var _kiss: AudioStreamPlayer
var _blink_sound: AudioStreamPlayer
var _hiccup_sound: AudioStreamPlayer
var _hiccup_timer := 0.0
var _drinking := false
var _bubbles: Array[Node2D] = []
var _lights_out := 0.0
var _sway := 0.0
var _sway_time := 0.0

enum State { WALK_IN, SIT, SEATED, STAND, WALK_OUT }
## Which sprite variant is shown (see CustomerData > Faces). The blush is
## separate and stacks on top of any of them (see set_blush()).
enum Face { DEFAULT, HAPPY, KISS, WINK }

var _state := State.WALK_IN
var _time := 0.0
var _from := Vector2.ZERO
var _seated_y := 0.0
var _standing_y := 0.0
var _hop := 0.0 # vertical offset from talk/poke hops (negative = up)
var _hop_velocity := 0.0
var _step_hop := 0.0
var _prev_step_phase := 0.0

var _squash := 0.0 # >0 stretch, <0 squash
var _squash_velocity := 0.0

var _jiggle := Vector2.ZERO
var _jiggle_velocity := Vector2.ZERO
var _prev_anchor := Vector2.ZERO
var _prev_anchor_velocity := Vector2.ZERO
var _chest_anchor := Vector2.ZERO # local, relative to the bottom-center pivot

var _face_flash := 0 # bumped on every face change, so stale timers don't reset it
var _blush := 0.0 # 0 = none, 1 = full blush overlay
var _blush_tween: Tween
var _nervous_tween: Tween
var _ripple_left := 0.0 # seconds of nervous ripple left

func _ready() -> void:
	_body.texture = data.texture
	_front.texture = data.texture
	var height := float(data.texture.get_height())
	_body.offset = Vector2(0, -height / 2.0)
	_front.offset = _body.offset
	var chest := _measure_chest(data.mask.get_image())
	for sprite: Sprite2D in [_body, _front]:
		var mat := sprite.material as ShaderMaterial
		mat.set_shader_parameter("jiggle_mask", data.mask)
		mat.set_shader_parameter("eyes_mask", data.eyes_mask)
		mat.set_shader_parameter("has_eyes_mask", data.eyes_mask != null)
		mat.set_shader_parameter("blush_tex", data.blush)
		if data.nervous != null:
			mat.set_shader_parameter("nervous_tex", data.nervous)
		mat.set_shader_parameter("chest_bottom", chest.y / height)
		mat.set_shader_parameter("chest_center_x", chest.x / data.texture.get_width())
	_front.visible = false
	_voice.stream = TICK_SOUND
	_boing = AudioStreamPlayer.new()
	_boing.stream = BOING_SOUNDS[data.bust]
	add_child(_boing)
	_blink_sound = AudioStreamPlayer.new()
	_blink_sound.process_mode = Node.PROCESS_MODE_ALWAYS # she blinks while the game is paused
	_blink_sound.max_polyphony = 2
	add_child(_blink_sound)
	_kiss = AudioStreamPlayer.new()
	_kiss.stream = KISS_SOUND
	add_child(_kiss)
	_hiccup_sound = AudioStreamPlayer.new()
	add_child(_hiccup_sound)
	_reset_hiccup_timer()
	_chest_anchor = Vector2(chest.x - data.texture.get_width() / 2.0, chest.y - height)
	# Pivot is the sprite's bottom edge; place it so the chest bottom sits on the counter.
	_seated_y = rest_line - _chest_anchor.y * display_scale
	_standing_y = _seated_y - sit_drop
	position.y = _standing_y
	_from = position
	_prev_anchor = _anchor_position()

## Lowest row of the chest (weight > 0.5) and its horizontal center, in sprite pixels.
func _measure_chest(mask: Image) -> Vector2:
	var bottom := 0
	var min_x := mask.get_width()
	var max_x := 0
	for y in mask.get_height():
		for x in mask.get_width():
			var c := mask.get_pixel(x, y)
			if c.r * c.a > 0.5:
				bottom = maxi(bottom, y)
				min_x = mini(min_x, x)
				max_x = maxi(max_x, x)
	return Vector2((min_x + max_x) / 2.0, bottom)

func _physics_process(delta: float) -> void:
	_time += delta
	match _state:
		State.WALK_IN:
			_update_walk(stop_x, State.SIT)
		State.SIT:
			_update_sit()
		State.SEATED:
			_squash += sin(_time * 2.2) * 0.0006 # breathing
			_body.rotation = -Sea.roll * sea_lean # keeps upright as the ship rolls under her
			_update_hiccups(delta)
		State.STAND:
			_update_stand()
		State.WALK_OUT:
			_update_walk(exit_x, State.WALK_OUT)
	_update_hop(delta)
	_update_squash(delta)
	_update_ripple(delta)
	_update_drunk_sway(delta)
	_apply_body_transform()
	_update_jiggle(delta)

func _update_walk(target_x: float, next: State) -> void:
	var t := clampf(_time / walk_duration, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 2.0) if next == State.SIT else t * t
	position.x = lerpf(_from.x, target_x, eased)
	var lean := 1.0 - t if next == State.SIT else t
	_body.rotation = deg_to_rad(4.0) * signf(target_x - _from.x) * lean
	var phase := fmod(_time * step_frequency, 1.0)
	_step_hop = -absf(sin(phase * PI)) * step_height * (1.0 - t * 0.6) if t < 1.0 else 0.0
	if t < 1.0 and phase < _prev_step_phase:
		_squash_velocity -= 2.2
	_prev_step_phase = phase
	if t >= 1.0:
		if next == State.SIT:
			_enter(State.SIT)
		else:
			left.emit()
			queue_free()

func _update_sit() -> void:
	const DURATION := 0.22
	var t := clampf(_time / DURATION, 0.0, 1.0)
	_body.rotation = 0.0
	position.y = lerpf(_standing_y, _seated_y, t * t) # falls into the chair
	if t >= 1.0:
		_front.visible = true
		_squash_velocity -= 5.0
		_jiggle_velocity.y += 120.0 # plop onto the counter
		# Boing, a bit deeper for lower-voiced characters.
		_boing.pitch_scale = BOING_PITCHES[data.bust] * lerpf(1.0, data.voice_pitch, 0.5) * randf_range(0.95, 1.05)
		_boing.play()
		slammed.emit(1.0)
		_enter(State.SEATED)
		seated.emit()

func _update_stand() -> void:
	const DURATION := 0.3
	var t := clampf(_time / DURATION, 0.0, 1.0)
	position.y = lerpf(_seated_y, _standing_y, 1.0 - pow(1.0 - t, 2.0))
	if t >= 1.0:
		_from = position
		_enter(State.WALK_OUT)

func _enter(state: State) -> void:
	_state = state
	_time = 0.0
	_step_hop = 0.0

func _update_hop(delta: float) -> void:
	if _hop < 0.0 or _hop_velocity < 0.0:
		_hop_velocity += 900.0 * delta
		_hop += _hop_velocity * delta
		if _hop >= 0.0:
			_hop = 0.0
			_hop_velocity = 0.0
			_squash_velocity -= 2.5

func _update_squash(delta: float) -> void:
	_squash_velocity += (-_squash * squash_stiffness - _squash_velocity * squash_damping) * delta
	_squash += _squash_velocity * delta
	_squash = clampf(_squash, -0.25, 0.25)

func _apply_body_transform() -> void:
	var stretch := 1.0 + _squash
	_body.scale = Vector2(display_scale / stretch, display_scale * stretch)
	_body.position = Vector2(0, _hop + _step_hop)

## Drunk: a slow, gentle wave keeps running through her (see jiggle.gdshader).
func _update_drunk_sway(delta: float) -> void:
	var target := 0.0
	if drunk >= hiccup_from:
		target = minf(drunk_sway + (drunk - hiccup_from) * drunk_sway_per_beer, max_drunk_sway)
	if _sway <= 0.0 and target <= 0.0:
		return
	_sway = move_toward(_sway, target, delta * 0.5)
	_sway_time += delta
	_set_shader("drunk_sway", _sway)
	_set_shader("drunk_time", _sway_time)

## The nervous ripple calms down: strong at first, then quickly still.
func _update_ripple(delta: float) -> void:
	if _ripple_left <= 0.0:
		return
	_ripple_left = maxf(_ripple_left - delta, 0.0)
	var k := _ripple_left / nervous_ripple_time
	_set_shader("ripple_amount", nervous_ripple * k * k)
	_set_shader("ripple_time", nervous_ripple_time - _ripple_left)

func _anchor_position() -> Vector2:
	return _body.global_transform * _chest_anchor

func _update_jiggle(delta: float) -> void:
	var anchor := _anchor_position()
	var anchor_velocity := (anchor - _prev_anchor) / delta
	var anchor_accel := (anchor_velocity - _prev_anchor_velocity) / delta
	_prev_anchor = anchor
	_prev_anchor_velocity = anchor_velocity
	# The chest wants to stay where it was: body acceleration pushes it the other way.
	var force := -_jiggle * data.jiggle_stiffness - _jiggle_velocity * data.jiggle_damping \
		- anchor_accel * data.jiggle_inertia * 0.01
	_jiggle_velocity += force * delta
	_jiggle += _jiggle_velocity * delta
	_jiggle = _jiggle.limit_length(data.jiggle_max)

	var offset := _jiggle / display_scale * Settings.physics_scale()
	var squish := 0.0
	if _state == State.SEATED and _hop > -1.0:
		# Resting on the counter: anything pushing down becomes squish.
		squish = resting_squish + maxf(offset.y, 0.0) * squish_per_pixel
		offset.y = minf(offset.y, 0.0)
	squish = minf(squish, max_squish)
	for sprite: Sprite2D in [_body, _front]:
		var mat := sprite.material as ShaderMaterial
		mat.set_shader_parameter("spring_offset", offset)
		mat.set_shader_parameter("squish", squish)

## Small hop. Used when she starts a new line of dialogue.
func bounce() -> void:
	if _state != State.SEATED:
		return
	_hop_velocity = -140.0
	_hop = -0.01
	_squash_velocity += 3.0

## Clicked: a hop plus a little "hm!" made of quick voice ticks.
func poke() -> void:
	bounce()
	_jiggle_velocity += Vector2(randf_range(-60.0, 60.0), -40.0)
	_voice_burst([1.0, 1.1, 1.2])

## Reaction to a served drink: 2 = happy, 1 = meh, 0 = angry.
func react(mood: int) -> void:
	match mood:
		2:
			set_face(Face.HAPPY, 0.8)
			bounce()
			_voice_burst([1.1, 1.25, 1.4, 1.55])
			await get_tree().create_timer(0.3).timeout
			if is_inside_tree():
				bounce()
		1:
			_squash_velocity -= 2.0
			_voice_burst([1.0, 0.9])
		_:
			# Stomp: squash down hard and shake side to side.
			_squash_velocity -= 6.0
			_jiggle_velocity += Vector2(randf_range(-90.0, 90.0), 60.0)
			slammed.emit(0.6)
			_voice_burst([0.8, 0.7, 0.6])

## Point on the counter in front of her chest, in screen space (for coin tosses).
func chest_screen_position() -> Vector2:
	return _body.global_transform * _chest_anchor

## Where the coins come out when she tips (between her breasts), in screen space.
func cleavage_screen_position() -> Vector2:
	# The anchor is the bottom of the chest; the cleavage sits well above it.
	return _body.global_transform * (_chest_anchor + Vector2(0.0, -50.0))

## Her mouth, in screen space (where a tankard is raised to drink).
func mouth_screen_position() -> Vector2:
	var size := Vector2(data.texture.get_size())
	return _body.global_transform * (data.mouth - Vector2(size.x / 2.0, size.y))

## One swallow while drinking: a quick stretch up, a low "glk" and a little
## jiggle. strength 1 = an eager gulp, less for a sip.
func gulp(strength: float = 1.0) -> void:
	_squash_velocity += 2.5 * strength
	_jiggle_velocity += Vector2(randf_range(-15.0, 15.0), -50.0) * strength
	_voice.pitch_scale = data.voice_pitch * 0.55 * randf_range(0.95, 1.05)
	_voice.play()

## The tankard reached her lips: she puckers up until finish_drinking().
func start_drinking() -> void:
	_drinking = true
	set_face(Face.KISS)

## A quick wink (ȘUKAR!, dropping her tip).
func wink() -> void:
	set_face(Face.WINK, 0.8)

## Done drinking: back to her normal face, and flushed if she liked it.
func finish_drinking(liked: bool) -> void:
	_drinking = false
	set_face(Face.DEFAULT)
	if liked:
		set_blush(true)

## A satisfied "ahh" after a good drink, with a chest pop.
func ahh() -> void:
	set_face(Face.HAPPY, 0.7)
	chest_pop()
	_voice_burst([1.3, 1.15, 1.0, 0.9, 0.85])

## She just banged the tankard down: the whole body takes the hit.
func slam_bounce() -> void:
	_squash_velocity -= 5.0
	_jiggle_velocity += Vector2(randf_range(-50.0, 50.0), 150.0)
	_boing.pitch_scale = BOING_PITCHES[data.bust] * lerpf(1.0, data.voice_pitch, 0.5) * randf_range(0.8, 0.9)
	_boing.play()
	slammed.emit(0.8)
	await get_tree().create_timer(0.12).timeout
	if is_inside_tree():
		bounce()

## A little upward bounce of the chest, like shaking a coin loose.
## Leans in at the screen with a little "mmm", smacks a kiss on it (emits
## kiss_landed at the moment of impact) and springs back to her seat.
func blow_kiss() -> void:
	if _state != State.SEATED:
		return
	var seat_position := position
	var seat_scale := scale
	set_face(Face.KISS)
	_voice_burst([1.0, 1.08, 1.16, 1.24, 1.32])
	var lean := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	lean.tween_property(self, "scale", seat_scale * 1.35, 0.4)
	lean.tween_property(self, "position:y", seat_position.y - 25.0, 0.4)
	await lean.finished
	if not is_inside_tree():
		return
	kiss_landed.emit()
	_kiss.pitch_scale = randf_range(0.95, 1.05)
	_kiss.play()
	_squash_velocity -= 4.0
	_jiggle_velocity += Vector2(randf_range(-40.0, 40.0), 140.0)
	var back := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	back.tween_property(self, "scale", seat_scale, 0.35)
	back.tween_property(self, "position:y", seat_position.y, 0.35)
	await back.finished
	if is_inside_tree():
		set_face(Face.DEFAULT)
		set_blush(true)

## Show a face. With seconds > 0 it's a flash: she goes back to the default
## face afterwards (unless something else changed it in the meantime).
func set_face(face: Face, seconds: float = 0.0) -> void:
	_face_flash += 1
	_show_face(face)
	if seconds <= 0.0:
		return
	var flash := _face_flash
	await get_tree().create_timer(seconds).timeout
	if is_inside_tree() and flash == _face_flash:
		_show_face(Face.DEFAULT)

## Anime nervous: a blue gloom pours down over her from the top, the sweat
## drops appear, and a quick ripple runs through her like through water; the
## gloom fades after nervous_hold.
func nervous() -> void:
	_ripple_left = nervous_ripple_time
	if _nervous_tween:
		_nervous_tween.kill()
	_set_shader("nervous_amount", 1.0)
	_set_shader("nervous_reveal", 0.0)
	_nervous_tween = create_tween()
	_nervous_tween.tween_method(func(v: float) -> void: _set_shader("nervous_reveal", v), 0.0, 1.0, 0.35) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_nervous_tween.tween_interval(nervous_hold)
	_nervous_tween.tween_method(func(v: float) -> void: _set_shader("nervous_amount", v), 1.0, 0.0, 0.5)

func _set_shader(param: String, value: float) -> void:
	for sprite: Sprite2D in [_body, _front]:
		(sprite.material as ShaderMaterial).set_shader_parameter(param, value)

## Fade the blush overlay in or out, on top of whatever face she has.
func set_blush(on: bool, seconds: float = 0.4) -> void:
	if data.blush == null:
		return
	if _blush_tween:
		_blush_tween.kill()
	_blush_tween = create_tween()
	_blush_tween.tween_method(_apply_blush, _blush, 1.0 if on else 0.0, seconds)

func _apply_blush(amount: float) -> void:
	_blush = amount
	for sprite: Sprite2D in [_body, _front]:
		(sprite.material as ShaderMaterial).set_shader_parameter("blush_amount", amount)

func _show_face(face: Face) -> void:
	var variant: Texture2D = [null, data.face_happy, data.face_kiss, data.face_wink][face]
	var texture := variant if variant != null else data.texture
	var shut := variant != null and face in [Face.HAPPY, Face.KISS]
	for sprite: Sprite2D in [_body, _front]:
		sprite.texture = texture
		(sprite.material as ShaderMaterial).set_shader_parameter("eyes_shut", 1.0 if shut else 0.0)

## 0 = lit, 1 = lights out: she goes black except her eye whites. In the dark
## she opens her eyes (normal face), or they'd never glow and her blink would
## be invisible; with only the eyes showing, the face swap can't be seen.
func set_lights_out(amount: float) -> void:
	if amount >= 0.5:
		set_face(Face.DEFAULT)
	for sprite: Sprite2D in [_body, _front]:
		(sprite.material as ShaderMaterial).set_shader_parameter("lights_out", amount)
	_lights_out = amount
	for bubble in _bubbles:
		if is_instance_valid(bubble):
			bubble.modulate = Color(1.0 - amount, 1.0 - amount, 1.0 - amount, bubble.modulate.a)

## A quick blink of the glowing eyes in the dark: a sound as they shut, the
## other as they open.
func blink() -> void:
	for i in 2:
		var amount := 1.0 if i == 0 else 0.0
		for sprite: Sprite2D in [_body, _front]:
			(sprite.material as ShaderMaterial).set_shader_parameter("blink", amount)
		_blink_sound.stream = BLINK_SOUNDS[i]
		_blink_sound.play()
		await get_tree().create_timer(0.12).timeout
		if not is_inside_tree():
			return

func chest_pop() -> void:
	bounce()
	_jiggle_velocity += Vector2(randf_range(-50.0, 50.0), -220.0)
	_squash_velocity += 3.0

func _voice_burst(pitches: Array) -> void:
	for pitch: float in pitches:
		_voice.pitch_scale = data.voice_pitch * pitch * randf_range(0.95, 1.05)
		_voice.play()
		await get_tree().create_timer(0.06).timeout
		if not is_inside_tree():
			return
func is_seated() -> bool:
	return _state == State.SEATED

func stand_up() -> void:
	if _state != State.SEATED:
		return
	_front.visible = false
	_hop = 0.0
	_hop_velocity = 0.0
	_squash_velocity += 3.0
	_enter(State.STAND)

func hit_test(global_point: Vector2) -> bool:
	return _body.is_pixel_opaque(_body.to_local(global_point))

## Tipsy: now and then a hiccup, sooner the more she's had. Not while the
## tankard is at her lips, and not in the dark.
func _update_hiccups(delta: float) -> void:
	if drunk < hiccup_from or _drinking or _lights_out > 0.0:
		return
	_hiccup_timer -= delta
	if _hiccup_timer <= 0.0:
		hiccup()
		_reset_hiccup_timer()

func _reset_hiccup_timer() -> void:
	var interval := randf_range(hiccup_interval.x, hiccup_interval.y) / maxf(drunk, 1.0)
	_hiccup_timer = maxf(interval, min_hiccup_interval)

## A hiccup: a jolt up, a "hic" in her pitch, and a few bubbles float out of
## her mouth and pop.
func hiccup() -> void:
	if _state != State.SEATED:
		return
	_hop_velocity = -110.0
	_hop = -0.01
	_squash_velocity += 4.0
	_jiggle_velocity += Vector2(randf_range(-30.0, 30.0), -90.0)
	_hiccup_sound.stream = HICCUP_SOUNDS.pick_random()
	_hiccup_sound.pitch_scale = lerpf(1.0, data.voice_pitch, 0.5) * randf_range(0.95, 1.05)
	_hiccup_sound.play()
	# Forget the ones that already popped.
	for i in range(_bubbles.size() - 1, -1, -1):
		if not is_instance_valid(_bubbles[i]):
			_bubbles.remove_at(i)
	var mouth := mouth_screen_position()
	for i in randi_range(bubbles_per_hiccup.x, bubbles_per_hiccup.y):
		var bubble: Sprite2D = HiccupBubble.new()
		bubble.size = randf_range(0.12, 0.28)
		bubble.rise_speed = randf_range(16.0, 30.0)
		bubble.life = randf_range(1.0, 2.2)
		# Next to her, over the counter, so they pop in front of everything.
		get_parent().add_child(bubble)
		bubble.global_position = mouth + Vector2(randf_range(-4.0, 4.0), randf_range(-3.0, 3.0))
		_bubbles.append(bubble)
		await get_tree().create_timer(randf_range(0.04, 0.12)).timeout
		if not is_inside_tree():
			return

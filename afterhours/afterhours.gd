class_name AfterHoursScene
extends Node2D

## After hours below deck: the rear view (BodyRig), her face in the porthole
## (PortholeCam), a heart beating at the pace she wants (HeartBeat).
##
## The penis follows the mouse and faces the nearer hole. Hold the button
## and push up into the pussy from below, down into the anus from above: it
## presses on the hole until it pops in, and backing out slides it out. Not
## holding it, the penis glides over the holes. A stroke counts when it goes
## deep; shallow ones tease her a little (more early on). A hole resists before it pops open; jab too fast and the tip
## bounces off. Push hard past her no on the anus and you force it: she
## cries out and it costs comfort. Strokes on her pace bounce harder and
## send up hearts. How it's going sinks into her mood slowly (mood_lag), so
## one uneven stroke doesn't flip it; she only complains once she's been
## unhappy for a while, and she talks at most every line_gap seconds unless
## something big happens. She presents herself first (the intro). Going deeper than
## fapwall's depth gets a reaction: she loves it or it's too much (likes_deep).
##
## Two meters race: hers (arousal, built on her pace) and yours (every
## stroke, faster when fast or deep, cooling off when you ease up). Hers full:
## she cums. Yours full: the edge, inside or out. Get her there first; both
## within a few seconds is the best ending. Stay on her pace to
## build her up, stage by stage, to the finish. Rushing, the wrong hole or
## pushing past a no costs comfort; at zero she stops. Esc pauses (the bar's
## pause menu: resume, options, or leave to the main menu). The
## result is rated like a drink.

const BAR_SCENE := "res://main.tscn"
const SCROLL_BUTTON: PackedScene = preload("res://menu/scroll_button.tscn")
const THRUST_SOUNDS: Array[AudioStream] = [
	preload("res://audio/placeholder/fapwall/thrust1.wav"),
	preload("res://audio/placeholder/fapwall/thrust2.wav"),
	preload("res://audio/placeholder/fapwall/thrust3.wav"),
	preload("res://audio/placeholder/fapwall/thrust4.wav"),
]
const SLAP_SOUND: AudioStream = preload("res://audio/placeholder/fapwall/slap.wav")
const PRECUM_SOUND: AudioStream = preload("res://audio/placeholder/fapwall/precum.wav")
## A slap on her butt (left click).
const SLAP_HIT_SOUND: AudioStream = preload("res://audio/slap.wav")
## In or out of a hole.
const HOLE_POP_SOUND: AudioStream = preload("res://audio/hole_pop.wav")
## Her landing in the intro: the boing her chest makes in the bar (her bust).
const BOING_SOUNDS: Array[AudioStream] = preload("res://customer/customer.gd").BOING_SOUNDS
const BOING_PITCHES: Array[float] = preload("res://customer/customer.gd").BOING_PITCHES
const CUM_SOUNDS: Array[AudioStream] = [
	preload("res://audio/placeholder/fapwall/cum1.wav"),
	preload("res://audio/placeholder/fapwall/cum2.wav"),
]

## Set before changing to this scene to skip the picker (the bar's debug keys do).
static var next_girl: CustomerData
## Where leaving goes. The main menu sets itself; it's back to the bar otherwise.
static var return_scene := BAR_SCENE

enum State { PICK, INTRO, PLAY, EDGE, FINISH, END }

## Given in the inspector, the scene starts with her (no picker). She needs
## After Hours filled in.
@export var character: CustomerData

## Her After Hours: body, tastes, lines.
var girl: AfterHoursGirl

@export_group("Feel")
## Pulling out faster than this (depth per second) is a slip, and she says so.
@export var slip_speed: float = 9.0
## How far past the entrance (rig pixels) the tip goes before it's out.
@export var exit_margin: float = 3.0
## The player's difficulty (Settings.difficulty: relaxed, normal, strict)
## scales how far off her pace she takes and how touchy she is.
const DIFFICULTY_TOLERANCE: Array[float] = [1.4, 1.0, 0.75]
const DIFFICULTY_TOUCHINESS: Array[float] = [0.6, 1.0, 1.4]

## Seconds between slaps (left click on her butt).
@export var slap_cooldown: float = 0.15
## Seconds between the same kind of remark (too fast, too slow...).
@export var remark_cooldown: float = 10.0
## Seconds of quiet after any line before she chats again (big moments
## still cut in: forced, wrong hole, cumming, the edge...).
@export var line_gap: float = 6.0
## Seconds her mood takes to (mostly) catch up with how it's going.
@export var mood_lag: float = 2.5
## Seconds unhappy (too fast, too slow, stopped) before she says so, and
## after that, before she says it again.
@export var complain_after: float = 4.0
@export var complain_again: float = 25.0
## How low her mood (-1..1) has to be to count as unhappy.
@export var unhappy_below: float = -0.5

# Laid out in afterhours.tscn: move them there.
@onready var _world: Node2D = $World
@onready var _rig: BodyRig = $World/Rig
@onready var _drips: CPUParticles2D = $World/Rig/Drips
@onready var _sweat: SweatDrops = $World/Rig/Sweat
## Burst template: _love() copies it for each burst of hearts.
@onready var _hearts: CPUParticles2D = $World/Rig/Hearts
@onready var _porthole: PortholeCam = $Porthole
@onready var _heart: HeartBeat = $Heart
@onready var _gauge: PaceGauge = $PaceGauge
@onready var _her_meter: MeterBar = $Heart/HerMeter
@onready var _you_meter: MeterBar = $Heart/YouMeter
# Untyped: their scripts (ui/speech_bubble.gd, ui/kiss_layer.gd, menu/scroll_button.gd) have no class_name.
@onready var _bubble = $SpeechBubble
@onready var _kisses = $KissLayer
@onready var _hint: Label = $UI/Hint
@onready var _choices: HBoxContainer = $UI/Choices
@onready var _ask_button = $UI/AskButton
@onready var _voice: AudioStreamPlayer = $Voice
## The bar's music, on below deck too.
@onready var _music: AudioStreamPlayer = $Music
## Sliding in and out of her plays it like a bow (violin_bow.gd), on top of
## the thrust sounds.
@onready var _violin: ViolinBow = $Violin
## The 3D sparks a slap throws (afterhours/fx/sparks.tscn, from Mechsodus),
## rendered in their own little 3D view and shown where the slap lands.
@onready var _slap_sparks: Sprite2D = $SlapSparks
@onready var _slap_view: SubViewport = $SlapSparks/Viewport

var _state := State.PICK
var _world_base := Vector2.ZERO

var _arousal := 0.0
var _comfort := 0.8
var _stage := 0
var _prev_tip := Vector2.ZERO
var _last_thrust := -10.0
## Your strokes per second, from the last few strokes (0 = no rhythm yet).
var _tempo := 0.0
var _intervals: Array[float] = []
## How she feels about it, -1 (hates it) .. 1 (loves it), easing toward
## _mood_target (set by each stroke) over mood_lag.
var _mood := 0.0
var _mood_target := 0.0
## Likewise, which way you're off: + too fast, - too slow (in tolerances).
var _drift := 0.0
var _drift_target := 0.0
## Seconds she's been unhappy (negative: waiting to say it again).
var _unhappy_for := 0.0
var _last_line := -100.0
var _slapped_at := -100.0
## How worked up her butt is from slaps: up with each, cooling off (picks
## her very-red slap line, marks on or off).
var _slap_heat := 0.0
## A line that waits for a gap to be said (stage lines).
var _pending := ""
var _good_streak := 0
var _anal_granted := false
var _refused_at := -1.0
var _respected := false
var _last_said := {}
## The slow strokes while you choose how to finish.
var _edge_tween: Tween
var _time := 0.0
var _shake := 0.0
var _pull_speed := 0.0
## Took the anus past her no (until she says yes or it's over).
var _forced := false
## Deep reactions, once per time in: went past fapwall's depth, went all in.
var _went_deep := false
var _went_all_in := false
## A blush spike that fades (deep reactions).
var _blush_boost := 0.0
## Counts down to her next whimper while a refused hole is being forced.
var _whimper_in := 0.0
## Your meter, 0..1 (full = the edge).
var _pleasure := 0.0
var _she_came := false
var _she_came_at := -100.0
## Seconds apart that still count as cumming together.
const TOGETHER := 3.0
## After she cums her meter drains back to AFTERGLOW_LEVEL over this long,
## then she can build up and cum again.
const AFTERGLOW := 2.0
const AFTERGLOW_LEVEL := 0.3
## Her penis's spurts as she cums: [seconds after, power].
const SPURTS := [[0.0, 1.0], [0.3, 0.85], [0.6, 0.7], [0.95, 0.5], [1.35, 0.35]]
var _ended_at := 0.0

func _ready() -> void:
	_world_base = _world.position
	_music.finished.connect(_music.play) # placeholder track: just loop it, like the bar
	_slap_sparks.texture = _slap_view.get_texture()
	_rig.thrust.connect(_on_thrust)
	_rig.shallow.connect(_on_shallow)
	_rig.press_started.connect(_on_press_started)
	_rig.popped.connect(_on_popped)
	_rig.pulled_out.connect(_on_pulled_out)
	_rig.bounced.connect(_on_bounced)
	_rig.forced.connect(_on_forced)
	_ask_button.pressed.connect(_ask_anal)
	# Buses in code: the editor drops ones it doesn't know (Settings makes
	# them when the game starts) from the scene when it saves.
	_music.bus = &"CabinMusic"
	_voice.bus = &"Voice"
	_bubble.get_node("Tick").bus = &"Voice"
	# Nobody's there until she's picked.
	for node: CanvasItem in [_rig, _porthole, _heart, _gauge, _ask_button, _her_meter, _you_meter]:
		node.visible = false
	_choices.visible = false
	Debug.all_girls_changed.connect(func() -> void:
		if _state == State.PICK:
			_pick())
	if next_girl:
		character = next_girl
		next_girl = null
	if character:
		_start()
	else:
		_pick()

func _exit_tree() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	return_scene = BAR_SCENE

## Who's staying after closing? Only the girls whose bar you've filled
## (SaveManager.after_hours), or all of them with the debug G toggle.
func _pick() -> void:
	_state = State.PICK
	_hint.text = "Who's staying after closing?   Esc menu"
	var picks: Array = []
	var girls := AfterHoursGirl.all()
	for girl_name: String in girls:
		if SaveManager.stays_after_hours(girls[girl_name]):
			picks.append([girl_name, girls[girl_name]])
	if picks.is_empty():
		_hint.text = "Nobody's staying yet. Win a girl over first.   Esc menu"
	_show_choices(picks, func(option: CustomerData) -> void:
		character = option
		_start())

func _start() -> void:
	girl = character.after_hours
	_rig.setup(girl)
	_rig.move_child(_drips, -1) # over her, not under the body setup() just built
	_rig.move_child(_hearts, -1)
	_porthole.setup(character)
	for node: CanvasItem in [_rig, _porthole, _heart, _gauge, _her_meter, _you_meter]:
		node.visible = true
	_ask_button.visible = _anal_consent() == AfterHoursGirl.Consent.ASK
	_rig.can_force = Settings.forced and Settings.anal != 2 # anal off: no way in there at all
	_rig.show_marks = Settings.marks
	_update_mood()
	_intro()

## She presents herself: her butt jumps up into view from below the screen
## (stretched on the way up, past her spot, back down, squashing as it
## lands) and invites you. The penis shows up after, then it's on.
func _intro() -> void:
	_state = State.INTRO
	_hint.text = ""
	_rig.visible = true
	_rig.show_penis(false)
	var home := _rig.position
	var size := _rig.scale
	_rig.position = home + Vector2(0, 460)
	_rig.scale = size * Vector2(0.85, 1.2)
	_rig.rotation = 0.0
	var jump := create_tween()
	# Up past her spot, stretched tall...
	jump.tween_property(_rig, "position", home + Vector2(0, -36), 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	jump.parallel().tween_property(_rig, "scale", size * Vector2(0.9, 1.12), 0.5)
	# ...back down...
	jump.tween_property(_rig, "position", home, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	jump.parallel().tween_property(_rig, "scale", size * Vector2(0.95, 1.06), 0.2)
	# ...squashes on landing and wobbles back.
	jump.tween_property(_rig, "scale", size * Vector2(1.2, 0.82), 0.07)
	jump.tween_property(_rig, "scale", size, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.7).timeout
	# The same boing as her chest landing on the bar counter.
	var bust: int = character.bust
	_play(BOING_SOUNDS[bust], BOING_PITCHES[bust] * lerpf(1.0, character.voice_pitch, 0.5) * randf_range(0.95, 1.05), 0.0)
	await jump.finished
	_say("start", true)
	await get_tree().create_timer(0.3).timeout
	if _state != State.INTRO:
		return # left during it
	_rig.show_penis(true)
	_state = State.PLAY
	var how := "Hold click: Yo Srkill drop it hard" if _rig.has_penis() else "Hold click: Pizdă și cur o algo"
	if Settings.anal == 2:
		how = "Hold click: Apasă pe lanternă"
	_hint.text = how + "   Esc pause"
	# The penis is the cursor now.
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_prev_tip = _tip()

func _process(delta: float) -> void:
	_time += delta
	_shake = move_toward(_shake, 0.0, delta * 2.0)
	_world.rotation = Sea.roll * 0.5
	_her_meter.value = _arousal
	_you_meter.value = _pleasure
	_world.position = _world_base + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake * 4.0 * Settings.shake_scale()
	# Every state, so the slow strokes at the edge play too and it dies away at the end.
	_violin.bow(_rig.depth, _rig.inserted, delta)
	if _state != State.PLAY:
		return
	_steer(delta)
	_update_strain(delta)
	_update_deep(delta)
	_update_idle(delta)
	_update_feelings(delta)
	if _time - _last_thrust > 1.0:
		_pleasure = maxf(_pleasure - delta * 0.03, 0.0) # easing off cools you down
	_blush_boost = move_toward(_blush_boost, 0.0, delta * 0.5)
	_slap_heat = move_toward(_slap_heat, 0.0, delta * 0.1)
	if _she_came and _time - _she_came_at < AFTERGLOW:
		_arousal = move_toward(_arousal, AFTERGLOW_LEVEL, delta * (1.0 - AFTERGLOW_LEVEL) / AFTERGLOW * 1.4)
	# Her wetness builds up on the penis while it's in her (more the hornier
	# she is) and dries off slowly once it's out.
	if _rig.inserted:
		_rig.coat = minf(_rig.coat + delta * 0.025 * (0.3 + _arousal), 1.0)
	else:
		_rig.coat = maxf(_rig.coat - delta * 0.008, 0.0)
	_update_mood()
	_heart.tempo = girl.pace[_stage]
	_heart.fill = _arousal
	# Your rhythm on the gauge, sagging toward slow while you pause.
	var live := minf(_tempo, 1.0 / maxf(_time - _last_thrust, 0.01)) if _tempo > 0.0 else 0.0
	_gauge.ratio = live / girl.pace[_stage] if _rig.inserted else 0.0
	_gauge.tolerance = _tolerance()
	_rig.arousal = _arousal
	_sweat.amount = _arousal if Settings.sweat else 0.0
	_rig.shine = pow(_arousal, 1.5)

## The tip goes where the mouse is. Pushing up into a hole presses on it
## until it pops in; inside, how far up the mouse is is how deep it goes.
func _steer(delta: float) -> void:
	var tip := _tip()
	if _rig.inserted:
		# The hole grips: the penis lags behind the mouse, more in a tight one.
		var target := _rig.grip_follow(_rig.depth_for(tip), delta)
		# Smoothed, so one jumpy mouse frame doesn't count as a yank.
		_pull_speed = lerpf(_pull_speed, (target - _rig.depth) / delta, 0.3)
		_rig.depth = target
		if _rig.is_out(tip, exit_margin):
			var yanked := _pull_speed < -slip_speed
			_rig.pull_out()
			_pull_speed = 0.0
			if yanked:
				_slip()
	else:
		_rig.aim = tip
		_rig.push(_prev_tip, tip, delta, Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT))
	_prev_tip = tip

## In: a pop, a gasp, a jolt, a few hearts.
func _on_popped(_hole: BodyRig.Hole, strength: float) -> void:
	_play(HOLE_POP_SOUND, randf_range(0.95, 1.1), 0.0)
	_play(PRECUM_SOUND, randf_range(0.9, 1.1), -6.0)
	_shake = maxf(_shake, 0.35 * strength)
	_porthole.jolt()
	_gasp()
	_chat("insert", 20.0)
	_love(3 + int(strength * 3.0))

## Out of her: the same pop, a little higher.
func _on_pulled_out(_hole: BodyRig.Hole) -> void:
	_play(HOLE_POP_SOUND, randf_range(1.1, 1.25), -2.0)

## Skidded off the closed hole.
func _on_bounced(_hole: BodyRig.Hole) -> void:
	_play(SLAP_SOUND, 1.4, -12.0)
	_porthole.jolt()

## Forced the anus past her no: she cries out and it costs comfort.
func _on_forced(_hole: BodyRig.Hole) -> void:
	_forced = true
	_rig.flinch()
	_porthole.jolt()
	_shake = maxf(_shake, 0.5)
	_play(SLAP_SOUND, 0.9, -2.0)
	_play(HOLE_POP_SOUND, randf_range(0.85, 0.95), 0.0)
	_gasp()
	_say("forced", true)
	_lose_comfort(0.3)
	_update_mood()

## The tip started pressing on a hole: she can refuse before it goes in.
func _on_press_started(hole: BodyRig.Hole) -> void:
	if hole == BodyRig.Hole.ANUS and not _anal_allowed():
		_rig.block()
		if Settings.anal != 2:
			_wrong_hole() # with anal off in the settings it just doesn't go in

## The mouse in her butt's space (where the holes are), kept to the area around her.
func _tip() -> Vector2:
	var mouse := _rig.to_body(_rig.get_local_mouse_position())
	return Vector2(clampf(mouse.x, -130.0, 130.0), clampf(mouse.y, -320.0, 420.0))

func _unhandled_input(event: InputEvent) -> void:
	if _state == State.PLAY and event is InputEventMouseButton and event.pressed 			and event.button_index == MOUSE_BUTTON_LEFT:
		_try_slap()
	elif _state == State.END and event is InputEventMouseButton and event.pressed:
		# A moment first, so a click mid-stroke doesn't skip her last line.
		if _time - _ended_at > 1.5:
			Transition.change_scene(return_scene)

func _anal_allowed() -> bool:
	return _anal_consent() == AfterHoursGirl.Consent.YES or _anal_granted

## Her anal consent. A girl with her own penis has no pussy to use, so it's
## always yes: it's the only way in (her lines can still be shy about it).
## The settings can make every girl need asking, or turn anal off (then her
## penis is gone too, see BodyRig.has_penis()).
func _anal_consent() -> AfterHoursGirl.Consent:
	if _rig.has_penis():
		return AfterHoursGirl.Consent.YES
	if Settings.anal == 2:
		return AfterHoursGirl.Consent.NO
	if Settings.anal == 1 and girl.anal == AfterHoursGirl.Consent.YES:
		return AfterHoursGirl.Consent.ASK
	return girl.anal

## A deep stroke landed.
func _on_thrust(strength: float) -> void:
	if _state != State.PLAY:
		return
	_note_stroke()
	_play(THRUST_SOUNDS.pick_random(), randf_range(0.92, 1.08), linear_to_db(0.7 + 0.6 * strength))
	if strength > 0.6:
		_play(SLAP_SOUND, randf_range(0.95, 1.1), -4.0)
	if _arousal > 0.3:
		_voice.pitch_scale = character.voice_pitch * randf_range(0.9, 1.0) * (1.0 + _arousal * 0.3)
		_voice.play()
	_shake = maxf(_shake, 0.15 * strength * (1.0 + _stage * 0.3))
	if _rig.shine > 0.35:
		# Wet.
		_play(PRECUM_SOUND, randf_range(1.2, 1.4), linear_to_db(0.2 + 0.4 * _rig.shine) - 4.0)
	var off := _off_pace()
	var fit := _fit(off)
	var forced_now := _forced and _rig.hole == BodyRig.Hole.ANUS and not _anal_allowed()
	# Yours builds with every stroke: harder, faster and deeper build it quicker.
	var rushing := 1.3 if off > 1.0 else 1.0
	_pleasure = minf(_pleasure + 0.035 * strength * (1.0 + clampf(_rig.depth - 1.0, 0.0, 3.0) * 0.15) * rushing, 1.0)
	if forced_now:
		# She's not into it: it barely builds, and she says so.
		_rig.impact(strength * 0.9)
		_arousal += girl.arousal_per_stroke * 0.3
		_lose_comfort(0.04)
		_good_streak = 0
		_mood_target = -1.0
		_chat("forced")
	else:
		# The closer to her pace, the juicier: harder bounce, more arousal.
		# Rushing costs comfort, the more the further off.
		_rig.impact(strength * lerpf(0.8 if off > 0.0 else 0.6, 1.4, fit))
		_arousal += girl.arousal_per_stroke * lerpf(0.3 if off > 0.0 else 0.4, 1.0, fit)
		if off > 0.0:
			_lose_comfort(0.05 * (1.0 - fit))
		_comfort = minf(_comfort + 0.01 * fit, 1.0)
		_judge(off, fit)
		if fit >= 0.8:
			_good_streak += 1
			_heart.glow()
			_love(1 + _stage)
			if _good_streak % 8 == 0 and _mood > 0.4:
				_chat("good")
		else:
			_good_streak = 0
			if off > 1.0:
				_porthole.jolt()
	_after_stroke()

## A shallow stroke: teasing. It keeps the rhythm and builds her up a
## little, mostly early on (less every stage).
func _on_shallow(length: float) -> void:
	if _state != State.PLAY:
		return
	_note_stroke()
	_play(THRUST_SOUNDS.pick_random(), randf_range(1.1, 1.25), linear_to_db(0.3 + 0.3 * length))
	var off := _off_pace()
	var fit := _fit(off)
	_pleasure = minf(_pleasure + 0.035 * 0.3 * length, 1.0)
	_rig.impact(0.4 * length * lerpf(0.6, 1.0, fit))
	if _forced and _rig.hole == BodyRig.Hole.ANUS and not _anal_allowed():
		_mood_target = -1.0
		return
	var teasing := lerpf(1.0, 0.25, float(_stage) / maxf(girl.pace.size() - 1, 1))
	_arousal += girl.arousal_per_stroke * 0.4 * fit * teasing
	_judge(off, fit)
	_after_stroke()

## What every stroke does after landing: stages, her mood, the finish.
func _after_stroke() -> void:
	if _state != State.PLAY:
		return # she'd had enough
	_check_respected()
	_arousal = minf(_arousal, 1.0)
	var stage := mini(int(_arousal * girl.pace.size()), girl.pace.size() - 1)
	if stage != _stage:
		# Back down after she cums, quietly; a line only on the way up.
		if stage > _stage:
			_chat("stage_%d" % stage, 0.0, true)
		_stage = stage
	_update_mood()
	_check_climaxes()

## A stroke's time goes into your tempo: the average of the last few, so
## one uneven stroke barely moves it. After a long pause it starts over.
func _note_stroke() -> void:
	var interval := _time - _last_thrust
	_last_thrust = _time
	if interval >= 4.0:
		_intervals.clear()
		_tempo = 0.0
		return
	_intervals.append(interval)
	if _intervals.size() > 4:
		_intervals.pop_front()
	var total := 0.0
	for each in _intervals:
		total += each
	_tempo = _intervals.size() / total

## How far your tempo is off hers, in her tolerances: 0 = on it, +1 = as
## fast as she still takes, -1 = as slow. No rhythm yet counts as on it.
func _off_pace() -> float:
	if _tempo <= 0.0:
		return 0.0
	return (_tempo / girl.pace[_stage] - 1.0) / _tolerance()

## Her pace tolerance and touchiness, with the player's difficulty.
func _tolerance() -> float:
	return girl.pace_tolerance * DIFFICULTY_TOLERANCE[Settings.difficulty]

func _touchiness() -> float:
	return girl.touchiness * DIFFICULTY_TOUCHINESS[Settings.difficulty]

## 1 = on her pace, fading to 0 just past her tolerance either way.
func _fit(off: float) -> float:
	return clampf((1.4 - absf(off)) / 0.6, 0.0, 1.0)

## Where her mood heads after this stroke.
func _judge(off: float, fit: float) -> void:
	_mood_target = fit * 2.0 - 1.0
	_drift_target = clampf(off, -2.0, 2.0)

## Her mood eases toward how it's going; unhappy for complain_after, she
## says why (too fast or too slow), then not again for complain_again.
## A line held for a gap gets said once there is one.
func _update_feelings(delta: float) -> void:
	var catch_up := 1.0 - exp(-delta * 2.0 / mood_lag)
	_mood = lerpf(_mood, _mood_target, catch_up)
	_drift = lerpf(_drift, _drift_target, catch_up)
	if not _pending.is_empty():
		var event := _pending
		_pending = ""
		_chat(event, 0.0, true)
	if not _rig.inserted:
		_unhappy_for = minf(_unhappy_for, 0.0)
		return
	if _mood < unhappy_below:
		_unhappy_for += delta
		if _unhappy_for >= complain_after and _chat("too_fast" if _drift > 0.0 else "too_slow"):
			_unhappy_for = complain_after - complain_again
	elif _mood > 0.0:
		_unhappy_for = 0.0

## Her meter full: she cums. Yours full: the edge.
func _check_climaxes() -> void:
	if _state != State.PLAY:
		return
	if _arousal >= 1.0 and _time - _she_came_at > AFTERGLOW:
		_her_climax()
	if _pleasure >= 1.0:
		_edge()

func _her_climax() -> void:
	_she_came = true
	_she_came_at = _time
	_arousal = 1.0
	_rig.climax()
	_porthole.jolt()
	_shake = maxf(_shake, 0.8)
	_gasp()
	_love(16)
	_heart.glow()
	_comfort = minf(_comfort + 0.2, 1.0) # afterglow
	if _rig.inserted:
		_rig.coat = minf(_rig.coat + 0.45, 1.0) # soaked
	if _rig.has_penis():
		# Her penis cums too, in spurts.
		for spurt: Array in SPURTS:
			get_tree().create_timer(spurt[0]).timeout.connect(_spurt.bind(spurt[1]))
	_say("her_cum", true)

## One spurt of her penis: it pumps, a burst of drops flies, a little shake.
func _spurt(power: float) -> void:
	_rig.futa_spurt(power)
	_shake = maxf(_shake, 0.25 * power)
	_play(PRECUM_SOUND, randf_range(0.85, 1.0), linear_to_db(0.3 + 0.5 * power))
	if Settings.cum == 2:
		return # no cum shown, in the settings
	var burst := _drips.duplicate() as CPUParticles2D
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.amount = maxi(int(14 * power), 3)
	burst.initial_velocity_min = 20.0 + 30.0 * power
	burst.initial_velocity_max = 40.0 + 70.0 * power
	burst.position = _rig.futa_tip()
	_rig.add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)

## Pushing on a hole she refused: she whimpers, faster the closer it is to
## giving, and the screen shakes a little.
func _update_strain(delta: float) -> void:
	if _rig.forcing <= 0.0:
		_whimper_in = 0.0
		return
	_shake = maxf(_shake, _rig.forcing * 0.15)
	_whimper_in -= delta
	if _whimper_in <= 0.0:
		_whimper_in = 0.45 - 0.25 * _rig.forcing
		_voice.pitch_scale = character.voice_pitch * randf_range(1.3, 1.45)
		_voice.play()
		if _rig.forcing > 0.3:
			_porthole.jolt()

## Deeper than fapwall's depth: she reacts the first time (and again at the
## whole length), then holding it there builds her up or wears her down.
func _update_deep(delta: float) -> void:
	if not _rig.inserted:
		_went_deep = false
		_went_all_in = false
		return
	var deep := _rig.depth > 1.05
	var into_it := girl.likes_deep >= 0.5 or _arousal >= 0.5
	if deep and not _went_deep:
		_went_deep = true
		_deep_reaction("deep" if into_it else "too_deep", into_it, 1.0)
	if _rig.depth >= _rig.max_depth() * 0.95 and _rig.max_depth() > 1.5 and not _went_all_in:
		_went_all_in = true
		_deep_reaction("all_in" if into_it else "too_deep", into_it, 1.6)
	if deep and not into_it:
		_mood_target = minf(_mood_target, -0.5)
	if deep and _state == State.PLAY:
		if into_it:
			_arousal = minf(_arousal + delta * 0.02 * maxf(girl.likes_deep, 0.5), 1.0)
			_check_climaxes()
		else:
			_lose_comfort(delta * 0.015 * (1.0 - girl.likes_deep))

func _deep_reaction(event: String, into_it: bool, size: float) -> void:
	_porthole.jolt()
	_gasp()
	_blush_boost = 0.6 * size
	_shake = maxf(_shake, 0.25 * size)
	_chat(event, 15.0 if into_it else 45.0)
	if into_it:
		_arousal = minf(_arousal + 0.04 * size * maxf(girl.likes_deep, 0.5), 1.0)
		_love(int(4 * size))
		_check_climaxes()
	else:
		_rig.flinch()
		_lose_comfort(0.03 * size * (1.0 - girl.likes_deep))

## Too long without a stroke: she cools off, and it's too slow for her
## (she says so once she's been unhappy a while, see _update_feelings).
func _update_idle(delta: float) -> void:
	if not _rig.inserted or _time - _last_thrust < 3.0 / girl.pace[_stage]:
		return
	_arousal = maxf(_arousal - delta * 0.02, 0.0)
	_mood_target = minf(_mood_target, -0.6)
	_drift_target = -2.0

## Yanked out too fast (she only says so once she's warmed up).
func _slip() -> void:
	_arousal = maxf(_arousal - 0.05, 0.0)
	if _arousal > 0.25:
		_chat("slip", 40.0)

func _wrong_hole() -> void:
	_rig.flinch()
	_porthole.jolt()
	_play(SLAP_SOUND, 1.3, -10.0)
	if _refused_at >= 0.0:
		# She said no, you went for it anyway.
		_lose_comfort(0.5)
		if _comfort > 0.0:
			_say("pushed", true)
	else:
		_lose_comfort(0.15)
		if _comfort > 0.0:
			_say("wrong_hole", true)
	_update_mood()

func _ask_anal() -> void:
	if _state != State.PLAY or _anal_granted:
		return
	if _comfort >= girl.anal_yes_comfort and _arousal >= girl.anal_yes_arousal:
		_anal_granted = true
		_refused_at = -1.0
		_ask_button.visible = false
		_say("ask_yes", true)
	else:
		_refused_at = _time
		_say("ask_no", true)

## Twenty seconds after a no, still going and still behaving: she notices.
func _check_respected() -> void:
	if _refused_at >= 0.0 and not _respected and _time - _refused_at > 20.0:
		_respected = true
		_comfort = minf(_comfort + 0.15, 1.0)
		_say("respected", true)

func _lose_comfort(amount: float) -> void:
	_comfort -= amount * _touchiness()
	if Settings.endless:
		_comfort = maxf(_comfort, 0.05) # she complains but stays
		return
	if _comfort <= 0.0:
		_comfort = 0.0
		_say("angry_stop", true)
		_porthole.set_face(PortholeCam.Face.DEFAULT)
		_rig.pull_out()
		_end(0.0)

func _update_mood() -> void:
	var happy := (_stage >= 2 or _she_came) and _comfort > 0.5 and _mood > -0.3
	_porthole.set_face(PortholeCam.Face.HAPPY if happy else PortholeCam.Face.DEFAULT)
	var nervous := maxf(maxf(clampf((0.6 - _comfort) * 2.0, 0.0, 1.0), _rig.forcing), clampf(-_mood, 0.0, 1.0) * 0.5)
	_porthole.set_mood(clampf(_arousal * 1.4 + _blush_boost, 0.0, 1.0), nervous, _arousal * 2.0)

## Arousal is full: inside or out?
func _edge() -> void:
	_state = State.EDGE
	_say("edge", true)
	# Outside only (the settings): there's nothing to decide.
	_show_choices([["Pull out", false]] if Settings.cum == 1 else [["Inside", true], ["Pull out", false]], _finish)
	if _ask_button:
		_ask_button.visible = false
	# Keep going slowly while you decide.
	_edge_tween = create_tween().set_loops()
	_edge_tween.tween_property(_rig, "depth", 1.0, 0.35)
	_edge_tween.tween_property(_rig, "depth", 0.4, 0.35)

func _finish(inside: bool) -> void:
	if _state != State.EDGE:
		return
	_state = State.FINISH
	_edge_tween.kill()
	_rig.depth = 1.0
	_rig.climax()
	if not _forced:
		_love(18)
	_porthole.jolt()
	_porthole.set_face(PortholeCam.Face.KISS)
	_shake = 1.0
	_play(CUM_SOUNDS.pick_random(), 1.0, 0.0)
	_say("inside" if inside else "outside", true)
	await get_tree().create_timer(1.2).timeout
	if _state != State.FINISH:
		return
	_play(CUM_SOUNDS.pick_random(), 0.9, -4.0)
	var at := _rig.entrance(_rig.hole)
	var filled := _rig.hole
	_rig.pull_out()
	if not inside:
		_rig.aim = at + Vector2(0, -30) # over her butt
	if Settings.cum != 2: # no cum shown, in the settings
		if inside:
			# fapwall's creampie: it shows in her hole and runs down her butt.
			_rig.cum_inside(filled)
		else:
			_rig.cum_outside()
		# A few drops falling on top of fapwall's cum layers.
		_drips.position = _rig.from_body(at)
		_drips.emitting = true
	await get_tree().create_timer(1.6).timeout
	_drips.emitting = false
	if _state != State.FINISH:
		return
	# Outside only (the settings): she doesn't hold it against you.
	var matched := inside == girl.wants_inside or Settings.cum == 1
	_say("after" if _she_came else "not_yet", true)
	_porthole.set_face(PortholeCam.Face.WINK if _she_came else PortholeCam.Face.DEFAULT)
	# Her first matters most; at the same time is the best.
	var together := _she_came and _time - _she_came_at <= TOGETHER + 2.8 # the finish itself takes ~2.8 s
	var score := _comfort * 0.4 + (0.35 if _she_came else 0.0) + (0.25 if matched else 0.05)
	if together:
		score += 0.2
		_kisses.shout("TOGETHER!", Color(1, 0.6, 0.8), 0.7)
	if Settings.endless:
		_rate(score)
		_next_round()
	else:
		_end(score)

## Rated like a drink (the bar's words), then click to go back.
func _end(score: float) -> void:
	_state = State.END
	_ended_at = _time
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_show_choices([], Callable())
	if _edge_tween:
		_edge_tween.kill()
	if _ask_button:
		_ask_button.visible = false
	_rate(score)
	_hint.text = "Click to go back up"

## Endless: shows how it went, then both meters start over and she's ready again.
func _next_round() -> void:
	await get_tree().create_timer(1.5).timeout
	if _state != State.FINISH:
		return
	_pleasure = 0.0
	_arousal = 0.0
	_stage = 0
	_she_came = false
	_she_came_at = -100.0
	_forced = false
	_tempo = 0.0
	_intervals.clear()
	_mood = 0.0
	_mood_target = 0.0
	_drift = 0.0
	_drift_target = 0.0
	_unhappy_for = 0.0
	_pending = ""
	_good_streak = 0
	_rig.arousal = 0.0
	_rig.shine = 0.0
	_state = State.PLAY
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	_prev_tip = _tip()
	_update_mood()
	_say("start", true)

## Shown like a drink's rating (the bar's words).
func _rate(score: float) -> void:
	var rating: Array
	if score > 0.85:
		rating = ["ȘUKAR!", Color(1, 0.85, 0.35), 1.0]
		_kisses.stamp()
	elif score > 0.6:
		rating = ["MIȘTO!", Color(1, 0.93, 0.65), 0.8]
	elif score > 0.35:
		rating = ["meh...", Color(0.75, 0.72, 0.68), 0.65]
	else:
		rating = ["AOLEU!", Color(0.9, 0.15, 0.1), 0.8]
	_kisses.shout(rating[0], rating[1], rating[2])

## A row of scroll buttons, each [label, value]; picking one calls on_pick(value).
## An empty list just clears the row.
func _show_choices(options: Array, on_pick: Callable) -> void:
	for old in _choices.get_children():
		old.queue_free()
	_choices.visible = not options.is_empty()
	if options.is_empty():
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for option: Array in options:
		var button = SCROLL_BUTTON.instantiate()
		button.text = option[0]
		button.pressed.connect(func() -> void:
			_choices.visible = false
			on_pick.call(option[1]))
		_choices.add_child(button)
	# Centred under her.
	_choices.position.x = 270.0 - (options.size() * 130.0 + (options.size() - 1) * 12.0) / 2.0

## A burst of n hearts floating up from where the penis is.
func _love(count: int) -> void:
	var burst := _hearts.duplicate() as CPUParticles2D
	burst.amount = maxi(count, 1)
	burst.one_shot = true
	burst.position = _rig.from_body(_rig.entrance(_rig.hole) + Vector2(0, -20))
	_rig.add_child(burst)
	burst.emitting = true
	burst.finished.connect(burst.queue_free)

## Left click on her butt: a slap. In her, it lands on the cheek on the
## mouse's side; out of her, wherever the tip is on her butt (on a hole the
## click is a push instead).
func _try_slap() -> void:
	if not Settings.slapping or _time - _slapped_at < slap_cooldown:
		return
	var at: Vector2
	var side: int
	if _rig.inserted:
		side = 0 if _rig.to_body(_rig.get_local_mouse_position()).x < 0.0 else 1
		at = _rig.cheek(side)
	else:
		at = _tip()
		if not _rig.on_butt(at) or _rig.near_hole(at):
			return
		side = 0 if at.x < 0.0 else 1
	_slapped_at = _time
	_rig.slap(side)
	_play(SLAP_HIT_SOUND, randf_range(0.92, 1.1), 0.0)
	_shake = maxf(_shake, 0.3)
	_porthole.jolt()
	_gasp()
	_slap_heat = minf(_slap_heat + 0.22, 1.0)
	_chat("slap_red" if _slap_heat > 0.6 else "slap", 10.0)
	_slap_sparks.global_position = _rig.to_global(_rig.from_body(at))
	for particles in _slap_view.get_node("Sparks").get_children():
		if particles is GPUParticles3D:
			particles.restart()
			particles.emitting = true

## A quick breathy burst in her voice.
func _gasp() -> void:
	for i in 3:
		get_tree().create_timer(i * 0.06).timeout.connect(func() -> void:
			_voice.pitch_scale = character.voice_pitch * (1.25 - i * 0.08)
			_voice.play())

## Chatter: said only if she isn't talking, it's been line_gap since her
## last line and cooldown since she last said this one. keep: if it can't
## be said now, it waits for the next gap (one line waits at a time).
## Returns whether she said it.
func _chat(event: String, cooldown: float = remark_cooldown, keep: bool = false) -> bool:
	# She talks less (the settings): twice the quiet between lines.
	var gap := line_gap * (2.0 if Settings.talk == 1 else 1.0)
	if _bubble.is_active() or _time - _last_line < gap or _time - _last_said.get(event, -100.0) < cooldown:
		if keep:
			_pending = event
		return false
	return _say(event)

## force: say it even if she's mid-line (the big moments).
## A girl with her own penis says her futa_ line for the event if she has one.
## Returns whether she said it.
func _say(event: String, force: bool = false) -> bool:
	if Settings.talk == 2:
		return false # silent (the settings): gasps only
	var text := girl.line("futa_" + event) if _rig.has_penis() else ""
	if text.is_empty():
		text = girl.line(event)
	if text.is_empty() or (not force and _bubble.is_active()):
		return false
	_last_said[event] = _time
	_last_line = _time
	_bubble.start(PackedStringArray([text]), character.voice_pitch, character.text_speed)
	return true

func _play(stream: AudioStream, pitch: float, volume_db: float) -> void:
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume_db
	player.bus = &"Body"
	player.finished.connect(player.queue_free)
	add_child(player)
	player.play()

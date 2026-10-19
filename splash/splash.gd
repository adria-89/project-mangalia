extends Node2D

## Studio splash: the Prenadez Studios logo drops in white and squashes, its
## white parts fill up with cola, beer and rum layered a third each, the guy
## hiccups, and the lights cut out, which takes us to the menu. Any key or
## click skips ahead to the lights going out.

const NEXT_SCENE := "res://menu/main_menu.tscn"
const HICCUP_BUBBLE: Script = preload("res://customer/hiccup_bubble.gd")
const HICCUP_SOUNDS: Array[AudioStream] = [
	preload("res://audio/hiccup1.wav"),
	preload("res://audio/hiccup2.wav"),
	preload("res://audio/hiccup3.wav"),
]

@export_group("Timing")
## Lights coming up at the start.
@export var lights_up_time: float = 0.3
## The logo falling in from above the screen.
@export var drop_time: float = 0.35
@export var before_pour: float = 0.3
## Each third of the drink: cola, beer, rum.
@export var layer_time: float = 0.7
@export var before_hiccup: float = 0.35
@export var after_hiccup: float = 1.0
## Black after the lights die, before the waves take us to the menu.
@export var dark_time: float = 0.4

@export_group("Pour")
@export var pour_volume_db: float = -4.0
## Pour sound pitch per stream (cola, beer, rum): the rum is a thinner stream.
@export var pour_pitches: PackedFloat32Array = [0.9, 1.0, 1.25]

@export_group("Squash")
@export var squash_stiffness: float = 260.0
@export var squash_damping: float = 9.0
## How stretched it falls, how hard it squashes on landing and on the hiccup.
@export var fall_stretch: float = 0.25
@export var land_squash: float = 5.0
@export var hiccup_stretch: float = 3.0
## Screen shake on landing (pixels, dies down over shake_time).
@export var land_shake_px: float = 5.0
@export var shake_time: float = 0.35

@export_group("Slosh")
@export var slosh_stiffness: float = 60.0
@export var slosh_damping: float = 3.0
## Kick to the surface when a stream starts and on the hiccup.
@export var pour_slosh: float = 0.4
@export var hiccup_slosh: float = 1.4
## How much it rocks with the ship (the drink stays level).
@export var sea_rock: float = 1.0

@export_group("")
## Where the guy's mouth is on the logo (0..1 across and down): the hiccup
## bubble comes out here.
@export var mouth := Vector2(0.27, 0.45)

@onready var _logo: Sprite2D = $Logo
@onready var _lights: ColorRect = $LightsOut
@onready var _jingle: AudioStreamPlayer = $Jingle
@onready var _pour: AudioStreamPlayer = $Pour
@onready var _thud: AudioStreamPlayer = $Thud
@onready var _hiccup: AudioStreamPlayer = $Hiccup

var _material: ShaderMaterial
var _rest := Vector2.ZERO
var _falling := false
var _squash := 0.0 # >0 stretched, <0 squashed
var _squash_velocity := 0.0
var _slosh := 0.0
var _slosh_velocity := 0.0
var _shake := 0.0
var _ending := false

func _ready() -> void:
	_material = _logo.material as ShaderMaterial
	# Pivot at the bottom middle, so it squashes down onto the "floor".
	var size := _logo.texture.get_size()
	_logo.centered = false
	_logo.offset = Vector2(-size.x / 2.0, -size.y)
	var screen := get_viewport_rect().size
	_rest = Vector2(screen.x / 2.0, (screen.y + size.y) / 2.0)
	_logo.position = _rest
	_logo.visible = false
	_set_levels(0.0, 0.0, 0.0)
	_lights.color.a = 1.0
	_run()

func _process(delta: float) -> void:
	if not _falling:
		_squash_velocity += (-_squash * squash_stiffness - _squash_velocity * squash_damping) * delta
		_squash = clampf(_squash + _squash_velocity * delta, -0.35, 0.35)
	# Keeps its volume: taller means thinner.
	var stretch := 1.0 + _squash
	_logo.scale = Vector2(1.0 / sqrt(stretch), stretch)
	_logo.rotation = Sea.roll * sea_rock
	_slosh_velocity += (-_slosh * slosh_stiffness - _slosh_velocity * slosh_damping) * delta
	_slosh += _slosh_velocity * delta
	# The surface stays level while the logo rocks: tilt it back against the
	# roll (in UV units, so scaled by the logo's width over its height).
	var size := _logo.texture.get_size()
	_material.set_shader_parameter("slosh", _slosh + tan(_logo.rotation) * size.x / size.y)
	_shake = maxf(_shake - delta / shake_time, 0.0)
	position = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * land_shake_px * _shake

func _unhandled_input(event: InputEvent) -> void:
	var pressed := event.is_pressed() and not event.is_echo()
	if pressed and (event is InputEventKey or event is InputEventMouseButton or event is InputEventJoypadButton):
		_lights_out(true)

func _run() -> void:
	_jingle.play()
	var tween := create_tween()
	tween.tween_property(_lights, "color:a", 0.0, lights_up_time)
	await tween.finished
	if _ending:
		return
	await _drop()
	if _ending:
		return
	await _wait(before_pour)
	if _ending:
		return
	await _pour_drink()
	if _ending:
		return
	await _wait(before_hiccup)
	if _ending:
		return
	_do_hiccup()
	await _wait(after_hiccup)
	_lights_out(false)

## Falls in from above, stretched by the speed, and squashes on landing.
func _drop() -> void:
	_logo.visible = true
	_falling = true
	_logo.position = _rest - Vector2(0.0, _rest.y + 40.0)
	var tween := create_tween().set_parallel()
	tween.tween_property(_logo, "position", _rest, drop_time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(self, "_squash", fall_stretch, drop_time)
	await tween.finished
	_falling = false
	_squash_velocity = -land_squash
	_shake = 1.0
	_thud.play()

## Cola, then beer floated on it, then rum on top: a third each, each
## stream knocking the surface a little as it starts.
func _pour_drink() -> void:
	_pour.volume_db = pour_volume_db
	_pour.play()
	var tween := create_tween()
	for layer in 3:
		tween.tween_callback(_start_stream.bind(layer))
		# The last one a bit past full, so the ripples never dip below the top.
		var to := (layer + 1) / 3.0 if layer < 2 else 1.03
		tween.tween_method(_set_layer.bind(layer), layer / 3.0, to, layer_time) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(_pour, "volume_db", -40.0, 0.25)
	await tween.finished
	_pour.stop()

func _start_stream(layer: int) -> void:
	_pour.pitch_scale = pour_pitches[layer]
	_slosh_velocity += pour_slosh * (1.0 if layer % 2 == 0 else -1.0)

## Pours layer (0 cola, 1 beer, 2 rum) up to level, the ones under it full.
func _set_layer(level: float, layer: int) -> void:
	var tops: Array[float] = [1.0 / 3.0, 2.0 / 3.0, level]
	for i in range(layer, 3):
		tops[i] = level
	_set_levels(tops[0], tops[1], tops[2])

func _do_hiccup() -> void:
	_hiccup.stream = HICCUP_SOUNDS.pick_random()
	_hiccup.play()
	_squash_velocity += hiccup_stretch
	_slosh_velocity += hiccup_slosh * (1.0 if randf() < 0.5 else -1.0)
	var bubble = HICCUP_BUBBLE.new()
	bubble.size = 0.35
	bubble.life = 1.1
	var size := _logo.texture.get_size()
	bubble.position = to_local(_logo.to_global(_logo.offset + mouth * size))
	add_child(bubble)
	move_child(bubble, _lights.get_index()) # under the lights-out black

## Closing time: the light flickers and dies (fast when skipped), a beat of
## black, then the waves take us to the menu.
func _lights_out(fast: bool) -> void:
	if _ending:
		return
	_ending = true
	create_tween().tween_property(_jingle, "volume_db", -40.0, 0.8 if fast else 1.2)
	create_tween().tween_property(_pour, "volume_db", -40.0, 0.2)
	var tween := create_tween()
	var from := 1.0 - _lights.color.a
	if not fast:
		for level: float in [0.35, 0.9, 0.2, 0.7]:
			tween.tween_method(_set_lights, from, level, 0.06)
			tween.tween_interval(0.08)
			from = level
	tween.tween_method(_set_lights, from, 0.0, 0.25 if fast else 0.45) \
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_interval(dark_time)
	await tween.finished
	Transition.change_scene(NEXT_SCENE)

## Room brightness: 1 = lit, 0 = lights out.
func _set_lights(level: float) -> void:
	_lights.color.a = 1.0 - level

func _set_levels(cola: float, beer: float, total: float) -> void:
	_material.set_shader_parameter("cola_level", cola)
	_material.set_shader_parameter("beer_level", beer)
	_material.set_shader_parameter("total_level", total)

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

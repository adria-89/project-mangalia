extends Node2D

## Main menu: a toon steam tug rocking among the waves (left), the title
## (top right) and the scroll buttons under it; Save Folder in the bottom left. Layers, back to front: sky,
## back waves, the tug (its own transparent 3D view), front waves.

const GAME_SCENE := "res://main.tscn"
const AFTER_HOURS_SCENE := "res://afterhours/afterhours.tscn"
const MUSIC: AudioStreamWAV = preload("res://audio/music/main_menu_loop.wav")
const BOING_SOUND: AudioStream = preload("res://audio/boing.wav")
const HOP_GRAVITY := 30.0 # 3D units/s²

## How much harder the tug rolls than the bar does (it's out on open water).
@export var roll_scale: float = 2.5
@export var pitch_degrees: float = 2.0
## Sea heave (pixels) to 3D units.
@export var heave_scale: float = 0.02
@export var music_volume_db: float = -8.0

@export_group("Click squash")
## Clicking the tug squashes it and it springs back like the customers do.
@export var squash_stiffness: float = 260.0
@export var squash_damping: float = 11.0
## How hard a click stretches it (and the landing squashes it), and how high
## it hops (3D units).
@export var click_squash: float = 4.0
@export var click_hop: float = 0.25
@export_group("")

@onready var _tug: Node3D = $ShipViewport/TugPivot
@onready var _tug_model: Node3D = $ShipViewport/TugPivot/Tugboat
@onready var _ship_viewport: SubViewport = $ShipViewport
@onready var _play: TextureButton = $Buttons/Play
@onready var _after_hours: TextureButton = $Buttons/AfterHours
@onready var _quit: TextureButton = $Buttons/Quit
@onready var _options: TextureButton = $Buttons/Options
@onready var _options_menu: CanvasLayer = $ScrollMenu
## Bottom left: opens the folder with the .prenadez saves.
@onready var _save_folder: TextureButton = $SaveFolder

var _time := 0.0
var _tug_base_y := 0.0
var _music: AudioStreamPlayer
var _boing: AudioStreamPlayer
var _tug_scale := Vector3.ONE
var _squash := 0.0 # >0 stretch, <0 squash
var _squash_velocity := 0.0
var _hop := 0.0
var _hop_velocity := 0.0

func _ready() -> void:
	Sea.strength = 1.0 # back from a stormy night: a normal sea for the tug
	_tug_scale = _tug_model.scale
	_boing = AudioStreamPlayer.new()
	_boing.stream = BOING_SOUND
	add_child(_boing)
	($SkyDisplay as Sprite2D).texture = ($SkyViewport as SubViewport).get_texture()
	($ShipDisplay as Sprite2D).texture = ($ShipViewport as SubViewport).get_texture()
	_tug_base_y = _tug.position.y
	_play.pressed.connect(_on_play_pressed)
	_options_menu.continue_pressed.connect(_on_continue)
	_options_menu.new_game_pressed.connect(_on_new_game)
	_save_folder.pressed.connect(SaveManager.open_folder)
	_after_hours.pressed.connect(_on_after_hours)
	_show_after_hours(Settings.nsfw)
	Settings.nsfw_changed.connect(_show_after_hours)
	_quit.pressed.connect(get_tree().quit)
	_options.pressed.connect(_options_menu.open_options)
	# Loop the whole file seamlessly (the import has looping off).
	var loop := MUSIC.duplicate() as AudioStreamWAV
	loop.loop_mode = AudioStreamWAV.LOOP_FORWARD
	loop.loop_begin = 0
	loop.loop_end = int(MUSIC.get_length() * MUSIC.mix_rate)
	_music = AudioStreamPlayer.new()
	_music.stream = loop
	_music.bus = &"Music"
	_music.volume_db = music_volume_db
	add_child(_music)
	_music.play()

func _process(delta: float) -> void:
	_time += delta
	# Roll with the shared sea, plus a slow pitch so it bobs bow to stern.
	_tug.rotation.x = Sea.roll * roll_scale
	_tug.rotation.z = deg_to_rad(pitch_degrees) * sin(_time * 0.9)
	_tug.position.y = _tug_base_y + Sea.heave * heave_scale + _hop
	_update_squash(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if _is_on_tug(event.position):
			_poke_tug()
			get_viewport().set_input_as_handled()

## The tug's view is transparent everywhere but the boat (and its smoke).
func _is_on_tug(screen: Vector2) -> bool:
	var display := $ShipDisplay as Sprite2D
	var pixel := Vector2i(display.to_local(screen))
	var image := _ship_viewport.get_texture().get_image()
	if not Rect2i(Vector2i.ZERO, image.get_size()).has_point(pixel):
		return false
	return image.get_pixelv(pixel).a > 0.5

## Like poking a customer: it stretches up into a little hop, squashes when
## it lands back on the water, and wobbles back.
func _poke_tug() -> void:
	_squash_velocity += click_squash
	_hop_velocity = maxf(_hop_velocity, sqrt(2.0 * HOP_GRAVITY * click_hop))
	_boing.pitch_scale = randf_range(0.9, 1.1)
	_boing.play()

func _update_squash(delta: float) -> void:
	_squash_velocity += (-_squash * squash_stiffness - _squash_velocity * squash_damping) * delta
	_squash = clampf(_squash + _squash_velocity * delta, -0.3, 0.3)
	# Keeps its volume: taller means thinner.
	var stretch := 1.0 + _squash
	_tug_model.scale = _tug_scale * Vector3(1.0 / sqrt(stretch), stretch, 1.0 / sqrt(stretch))
	# The hop: up, then back down under gravity onto the water.
	if _hop > 0.0 or _hop_velocity > 0.0:
		_hop_velocity -= HOP_GRAVITY * delta
		_hop += _hop_velocity * delta
		if _hop <= 0.0:
			_hop = 0.0
			_hop_velocity = 0.0
			_squash_velocity -= click_squash # splash back down

## No save yet: straight into a new game. Otherwise the scroll asks:
## Continue or New Game.
func _on_play_pressed() -> void:
	if SaveManager.has_save():
		_options_menu.open_start()
	else:
		_on_new_game()

func _on_continue() -> void:
	if SaveManager.load_game():
		_on_play(GAME_SCENE)

func _on_new_game() -> void:
	SaveManager.new_game()
	_on_play(GAME_SCENE)

func _on_play(scene: String) -> void:
	# Fade the music out under the transition instead of cutting it.
	create_tween().tween_property(_music, "volume_db", -40.0, 0.8)
	# A beat so the press clack and squash read before the scene changes.
	await get_tree().create_timer(0.15).timeout
	Transition.change_scene(scene)

## After Hours only shows with NSFW content on. Hidden, the buttons under it
## move up into its place (each into the slot of the one above, as laid out
## in the scene), so there's no gap.
func _show_after_hours(on: bool) -> void:
	if not _after_hours.has_meta("slot"):
		for button: Control in [_after_hours, _options, _quit]:
			button.set_meta("slot", button.position)
	_after_hours.visible = on
	_options.position = _options.get_meta("slot") if on else _after_hours.get_meta("slot")
	_quit.position = _quit.get_meta("slot") if on else _options.get_meta("slot")

## Straight to after hours: she's picked there, and leaving comes back here.
func _on_after_hours() -> void:
	AfterHoursScene.return_scene = scene_file_path
	_on_play(AFTER_HOURS_SCENE)

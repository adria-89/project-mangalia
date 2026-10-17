extends CanvasLayer

## Pause / options menu in "picture mode". Esc freezes the game and a gilded
## frame closes in from past the screen edges while the picture inside turns
## to three tones of sepia; then the framed picture squishes down onto a black
## background with a slight random tilt, and the paper scroll spins in on top
## (spinning-newspaper style). Esc or Resume plays it all backwards.
## The main menu opens it straight on the options page, without pausing.

const MAIN_MENU_SCENE := "res://menu/main_menu.tscn"
const SPIN_SOUND: AudioStream = preload("res://audio/boing.wav")
const SPIN_SOUND_REVERSED: AudioStream = preload("res://audio/boing_reversed.wav")
const TICK_SOUND: AudioStream = preload("res://audio/dialogue_tick.wav")

## Esc opens the pause menu (off in the main menu, which has a button instead).
@export var pausable: bool = true
@export var page_fade_time: float = 0.12

@export_group("Frame")
## The frame starts this big (edges off screen) and closes in to fit the screen.
@export var frame_start_scale: float = 1.5
@export var frame_time: float = 0.3
## The framed picture then shrinks to this and tilts by a random angle
## (either way) in this range, in degrees.
@export var picture_scale: float = 0.86
@export var tilt_degrees: Vector2 = Vector2(2.5, 5.0)
@export var squish_time: float = 0.35
@export_group("Scroll")
## Final size of the scroll, small enough to leave the frame showing around it.
@export var scroll_scale: float = 0.78
@export var spin_time: float = 0.5
## Full turns the scroll makes on the way in (and out).
@export var spins: float = 2.0
## Scale it starts from / shrinks back to.
@export var start_scale: float = 0.02
@export_group("")

@onready var _backdrop: ColorRect = $Backdrop
@onready var _picture: Control = $Picture
@onready var _snapshot: TextureRect = $Picture/Snapshot
@onready var _frame: Control = $Picture/Frame
@onready var _scroll: Control = $Scroll
@onready var _paper: Control = $Scroll/Paper
@onready var _title: Label = $Scroll/Title
@onready var _pause_page: Control = $Scroll/PausePage
@onready var _options_page: Control = $Scroll/OptionsPage
@onready var _window_scale: Node = $Scroll/OptionsPage/WindowScale/Choice

var _open := false
var _busy := false
## Opened with Esc in-game (Back returns to the pause page and closing unpauses).
var _from_pause := false
var _sound: AudioStreamPlayer

func _ready() -> void:
	_sound = AudioStreamPlayer.new()
	add_child(_sound)
	visible = false
	$Scroll/PausePage/Resume.pressed.connect(close)
	$Scroll/PausePage/Options.pressed.connect(_show_page.bind(_options_page))
	$Scroll/PausePage/MainMenu.pressed.connect(_on_main_menu)
	$Scroll/PausePage/Quit.pressed.connect(get_tree().quit)
	$Scroll/OptionsPage/Back.pressed.connect(_on_back)
	_init_options()

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _open:
		if _options_page.visible:
			_on_back()
		else:
			close()
		get_viewport().set_input_as_handled()
	elif pausable:
		open_pause()
		get_viewport().set_input_as_handled()

## Freeze the game and spin in on the pause page. Does nothing if something
## else (lights out, the night card, a transition) already has it paused.
func open_pause() -> void:
	if _open or _busy or get_tree().paused or Transition.is_covered():
		return
	get_tree().paused = true
	_from_pause = true
	_set_page(_pause_page)
	_spin(true)

## Spin in on the options page (main menu), the game keeps running behind.
func open_options() -> void:
	if _open or _busy:
		return
	_from_pause = false
	_set_page(_options_page)
	_spin(true)

func close() -> void:
	if not _open or _busy:
		return
	Settings.save()
	await _spin(false)
	if _from_pause:
		get_tree().paused = false

## In-game pause is "picture mode" (the frozen sepia picture in the frame,
## menu straight on top of it); the main menu just spins the paper scroll in
## over the live menu.
func _spin(opening: bool) -> void:
	_busy = true
	var framed := _from_pause
	if opening:
		# Black in picture mode, see-through otherwise (it still blocks clicks).
		_backdrop.color.a = 1.0 if framed else 0.0
		_picture.visible = framed
		_paper.visible = not framed
		_scroll.scale = Vector2.ONE * start_scale
		_scroll.rotation = -TAU * spins
		if framed:
			# The game as it was last drawn becomes the picture in the frame.
			_snapshot.texture = ImageTexture.create_from_image(get_viewport().get_texture().get_image())
			_set_reveal(0.0)
			_frame.scale = Vector2.ONE * frame_start_scale
			_picture.scale = Vector2.ONE
			_picture.rotation = 0.0
			# Copying the screen can hitch a frame; let that pass before animating.
			await get_tree().process_frame
	visible = true
	var tween := create_tween().set_parallel()
	if opening:
		# The options spin in while the frame closes in and the sepia spreads...
		_play(SPIN_SOUND, randf_range(0.55, 0.65))
		tween.tween_property(_scroll, "scale", Vector2.ONE * (scroll_scale if framed else 1.0), spin_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(_scroll, "rotation", 0.0, spin_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if framed:
			tween.tween_property(_frame, "scale", Vector2.ONE, frame_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.tween_method(_set_reveal, 0.0, 1.0, frame_time)
			# ...and once the frame lands, the picture squishes down and tilts.
			tween.tween_property(_picture, "scale", Vector2.ONE * picture_scale, squish_time) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(frame_time)
			var tilt: float = deg_to_rad(randf_range(tilt_degrees.x, tilt_degrees.y)) * [-1.0, 1.0].pick_random()
			tween.tween_property(_picture, "rotation", tilt, squish_time) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(frame_time)
	else:
		# The same backwards: the options spin out while the picture straightens
		# up, then the frame opens out past the edges and the color comes back.
		_play(SPIN_SOUND_REVERSED, randf_range(0.8, 0.9))
		tween.tween_property(_scroll, "scale", Vector2.ONE * start_scale, spin_time) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_property(_scroll, "rotation", TAU * spins, spin_time) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		if framed:
			tween.tween_property(_picture, "scale", Vector2.ONE, squish_time) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tween.tween_property(_picture, "rotation", 0.0, squish_time) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			tween.tween_property(_frame, "scale", Vector2.ONE * frame_start_scale, frame_time) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT).set_delay(squish_time)
			tween.tween_method(_set_reveal, 1.0, 0.0, frame_time).set_delay(squish_time)
	await tween.finished
	_open = opening
	visible = opening
	_busy = false

func _set_reveal(value: float) -> void:
	(_snapshot.material as ShaderMaterial).set_shader_parameter("reveal", value)

## Swap pages with a quick ink fade (the scroll stays put).
func _show_page(page: Control) -> void:
	if _busy:
		return
	_busy = true
	var current := _options_page if _options_page.visible else _pause_page
	var tween := create_tween()
	tween.tween_property(current, "modulate:a", 0.0, page_fade_time)
	tween.tween_callback(_set_page.bind(page))
	tween.tween_property(page, "modulate:a", 1.0, page_fade_time).from(0.0)
	await tween.finished
	_busy = false

func _set_page(page: Control) -> void:
	_pause_page.visible = page == _pause_page
	_options_page.visible = page == _options_page
	page.modulate.a = 1.0
	_title.text = "Options" if page == _options_page else "Paused"

func _on_back() -> void:
	Settings.save()
	if _from_pause:
		_show_page(_pause_page)
	else:
		close()

## Straight to the title, no transition.
func _on_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE)

func _init_options() -> void:
	var rows := {
		&"Master": $Scroll/OptionsPage/Master/Slider,
		&"Music": $Scroll/OptionsPage/Music/Slider,
		&"SFX": $Scroll/OptionsPage/SFX/Slider,
	}
	for bus: StringName in rows:
		var slider: Range = rows[bus]
		slider.value = Settings.volumes[bus]
		slider.value_changed.connect(func(value: float) -> void: Settings.set_volume(bus, value))
	# A tick on the SFX bus so the SFX slider can be heard while dragging.
	rows[&"SFX"].value_changed.connect(func(_value: float) -> void: _play(TICK_SOUND, 1.2))

	var physics: Node = $Scroll/OptionsPage/Physics/Choice
	physics.index = Settings.physics
	physics.changed.connect(func(index: int) -> void:
		Settings.physics = index
		_play(TICK_SOUND, 1.2))

	var text_speed: Node = $Scroll/OptionsPage/TextSpeed/Choice
	text_speed.index = Settings.text_speed
	text_speed.changed.connect(func(index: int) -> void:
		Settings.text_speed = index
		_play(TICK_SOUND, 1.2))

	var fullscreen: Node = $Scroll/OptionsPage/Fullscreen/Choice
	fullscreen.index = 1 if Settings.fullscreen else 0
	fullscreen.changed.connect(func(index: int) -> void:
		Settings.set_fullscreen(index == 1)
		_window_scale.set_disabled(Settings.fullscreen)
		_play(TICK_SOUND, 1.2))

	var scales := PackedStringArray()
	for i in Settings.max_window_scale():
		scales.append("%dx" % (i + 1))
	_window_scale.set_options(scales, Settings.window_scale - 1)
	_window_scale.set_disabled(Settings.fullscreen)
	_window_scale.changed.connect(func(index: int) -> void:
		Settings.set_window_scale(index + 1)
		_play(TICK_SOUND, 1.2))

func _play(stream: AudioStream, pitch: float) -> void:
	_sound.stream = stream
	_sound.pitch_scale = pitch
	_sound.play()

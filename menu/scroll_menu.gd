extends CanvasLayer

## Pause / options menu in "picture mode". Esc freezes the game and a gilded
## frame closes in from past the screen edges while the picture inside turns
## to three tones of sepia; then the framed picture squishes down onto a black
## background with a slight random tilt, and the paper scroll spins in on top
## (spinning-newspaper style). Esc or Resume plays it all backwards.
## With NSFW content on, the options page has an NSFW button: After Hours'
## own settings on three pages (content, play, sound). Esc or Back steps
## back a page at a time.
## The main menu opens it straight on the options page, without pausing, or
## on the start page (Continue / New Game) when Play is pressed with a save.

## Start page buttons (the main menu acts on them).
signal continue_pressed
signal new_game_pressed

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
@onready var _nsfw_button: Control = $Scroll/OptionsPage/Buttons/NSFW
@onready var _nsfw_page: Control = $Scroll/NsfwPage
@onready var _content_page: Control = $Scroll/ContentPage
@onready var _play_page: Control = $Scroll/PlayPage
@onready var _sound_page: Control = $Scroll/SoundPage
## Main menu, with a save on disk: Continue / New Game (see open_start()).
@onready var _start_page: Control = $Scroll/StartPage
## Every page, its title, and the page Back (or Esc) goes to (null: the
## options page's own back, see _on_back()).
@onready var _pages := {
	_pause_page: ["Paused", null],
	_options_page: ["Options", null],
	_nsfw_page: ["NSFW", _options_page],
	_content_page: ["Content", _nsfw_page],
	_play_page: ["Play", _nsfw_page],
	_sound_page: ["Sound", _nsfw_page],
	_start_page: ["Play", null],
}
## Plays when NSFW content is switched on.
@onready var _jingle: AudioStreamPlayer = $Jingle
## Switching NSFW on also floods the screen red (Mechsodus's pause screen,
## shaders/red_flash.gdshader) and fades it out over this long.
@export var red_flash_time: float = 1.4
@onready var _red_flash: CanvasLayer = $RedFlash
@onready var _red_flash_rect: ColorRect = $RedFlash/Flash
var _red_flash_tween: Tween

var _open := false
var _busy := false
## Opened with Esc in-game (Back returns to the pause page and closing unpauses).
var _from_pause := false
var _sound: AudioStreamPlayer
## The menu always has the cursor. What the game wanted (After Hours hides
## it: the penis is the cursor) is kept here and put back when it closes.
var _cursor_on := false
var _game_mouse := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	_sound = AudioStreamPlayer.new()
	add_child(_sound)
	visible = false
	$Scroll/PausePage/Resume.pressed.connect(close)
	$Scroll/PausePage/Options.pressed.connect(_show_page.bind(_options_page))
	$Scroll/PausePage/MainMenu.pressed.connect(_on_main_menu)
	$Scroll/PausePage/Quit.pressed.connect(get_tree().quit)
	$Scroll/OptionsPage/Buttons/Back.pressed.connect(_on_back)
	_nsfw_button.pressed.connect(_show_page.bind(_nsfw_page))
	$Scroll/NsfwPage/Content.pressed.connect(_show_page.bind(_content_page))
	$Scroll/NsfwPage/Play.pressed.connect(_show_page.bind(_play_page))
	$Scroll/NsfwPage/Sound.pressed.connect(_show_page.bind(_sound_page))
	$Scroll/StartPage/Continue.pressed.connect(continue_pressed.emit)
	$Scroll/StartPage/NewGame.pressed.connect(new_game_pressed.emit)
	$Scroll/StartPage/Back.pressed.connect(close)
	for page: Control in [_nsfw_page, _content_page, _play_page, _sound_page]:
		page.get_node("Back").pressed.connect(_show_page.bind(_pages[page][1]))
	_init_options()

## While it's open, the game may still try to hide the cursor (timers run
## through a pause): it stays, and that's what goes back on close.
func _process(_delta: float) -> void:
	if _cursor_on and Input.mouse_mode != Input.MOUSE_MODE_VISIBLE:
		_game_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _open:
		var back: Control = _pages[_current_page()][1]
		if back:
			_show_page(back)
		elif _options_page.visible:
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

## Spin in on the start page (main menu, when there's a save to continue).
func open_start() -> void:
	if _open or _busy:
		return
	_from_pause = false
	_set_page(_start_page)
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
	_cursor_on = false
	Input.mouse_mode = _game_mouse
	if _from_pause:
		get_tree().paused = false

## In-game pause is "picture mode" (the frozen sepia picture in the frame,
## menu straight on top of it); the main menu just spins the paper scroll in
## over the live menu.
func _spin(opening: bool) -> void:
	_busy = true
	if opening and not _cursor_on:
		_cursor_on = true
		_game_mouse = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
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
	var current := _current_page()
	var tween := create_tween()
	tween.tween_property(current, "modulate:a", 0.0, page_fade_time)
	tween.tween_callback(_set_page.bind(page))
	tween.tween_property(page, "modulate:a", 1.0, page_fade_time).from(0.0)
	await tween.finished
	_busy = false

func _set_page(page: Control) -> void:
	for each: Control in _pages:
		each.visible = each == page
	page.modulate.a = 1.0
	_title.text = _pages[page][0]

func _current_page() -> Control:
	for page: Control in _pages:
		if page.visible:
			return page
	return _pause_page

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

	var nsfw: Node = $Scroll/OptionsPage/NSFW/Choice
	nsfw.index = 1 if Settings.nsfw else 0
	nsfw.changed.connect(func(index: int) -> void:
		Settings.set_nsfw(index == 1)
		_nsfw_button.visible = Settings.nsfw
		if Settings.nsfw:
			_jingle.play()
			_flash_red()
		else:
			_jingle.stop()
			_play(TICK_SOUND, 1.2))

	_nsfw_button.visible = Settings.nsfw
	_init_nsfw()

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

## The NSFW pages: each row's choice is the setting's index (Off/On rows: 0/1).
func _init_nsfw() -> void:
	var choices := {
		"ContentPage/Futa": "futa", "ContentPage/Anal": "anal", "ContentPage/Bulge": "bulge",
		"ContentPage/Forced": "forced", "ContentPage/Cum": "cum", "ContentPage/Sweat": "sweat",
		"ContentPage/Marks": "marks",
		"PlayPage/Talk": "talk", "PlayPage/Difficulty": "difficulty", "PlayPage/Slapping": "slapping",
		"PlayPage/Endless": "endless", "PlayPage/Shake": "shake",
	}
	for row: String in choices:
		var key: String = choices[row]
		var choice: Node = get_node("Scroll/%s/Choice" % row)
		var on_off: bool = Settings.get(key) is bool
		choice.index = int(Settings.get(key))
		choice.changed.connect(func(index: int) -> void:
			Settings.set(key, index == 1 if on_off else index)
			_play(TICK_SOUND, 1.2))
	for bus: StringName in [&"Violin", &"Body", &"Voice", &"CabinMusic"]:
		var slider: Range = get_node("Scroll/SoundPage/%s/Slider" % bus)
		slider.value = Settings.volumes[bus]
		slider.value_changed.connect(func(value: float) -> void: Settings.set_volume(bus, value))

## The screen goes red in an instant, then fades back.
func _flash_red() -> void:
	if _red_flash_tween:
		_red_flash_tween.kill()
	_red_flash.visible = true
	_red_flash_rect.modulate.a = 1.0
	_red_flash_tween = create_tween()
	_red_flash_tween.tween_property(_red_flash_rect, "modulate:a", 0.0, red_flash_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_red_flash_tween.tween_callback(func() -> void: _red_flash.visible = false)

func _play(stream: AudioStream, pitch: float) -> void:
	_sound.stream = stream
	_sound.pitch_scale = pitch
	_sound.play()

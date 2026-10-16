extends Node2D

## Speech bubble with Undertale-style typewriter text: every revealed
## character plays a tick in the speaker's voice. advance() finishes the
## current line or moves on to the next one; lines also move on by themselves
## after a reading pause (longer for longer lines and slower talkers).

signal line_started(index: int)
signal finished
## The last line finished typing (with hold_last it then stays on screen).
signal last_line_shown

const TICK_SOUND: AudioStream = preload("res://audio/dialogue_tick.wav")

@export var chars_per_second: float = 30.0
@export var punctuation_pause: float = 0.18
@export var tick_pitch_variance: float = 0.08

@export_group("Auto advance")
@export var auto_advance: bool = true
## Seconds a finished line stays up before the next one, plus a bit per character.
@export var read_pause: float = 1.2
@export var read_pause_per_char: float = 0.035

@onready var _label: Label = $Bubble/Label
@onready var _bubble: Node2D = $Bubble
@onready var _tick: AudioStreamPlayer = $Tick

var _lines: PackedStringArray = []
var _index := -1
var _typing := false
var _char_timer := 0.0
var _voice_pitch := 1.0
var _text_speed := 1.0
var _hold_last := false
## Counts down after a line is fully shown; at zero the next line starts.
var _read_timer := 0.0
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_tick.stream = TICK_SOUND
	visible = false

## hold_last: keep the last line up (e.g. an order) until stop() is called.
func start(lines: PackedStringArray, voice_pitch: float = 1.0, text_speed: float = 1.0, hold_last: bool = false) -> void:
	_lines = lines
	_hold_last = hold_last
	_voice_pitch = voice_pitch
	_text_speed = text_speed
	_index = -1
	visible = true
	_next_line()

func stop() -> void:
	_index = -1
	_typing = false
	visible = false

func is_active() -> bool:
	return _index != -1

## Click / Space: finish the line instantly, or go to the next one.
func advance() -> void:
	if not is_active():
		return
	if _typing:
		_label.visible_characters = -1
		_finish_typing()
	elif _hold_last and _index == _lines.size() - 1:
		return # stays up until stop()
	else:
		_next_line()

func _finish_typing() -> void:
	_typing = false
	# Slow talkers get read more slowly too.
	_read_timer = (read_pause + read_pause_per_char * _label.text.length()) / maxf(_text_speed, 0.1)
	if _index == _lines.size() - 1:
		last_line_shown.emit()

func _next_line() -> void:
	_index += 1
	if _index >= _lines.size():
		stop()
		finished.emit()
		return
	_label.text = _lines[_index]
	_label.visible_characters = 0
	_typing = true
	_char_timer = 0.0
	_pop()
	line_started.emit(_index)

func _pop() -> void:
	_bubble.scale = Vector2(0.7, 0.7)
	var tween := create_tween()
	tween.tween_property(_bubble, "scale", Vector2.ONE, 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	if not _typing:
		_update_auto_advance(delta)
		return
	_char_timer -= delta
	while _typing and _char_timer <= 0.0:
		_reveal_next_char()

func _reveal_next_char() -> void:
	var text := _label.text
	var shown := _label.visible_characters
	if shown >= text.length():
		_finish_typing()
		return
	var c := text[shown]
	_label.visible_characters = shown + 1
	_char_timer += 1.0 / (chars_per_second * _text_speed)
	if c in ".!?,":
		_char_timer += punctuation_pause / _text_speed
	if c != " ":
		_play_tick()
	if _label.visible_characters >= text.length():
		_finish_typing()

func _update_auto_advance(delta: float) -> void:
	if not auto_advance or not is_active():
		return
	if _hold_last and _index == _lines.size() - 1:
		return # the held line (e.g. an order) stays until stop()
	_read_timer -= delta
	if _read_timer <= 0.0:
		_next_line()

func _play_tick() -> void:
	_tick.pitch_scale = _voice_pitch * (1.0 + _rng.randf_range(-tick_pitch_variance, tick_pitch_variance))
	_tick.play()

extends CanvasLayer

## FNAF-style card between days: fade to black, "Night 0", then the night's
## receipt typed out like a bill (today's drink ratings, earned, drinks
## refill, ship fuel, what's left, with typewriter clacks and a bell). If the
## bill is paid, the number slowly rolls to the next night and the bar comes back;
## if not, it's GAME OVER and a click starts over.
## Runs while the game is paused.

## The screen is fully black (e.g. reset the bar now).
signal blacked_out
## Game over was acknowledged with a click.
signal restart_requested

const PUNCH_SOUND: AudioStream = preload("res://audio/typewriter_punch.wav")
const BELL_SOUND: AudioStream = preload("res://audio/typewriter_bell.wav")

@export var fade_time: float = 0.6
## How dark the strip behind the text is, over the waves (1 = solid black).
@export var backdrop_alpha: float = 0.55
@export var hold_before: float = 0.8
@export var roll_time: float = 1.4
## Pause between receipt lines.
@export var line_delay: float = 0.3
## Seconds per typed character on the receipt.
@export var type_delay: float = 0.04
@export var hold_after: float = 1.2

@onready var _black: ColorRect = $Black
@onready var _content: Control = $Black/Content
@onready var _old: Label = $Black/Content/Digits/Old
@onready var _new: Label = $Black/Content/Digits/New
@onready var _digits: Control = $Black/Content/Digits
@onready var _stats: Label = $Black/Content/Receipt/Stats
@onready var _earned: Label = $Black/Content/Receipt/Earned
@onready var _drinks: Label = $Black/Content/Receipt/Drinks
@onready var _fuel: Label = $Black/Content/Receipt/Fuel
@onready var _broken: Label = $Black/Content/Receipt/Broken
@onready var _total: Label = $Black/Content/Receipt/Total
@onready var _game_over: Control = $Black/GameOver

var _waiting_for_click := false
var _punch: AudioStreamPlayer
var _bell: AudioStreamPlayer

func _ready() -> void:
	_black.visible = false
	_punch = AudioStreamPlayer.new()
	_punch.stream = PUNCH_SOUND
	_punch.max_polyphony = 3
	add_child(_punch)
	_bell = AudioStreamPlayer.new()
	_bell.stream = BELL_SOUND
	add_child(_bell)

## Plays the card for the night that just ended. If money_left is negative the
## bill couldn't be paid: shows GAME OVER and waits for a click (then emits
## restart_requested). Otherwise rolls to the next night and fades back. Await it.
## broken / broken_cost: tankards smashed tonight and what they cost (the line
## only shows if something broke).
func play(from_night: int, stats: String, earned: int, drinks_cost: int, fuel_cost: int,
		broken: int, broken_cost: int, money_left: int) -> void:
	_old.text = str(from_night)
	_new.text = str(from_night + 1)
	var height := _digits.size.y
	_old.position.y = 0.0
	_new.position.y = -height
	var lines := {
		_stats: stats,
		_earned: "+%d lei earned" % earned,
		_drinks: "-%d drinks refill" % drinks_cost,
		_fuel: "-%d ship fuel" % fuel_cost,
		_broken: "-%d broken tankard%s" % [broken_cost, "" if broken == 1 else "s"],
		_total: "= %d lei" % money_left,
	}
	_broken.visible = broken > 0
	for label: Label in lines:
		label.text = lines[label]
		label.visible_characters = 0
	_total.label_settings = _total.label_settings.duplicate()
	_total.label_settings.font_color = Color(1, 0.85, 0.35) if money_left >= 0 else Color(0.9, 0.15, 0.1)
	_game_over.visible = false
	_content.modulate.a = 0.0

	# The sea rises over the bar, then the card fades in on a dark strip over the waves.
	await Transition.cover()
	_black.color.a = 0.0
	_black.visible = true
	blacked_out.emit()
	var tween := create_tween().set_parallel()
	tween.tween_property(_black, "color:a", backdrop_alpha, fade_time)
	tween.tween_property(_content, "modulate:a", 1.0, fade_time)
	await tween.finished
	await _wait(hold_before)

	# The receipt types itself out line by line; the bell rings on the total.
	for label: Label in [_stats, _earned, _drinks, _fuel, _broken, _total]:
		if not label.visible:
			continue
		await _type(label)
		await _wait(line_delay)
	_bell.play()
	await _wait(0.5)

	if money_left < 0:
		_game_over.visible = true
		_waiting_for_click = true
		await restart_requested
		return

	# Paid: the old number slides down and out while the next comes in from above.
	tween = create_tween().set_parallel()
	tween.tween_property(_old, "position:y", height, roll_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(_new, "position:y", 0.0, roll_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished
	await _wait(hold_after)

	tween = create_tween().set_parallel()
	tween.tween_property(_content, "modulate:a", 0.0, 0.3)
	tween.tween_property(_black, "color:a", 0.0, 0.3)
	await tween.finished
	_black.visible = false
	await Transition.uncover()

## Reveal a label one character at a time with a typewriter clack per key.
func _type(label: Label) -> void:
	var text := label.text
	for i in text.length():
		label.visible_characters = i + 1
		if text[i] != " ":
			_punch.pitch_scale = randf_range(0.9, 1.1)
			_punch.play()
		await _wait(type_delay)
	label.visible_characters = -1

func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func _input(event: InputEvent) -> void:
	if not _waiting_for_click:
		return
	var clicked: bool = (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventKey and event.pressed and not event.echo)
	if clicked:
		_waiting_for_click = false
		get_viewport().set_input_as_handled()
		restart_requested.emit()

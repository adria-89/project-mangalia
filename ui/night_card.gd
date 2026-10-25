extends CanvasLayer

## FNAF-style card between days: fade to black, "Night 0", then the night's
## receipt typed out like a bill (today's drink ratings, earned, drinks
## refill, ship fuel, what's left, with typewriter clacks and a bell). If the
## bill is paid, the number slowly rolls to the next night and the bar comes back;
## if not, it's GAME OVER and a click goes back to the morning's save.
## Runs while the game is paused.

## Under the receipt, a row per girl met so far: her head and her affection
## bar in her color, which fills from where it was this morning to now (only
## if the bill is paid). Affection/Row is the template, copied per girl.

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
## Seconds each affection bar takes to fill to today's value.
@export var affection_fill_time: float = 0.7

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
@onready var _affection: VBoxContainer = $Black/Content/Affection
@onready var _row_template: HBoxContainer = $Black/Content/Affection/Row

var _waiting_for_click := false
var _punch: AudioStreamPlayer
var _bell: AudioStreamPlayer

func _ready() -> void:
	_black.visible = false
	_row_template.visible = false
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
## only shows if something broke). affection: a row per girl, each
## {head: Texture2D, color: Color, from: float, to: float} (bar 0..1).
func play(from_night: int, stats: String, earned: int, drinks_cost: int, fuel_cost: int,
		broken: int, broken_cost: int, money_left: int, affection: Array[Dictionary] = []) -> void:
	var rows := _make_rows(affection)
	_affection.visible = money_left >= 0 and not rows.is_empty()
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

	# Paid: the girls' bars fill one by one.
	for i in rows.size():
		await _fill(rows[i], affection[i].to)
		await _wait(line_delay)

	# The old number slides down and out while the next comes in from above.
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

## Fresh rows from the template (last night's are thrown away), each showing
## her bar where it was this morning.
func _make_rows(affection: Array[Dictionary]) -> Array[HBoxContainer]:
	for child in _affection.get_children():
		if child != _row_template:
			child.queue_free()
	var rows: Array[HBoxContainer] = []
	for girl in affection:
		var row := _row_template.duplicate() as HBoxContainer
		row.visible = true
		(row.get_node("Head") as TextureRect).texture = girl.head
		(row.get_node("Bar/Fill") as ColorRect).color = girl.color
		_set_bar(girl.from, row)
		_affection.add_child(row)
		rows.append(row)
	return rows

## Her bar grows (or shrinks) to today's value with a rising clack; a heart
## shows once it's full.
func _fill(row: HBoxContainer, to: float) -> void:
	var fill := row.get_node("Bar/Fill") as ColorRect
	var from := fill.anchor_right
	if not is_equal_approx(from, to):
		_punch.pitch_scale = 1.2 if to > from else 0.8
		_punch.play()
		var tween := create_tween()
		tween.tween_method(_set_bar.bind(row), from, to, affection_fill_time) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		await tween.finished
	if to >= 1.0 and from < 1.0:
		_bell.play() # just filled up

## Bar fill 0..1 (the Fill's right anchor), and the heart if it's full.
func _set_bar(amount: float, row: HBoxContainer) -> void:
	(row.get_node("Bar/Fill") as ColorRect).anchor_right = clampf(amount, 0.0, 1.0)
	# Faded, not hidden, so the row doesn't shift when it shows.
	(row.get_node("Heart") as CanvasItem).modulate.a = 1.0 if amount >= 1.0 else 0.0

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

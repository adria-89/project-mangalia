extends Control

## Day clock in the corner, "HH:MM". Each character sits in its own clipped
## slot; when a digit changes, the old one slides down and out while the new
## one comes in from above, like the night card's number.

@export var start_hour: int = 12
@export var end_hour: int = 20
## The clock jumps in steps of this many minutes, like a cheap wall clock.
@export var step_minutes: int = 10
@export var roll_time: float = 0.35
@export var label_settings: LabelSettings

const DIGIT_WIDTH := 10.0
const COLON_WIDTH := 6.0
const HEIGHT := 20.0

var _slots: Array[Control] = []
var _text := ""

func _ready() -> void:
	_set_text("%02d:00" % start_hour, true)

## Show the time for a 0..1 progress through the day.
func show_progress(progress: float, instant: bool = false) -> void:
	var total := (end_hour - start_hour) * 60
	var minutes := int(clampf(progress, 0.0, 1.0) * total) / step_minutes * step_minutes
	var hour := start_hour + minutes / 60
	_set_text("%02d:%02d" % [hour, minutes % 60], instant)

func _set_text(text: String, instant: bool) -> void:
	if _slots.is_empty():
		_build_slots(text)
	for i in text.length():
		if i >= _text.length() or text[i] != _text[i]:
			_roll(i, text[i], instant)
	_text = text

func _build_slots(text: String) -> void:
	var x := 0.0
	for i in text.length():
		var slot := Control.new()
		slot.clip_contents = true
		slot.position = Vector2(x, 0.0)
		slot.size = Vector2(COLON_WIDTH if text[i] == ":" else DIGIT_WIDTH, HEIGHT)
		add_child(slot)
		_slots.append(slot)
		x += slot.size.x

func _roll(index: int, character: String, instant: bool) -> void:
	var slot := _slots[index]
	var incoming := _make_label(character, slot.size.x)
	slot.add_child(incoming)
	# Everything already in the slot (the old digit, or one still rolling) leaves downward.
	var outgoing: Array[Node] = slot.get_children().slice(0, -1)
	if instant:
		for old in outgoing:
			old.queue_free()
		return
	incoming.position.y = -HEIGHT
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_property(incoming, "position:y", 0.0, roll_time)
	for old: Label in outgoing:
		tween.tween_property(old, "position:y", HEIGHT, roll_time)
	tween.chain().tween_callback(func() -> void:
		for old in outgoing:
			if is_instance_valid(old):
				old.queue_free())

func _make_label(character: String, width: float) -> Label:
	var label := Label.new()
	label.text = character
	label.label_settings = label_settings
	label.size = Vector2(width, HEIGHT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

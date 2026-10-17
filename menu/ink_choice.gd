extends HBoxContainer

## Pick-one setting drawn as "< Normal >": the arrows step through the
## options (wrapping around) and the label shows the current one.

signal changed(index: int)

const FONT: FontFile = preload("res://assets/ui/alagard.ttf")
const INK := Color(0.25, 0.14, 0.07)
const INK_HOVER := Color(0.55, 0.3, 0.12)
## Pale outline so the text reads on top of the picture.
const OUTLINE := Color(0.85, 0.71, 0.65)

@export var options: PackedStringArray = ["Off", "On"]

var index := 0:
	set(value):
		index = value
		if _label != null:
			_label.text = options[index]

var _label: Label
var _arrows: Array[Button] = []

func _ready() -> void:
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_arrow("<", -1))
	_label = Label.new()
	_label.custom_minimum_size = Vector2(90.0, 0.0)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.label_settings = LabelSettings.new()
	_label.label_settings.font = FONT
	_label.label_settings.font_color = INK
	_label.label_settings.outline_size = 5
	_label.label_settings.outline_color = OUTLINE
	add_child(_label)
	add_child(_arrow(">", 1))
	index = clampi(index, 0, options.size() - 1)

func set_options(new_options: PackedStringArray, new_index: int) -> void:
	options = new_options
	index = clampi(new_index, 0, options.size() - 1)

## Greyed out and unclickable (e.g. window size while fullscreen).
func set_disabled(disabled: bool) -> void:
	modulate.a = 0.4 if disabled else 1.0
	for arrow in _arrows:
		arrow.disabled = disabled

func _arrow(text: String, direction: int) -> Button:
	var arrow := Button.new()
	arrow.text = text
	arrow.flat = true
	arrow.focus_mode = Control.FOCUS_NONE
	arrow.add_theme_font_override("font", FONT)
	arrow.add_theme_color_override("font_color", INK)
	arrow.add_theme_color_override("font_pressed_color", INK)
	arrow.add_theme_color_override("font_hover_color", INK_HOVER)
	arrow.add_theme_color_override("font_disabled_color", INK)
	arrow.add_theme_constant_override("outline_size", 5)
	arrow.add_theme_color_override("font_outline_color", OUTLINE)
	arrow.pressed.connect(func() -> void:
		index = posmod(index + direction, options.size())
		changed.emit(index))
	_arrows.append(arrow)
	return arrow

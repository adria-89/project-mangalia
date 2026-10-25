extends CanvasLayer

## F1 debug overlay: what the bar is doing right now, the debug keys and a log
## of what they did. Debug builds only (the editor counts) until there's a
## secret code to unlock it. The debug keys themselves (main.gd, tap_tray.gd)
## only work while it's open, so a playtest can't trip them by accident.
##
## The flags live here, not in the bar scene, so they survive R (restart).

const FONT: Font = preload("res://assets/ui/alagard.ttf")
const FONT_SIZE := 16
const LOG_LINES := 6
const KEYS := """F1  close
1 2 3  call a customer
P  placeholders walk in
H  +1 drunk, hiccup
K  next drink is perfect
U  unlock every drink
S  sea: auto / 0 / 1 / 2
M  +20 lei
[ ]  night - / +
N  end the day
T  tap drink
A  after hours (Shift: Striggy)
G  every girl in After Hours (anywhere)
R  restart"""

## Debug keys and the overlay work at all (later: unlocked by a secret code).
var enabled := OS.is_debug_build()
## The overlay is up, and with it the debug keys.
var open := false

## Every drink can be ordered from the first night (U).
var unlock_all := false
## Customers still on placeholder art walk in too (P, see CustomerData.placeholder).
var placeholders := false
## The next drink served counts as perfect, kiss and all (K). One shot.
var force_perfect := false
## Fixed sea strength instead of tonight's (S); negative = auto.
var sea := -1.0
## After Hours offers every girl, not just the ones you've won over (G, works
## in any scene).
var all_girls := false

signal all_girls_changed

## Returns the live info text; the bar sets it while it's loaded.
var info := Callable()

var _panel: PanelContainer
var _info: Label
var _log: Label
var _lines: PackedStringArray = []

func _ready() -> void:
	layer = 120 # over the night card and the wave transition
	process_mode = Node.PROCESS_MODE_ALWAYS
	_panel = PanelContainer.new()
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0, 0, 0, 0.7)
	box.set_content_margin_all(6)
	_panel.add_theme_stylebox_override("panel", box)
	_panel.position = Vector2(4, 4)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	_panel.add_child(columns)
	var left := VBoxContainer.new()
	columns.add_child(left)
	_info = _label(Color(1, 0.93, 0.65))
	left.add_child(_info)
	_log = _label(Color(0.45, 0.88, 0.45))
	left.add_child(_log)
	var keys := _label(Color(0.75, 0.72, 0.68))
	keys.text = KEYS
	columns.add_child(keys)
	_panel.hide()

func _label(color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.add_theme_constant_override("line_spacing", -4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _input(event: InputEvent) -> void:
	if enabled and event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F1:
		open = not open
		_panel.visible = open
		get_viewport().set_input_as_handled()
	elif key(event) and event.keycode == KEY_G:
		all_girls = not all_girls
		note("Every girl in After Hours: %s" % ("ON" if all_girls else "off"))
		all_girls_changed.emit()
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if open:
		_info.text = info.call() if info.is_valid() else "(no bar loaded)"

## A line in the overlay's log (and the output panel).
func note(text: String) -> void:
	print("[Debug] ", text)
	_lines.append(text)
	if _lines.size() > LOG_LINES:
		_lines.remove_at(0)
	_log.text = "\n".join(_lines)

## For the debug key handlers: a key press, and the overlay is open.
func key(event: InputEvent) -> bool:
	return open and event is InputEventKey and event.pressed and not event.echo

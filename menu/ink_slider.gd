extends Range

## Slider drawn in ink on the menu scroll: a line with end ticks and a round
## knob. Click or drag anywhere on it; left/right nudge it when focused.

const INK := Color(0.25, 0.14, 0.07)
const KNOB_FILL := Color(0.85, 0.71, 0.65)

@export var knob_radius: float = 6.0

func _ready() -> void:
	focus_mode = Control.FOCUS_CLICK
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(150.0, 18.0)
	value_changed.connect(func(_value: float) -> void: queue_redraw())

func _draw() -> void:
	var y := size.y / 2.0
	var left := knob_radius
	var right := size.x - knob_radius
	# A pale halo under the ink so it reads on top of the picture.
	for pass_index in 2:
		var color := KNOB_FILL if pass_index == 0 else INK
		var width := 6.0 if pass_index == 0 else 2.0
		draw_line(Vector2(left, y), Vector2(right, y), color, width)
		draw_line(Vector2(left, y - 4.0), Vector2(left, y + 4.0), color, width)
		draw_line(Vector2(right, y - 4.0), Vector2(right, y + 4.0), color, width)
	var knob := Vector2(lerpf(left, right, ratio), y)
	draw_circle(knob, knob_radius + 2.0, KNOB_FILL)
	draw_circle(knob, knob_radius, INK, false, 2.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_set_from_x(event.position.x)
		accept_event()
	elif event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT:
		_set_from_x(event.position.x)
		accept_event()
	elif event.is_action_pressed("ui_left"):
		value -= step
		accept_event()
	elif event.is_action_pressed("ui_right"):
		value += step
		accept_event()

func _set_from_x(x: float) -> void:
	ratio = clampf(inverse_lerp(knob_radius, size.x - knob_radius, x), 0.0, 1.0)

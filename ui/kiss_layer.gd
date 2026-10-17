extends CanvasLayer

## Lipstick prints "on the glass" of the screen. stamp() smacks one onto a
## random spot along the edges/corners; it stays until the night washes it
## off, slowly going faint. Clicking one wipes it away early. shout() flashes
## a big word across the glass.

const KISS_TEXTURE: Texture2D = preload("res://assets/ui/kiss_love.png")
const SHOUT_FONT: Font = preload("res://assets/ui/alagard.ttf")
const HEART_TEXTURE: Texture2D = preload("res://assets/ui/heart.png")
## Font size at which one of Alagard's pixels is one screen pixel.
const FONT_PIXELS := 16

## Size of a print relative to the 150 px texture.
@export var kiss_scale: float = 0.65
## More than this and the oldest print is wiped off for the new one.
@export var max_kisses: int = 8
## Prints stay all day, slowly going faint down to this opacity over faint_time seconds.
@export var faded_alpha: float = 0.45
@export var faint_time: float = 60.0
## How far in from the screen edge the prints sit (px).
@export var edge_inset: float = 45.0
## Prints keep at least this far apart (px).
@export var min_spacing: float = 90.0
## Font size of the rating pop-up at full size (see shout()). Snapped to
## whole multiples of FONT_PIXELS so the pixel font stays crisp.
@export var shout_size: int = 48

@export_group("Impact")
## Hearts that burst out of a fresh print.
@export var heart_count: int = 8
## Heart size relative to the 81 px texture.
@export var heart_scale: float = 0.3
## How far the hearts fly out (px).
@export var heart_spread: float = 90.0
## Screen flash on impact (alpha = strength).
@export var flash_color: Color = Color(1.0, 0.45, 0.7, 0.35)
@export var flash_time: float = 0.3

var _kisses: Array[Sprite2D] = []

## Smack a print onto the screen. Returns where it landed.
func stamp() -> Vector2:
	while _kisses.size() >= max_kisses:
		_fade_out(_kisses[0], 0.2)
	var kiss := Sprite2D.new()
	kiss.texture = KISS_TEXTURE
	kiss.position = _free_spot()
	kiss.rotation = deg_to_rad(randf_range(-25.0, 25.0))
	kiss.scale = Vector2.ONE * kiss_scale * 1.7
	add_child(kiss)
	_kisses.append(kiss)
	# Pops in big and squashes onto the glass.
	var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(kiss, "scale", Vector2.ONE * kiss_scale, 0.3)
	# Then slowly goes faint, but stays until the night washes it off.
	var fade := create_tween()
	fade.tween_property(kiss, "modulate:a", faded_alpha, faint_time).set_delay(0.3)
	kiss.set_meta("fade", fade)
	_flash()
	_burst_hearts(kiss.position)
	return kiss.position

## A quick pink wash over the whole screen, under the prints.
func _flash() -> void:
	var rect := ColorRect.new()
	rect.color = flash_color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.size = get_viewport().get_visible_rect().size
	add_child(rect)
	move_child(rect, 0)
	var tween := create_tween()
	tween.tween_property(rect, "modulate:a", 0.0, flash_time).set_ease(Tween.EASE_OUT)
	tween.tween_callback(rect.queue_free)

## Little hearts pop out of the print in all directions, float up and fade.
func _burst_hearts(at: Vector2) -> void:
	for i in heart_count:
		var heart := Sprite2D.new()
		heart.texture = HEART_TEXTURE
		heart.position = at
		heart.rotation = deg_to_rad(randf_range(-20.0, 20.0))
		var size := heart_scale * randf_range(0.7, 1.2)
		heart.scale = Vector2.ONE * size * 0.3
		add_child(heart)
		var angle := TAU * (i + randf_range(-0.3, 0.3)) / heart_count
		var target := at + Vector2.from_angle(angle) * heart_spread * randf_range(0.6, 1.1)
		var time := randf_range(0.6, 0.9)
		var tween := create_tween().set_parallel()
		tween.tween_property(heart, "position", target, time * 0.5).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tween.tween_property(heart, "scale", Vector2.ONE * size, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(heart, "rotation", heart.rotation + randf_range(-0.6, 0.6), time)
		# Second half: drift upward and fade out.
		tween.tween_property(heart, "position:y", target.y - 30.0, time * 0.5).set_delay(time * 0.5)
		tween.tween_property(heart, "modulate:a", 0.0, time * 0.5).set_delay(time * 0.5)
		tween.chain().tween_callback(heart.queue_free)

## Dim the prints with the room's lights (1 = lit, 0 = dark).
func set_brightness(amount: float) -> void:
	for kiss in _kisses:
		kiss.self_modulate = Color(amount, amount, amount)

## Wash everything off (e.g. a new night).
func clear() -> void:
	for kiss in _kisses.duplicate():
		_fade_out(kiss, 0.1)

## Big word that pops up mid-screen, floats up and fades (e.g. a drink's
## rating). size_scale shrinks it for lesser words.
func shout(text: String, color: Color, size_scale: float = 1.0) -> void:
	var label := Label.new()
	label.text = text
	var settings := LabelSettings.new()
	settings.font = SHOUT_FONT
	settings.font_size = maxi(roundi(shout_size * size_scale / FONT_PIXELS), 1) * FONT_PIXELS
	settings.font_color = color
	settings.outline_size = 8
	settings.outline_color = Color(0.2, 0.05, 0.1)
	label.label_settings = settings
	add_child(label)
	label.reset_size()
	var screen := get_viewport().get_visible_rect().size
	label.pivot_offset = label.size / 2.0
	label.position = (Vector2(screen.x / 2.0, screen.y * 0.3) - label.size / 2.0).round()
	label.rotation = deg_to_rad(randf_range(-6.0, 6.0))
	label.scale = Vector2.ONE * 0.3
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.5)
	tween.tween_property(label, "position:y", label.position.y - 40.0, 0.6).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.6).set_ease(Tween.EASE_IN)
	tween.tween_callback(label.queue_free)

func _fade_out(kiss: Sprite2D, time: float) -> void:
	if not _kisses.has(kiss):
		return
	_kisses.erase(kiss)
	_stop_fading(kiss)
	var tween := create_tween().set_parallel()
	tween.tween_property(kiss, "modulate:a", 0.0, time)
	tween.tween_property(kiss, "position:y", kiss.position.y + 6.0, time) # smears down
	tween.chain().tween_callback(kiss.queue_free)

## Stop a print's slow fade so a wipe can take over its opacity.
func _stop_fading(kiss: Sprite2D) -> void:
	var fade: Tween = kiss.get_meta("fade")
	if fade.is_valid():
		fade.kill()

## Click a print to wipe it: it smudges sideways and vanishes.
func _input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var point: Vector2 = get_viewport().get_canvas_transform().affine_inverse() * event.position
	for i in range(_kisses.size() - 1, -1, -1):
		var kiss := _kisses[i]
		var size := KISS_TEXTURE.get_size() * kiss_scale
		if Rect2(kiss.position - size / 2.0, size).has_point(point):
			_kisses.remove_at(i)
			_stop_fading(kiss)
			var tween := create_tween().set_parallel()
			tween.tween_property(kiss, "scale:x", kiss.scale.x * 1.4, 0.25)
			tween.tween_property(kiss, "position:x", kiss.position.x + 14.0, 0.25)
			tween.tween_property(kiss, "modulate:a", 0.0, 0.25)
			tween.chain().tween_callback(kiss.queue_free)
			get_viewport().set_input_as_handled()
			return

## A random spot along the edges or in a corner, away from other prints.
func _free_spot() -> Vector2:
	var screen := get_viewport().get_visible_rect().size
	var best := Vector2.ZERO
	var best_gap := -1.0
	for attempt in 8:
		var spot := _edge_spot(screen)
		var gap := INF
		for kiss in _kisses:
			gap = minf(gap, kiss.position.distance_to(spot))
		if gap >= min_spacing:
			return spot
		if gap > best_gap:
			best_gap = gap
			best = spot
	return best

func _edge_spot(screen: Vector2) -> Vector2:
	var left := edge_inset
	var right := screen.x - edge_inset
	var top := edge_inset
	var bottom := screen.y - edge_inset
	if randf() < 0.35: # a corner, slightly jittered
		var jitter := Vector2(randf_range(-12.0, 12.0), randf_range(-12.0, 12.0))
		return Vector2(left if randf() < 0.5 else right, top if randf() < 0.5 else bottom) + jitter
	match randi() % 4:
		0: return Vector2(randf_range(left, right), top)        # top edge
		1: return Vector2(randf_range(left, right), bottom)     # bottom edge
		2: return Vector2(left, randf_range(top, bottom))       # left edge
		_: return Vector2(right, randf_range(top, bottom))      # right edge

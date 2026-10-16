extends CanvasLayer

## Scene transitions as a wall of waves. Seven rows of the wave cutout pop up
## from the bottom one after another (like paper cutouts on sticks) until the
## screen is all sea, the scene changes behind them, then they drop away again.
## Use change_scene() / reload_scene(), or cover() / uncover() around anything.

const WAVE_TEXTURE: Texture2D = preload("res://assets/bar/water_wave.png")
## Where the crest line sits inside the wave texture (px from its top).
const CREST_Y := 165.0

@export var rows: int = 7
## Delay between one row and the next.
@export var row_stagger: float = 0.06
## How long each row takes to pop up or drop down.
@export var move_time: float = 0.45
## Brightness of the top (furthest) row; the bottom one is full brightness.
@export var top_brightness: float = 0.6
## Crest line of the bottom and top rows when the screen is covered (screen px).
@export var bottom_crest_y: float = 360.0
@export var top_crest_y: float = -50.0
## Sideways shift between rows so the crests interleave.
@export var row_shift_px: float = 37.0
@export var sway_px: float = 6.0

var _rows: Array[Sprite2D] = []
var _covered := false
var _time := 0.0

func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	var margin := sway_px + 4.0
	var size := WAVE_TEXTURE.get_size()
	# Created top row first so the lower (nearer) rows draw over the higher ones.
	for i in range(rows - 1, -1, -1):
		var row := Sprite2D.new()
		row.texture = WAVE_TEXTURE
		row.centered = false
		row.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		row.region_enabled = true
		row.region_rect = Rect2(fposmod(i * row_shift_px, size.x) - margin, 0.0, size.x + margin * 2.0, size.y)
		var shade := lerpf(1.0, top_brightness, float(i) / maxf(rows - 1, 1))
		row.self_modulate = Color(shade, shade, shade)
		row.position = Vector2(-margin, _hidden_y())
		row.visible = false
		add_child(row)
	# _rows[0] is the bottom (nearest) row.
	for i in rows:
		_rows.append(get_child(rows - 1 - i))

func _process(delta: float) -> void:
	_time += delta
	for i in _rows.size():
		var row := _rows[i]
		if row.visible:
			row.offset.x = sin(_time * 1.6 + i * 1.3) * sway_px * (1.0 if i % 2 == 0 else -1.0)

## Fade out the current scene behind the waves, switch to another, reveal it.
func change_scene(path: String) -> void:
	await cover()
	get_tree().paused = false
	get_tree().change_scene_to_file(path)
	await _settle()
	await uncover()

func reload_scene() -> void:
	await cover()
	get_tree().paused = false
	get_tree().reload_current_scene()
	await _settle()
	await uncover()

func is_covered() -> bool:
	return _covered

## Rows pop up from the bottom, nearest first, until the screen is all sea.
func cover() -> void:
	if _covered:
		return
	var tween := create_tween().set_parallel()
	for i in _rows.size():
		var row := _rows[i]
		row.visible = true
		row.position.y = _hidden_y()
		tween.tween_property(row, "position:y", _covered_y(i), move_time) \
			.set_delay(i * row_stagger).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await tween.finished
	_covered = true

## Rows drop away, furthest first, revealing whatever is behind.
func uncover() -> void:
	if not _covered:
		return
	var tween := create_tween().set_parallel()
	for i in _rows.size():
		var order := _rows.size() - 1 - i
		tween.tween_property(_rows[i], "position:y", _hidden_y(), move_time) \
			.set_delay(order * row_stagger).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	await tween.finished
	for row in _rows:
		row.visible = false
	_covered = false

func _covered_y(row: int) -> float:
	var crest := lerpf(bottom_crest_y, top_crest_y, float(row) / maxf(rows - 1, 1))
	return crest - CREST_Y

func _hidden_y() -> float:
	# Crest just below the screen (above the crest the texture is see-through).
	return get_viewport().get_visible_rect().size.y + 20.0 - CREST_Y

## Give the new scene a couple of frames to build before revealing it.
func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

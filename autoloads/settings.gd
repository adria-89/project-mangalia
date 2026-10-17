extends Node

## Player settings, saved to user://settings.cfg: volumes, how much the
## customers jiggle, dialogue speed and the window. Changes apply right away;
## save() writes them out (the options menu does it when it closes).

const PATH := "user://settings.cfg"
const BASE_SIZE := Vector2i(540, 400)
## Physics strength choices: Off / Normal / Max (multiplies the jiggle).
const PHYSICS_SCALES: Array[float] = [0.0, 1.0, 1.6]
## Text speed choices: Slow / Normal / Fast (multiplies typing and reading).
const TEXT_SPEEDS: Array[float] = [0.6, 1.0, 1.7]
const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX"]

## Linear volume (0..1) per bus.
var volumes := {&"Master": 1.0, &"Music": 0.8, &"SFX": 1.0}
var physics := 1
var text_speed := 1
var fullscreen := false
var window_scale := 2

func _ready() -> void:
	# Music and SFX buses, both feeding Master.
	for bus: StringName in [&"Music", &"SFX"]:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, &"Master")
	# Every sound player left on Master is a sound effect; music players set
	# their bus to Music themselves.
	get_tree().node_added.connect(_on_node_added)
	_load()
	for bus in BUSES:
		_apply_volume(bus)
	_apply_window()

func physics_scale() -> float:
	return PHYSICS_SCALES[physics]

func text_speed_scale() -> float:
	return TEXT_SPEEDS[text_speed]

func set_volume(bus: StringName, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)

func set_fullscreen(on: bool) -> void:
	fullscreen = on
	_apply_window()

func set_window_scale(value: int) -> void:
	window_scale = clampi(value, 1, max_window_scale())
	_apply_window()

## Biggest whole-number window scale that still fits on the screen.
func max_window_scale() -> int:
	var usable := DisplayServer.screen_get_usable_rect().size
	return maxi(1, mini(usable.x / BASE_SIZE.x, usable.y / BASE_SIZE.y))

func save() -> void:
	var config := ConfigFile.new()
	for bus in BUSES:
		config.set_value("audio", bus, volumes[bus])
	config.set_value("game", "physics", physics)
	config.set_value("game", "text_speed", text_speed)
	config.set_value("display", "fullscreen", fullscreen)
	config.set_value("display", "window_scale", window_scale)
	config.save(PATH)

func _load() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) != OK:
		return
	for bus in BUSES:
		volumes[bus] = config.get_value("audio", bus, volumes[bus])
	physics = clampi(config.get_value("game", "physics", physics), 0, PHYSICS_SCALES.size() - 1)
	text_speed = clampi(config.get_value("game", "text_speed", text_speed), 0, TEXT_SPEEDS.size() - 1)
	fullscreen = config.get_value("display", "fullscreen", fullscreen)
	window_scale = config.get_value("display", "window_scale", window_scale)

func _apply_volume(bus: StringName) -> void:
	var index := AudioServer.get_bus_index(bus)
	AudioServer.set_bus_volume_db(index, linear_to_db(volumes[bus]))
	AudioServer.set_bus_mute(index, volumes[bus] <= 0.0)

func _apply_window() -> void:
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	# Clamped only for this screen; the saved choice stays as it is.
	var window_size := BASE_SIZE * clampi(window_scale, 1, max_window_scale())
	var usable := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_size(window_size)
	DisplayServer.window_set_position(usable.position + (usable.size - window_size) / 2)

func _on_node_added(node: Node) -> void:
	if (node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D) \
			and node.get("bus") == &"Master":
		node.set("bus", &"SFX")

extends Node

## Player settings, saved to user://settings.cfg: volumes, how much the
## customers jiggle, dialogue speed, the window and NSFW content (it unlocks
## After Hours), with After Hours' own settings (the NSFW pages). Changes apply right away;
## save() writes them out (the options menu does it when it closes).

const PATH := "user://settings.cfg"
const BASE_SIZE := Vector2i(540, 400)
## Physics strength choices: Off / Normal / Max (multiplies the jiggle).
const PHYSICS_SCALES: Array[float] = [0.0, 1.0, 1.6]
## Text speed choices: Slow / Normal / Fast (multiplies typing and reading).
const TEXT_SPEEDS: Array[float] = [0.6, 1.0, 1.7]
const BUSES: Array[StringName] = [&"Master", &"Music", &"SFX", &"Violin", &"Body", &"Voice", &"CabinMusic"]
## Where each bus but Master sends. After Hours' own go through SFX and
## Music, so those sliders turn them down too.
const BUS_SENDS := {
	&"Music": &"Master", &"SFX": &"Master",
	&"Violin": &"SFX", &"Body": &"SFX", &"Voice": &"SFX", &"CabinMusic": &"Music",
}
## Screen shake choices: Off / Normal / Max.
const SHAKE_SCALES: Array[float] = [0.0, 1.0, 1.8]

## After Hours' settings, saved under [nsfw].
const NSFW_KEYS: Array[String] = ["futa", "anal", "bulge", "forced", "cum", "sweat", "marks", "talk", "difficulty", "slapping", "endless", "shake"]

## NSFW content was switched on or off.
signal nsfw_changed(on: bool)

## Linear volume (0..1) per bus.
var volumes := {
	&"Master": 1.0, &"Music": 0.8, &"SFX": 1.0,
	&"Violin": 1.0, &"Body": 1.0, &"Voice": 1.0, &"CabinMusic": 1.0,
}
var physics := 1
var text_speed := 1
var fullscreen := false
var window_scale := 2
## NSFW content: After Hours shows up on the main menu. Off by default.
var nsfw := false

# After Hours (the NSFW pages).
## Girls with their own penis have it (off: their pussy is back instead).
var futa := true
## 0 = on (each girl's own taste), 1 = every girl has to be asked, 2 = off.
var anal := 0
## The belly bulge (anal, deep).
var bulge := true
## Pushing hard past her no forces it (off: a no just blocks).
var forced := true
## 0 = inside and out, 1 = outside only, 2 = no cum shown.
var cum := 0
var sweat := true
## Slaps leave a red mark that fades.
var marks := true
## How much she talks: 0 = normal, 1 = less, 2 = silent (gasps only).
var talk := 0
## 0 = relaxed (she takes more and minds less), 1 = normal, 2 = strict.
var difficulty := 1
## Left click slaps her butt.
var slapping := true
## Testing: nothing ends the scene (her comfort never runs out, finishing
## starts another round).
var endless := false
## Screen shake: an index into SHAKE_SCALES.
var shake := 1

func _ready() -> void:
	# The buses (Music and SFX feed Master, After Hours' feed those).
	for bus: StringName in BUS_SENDS:
		if AudioServer.get_bus_index(bus) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, BUS_SENDS[bus])
	# Every sound player left on Master is a sound effect; music players set
	# their bus to Music themselves.
	get_tree().node_added.connect(_on_node_added)
	_load()
	for bus in BUSES:
		_apply_volume(bus)
	_apply_window()

func shake_scale() -> float:
	return SHAKE_SCALES[shake]

func physics_scale() -> float:
	return PHYSICS_SCALES[physics]

func text_speed_scale() -> float:
	return TEXT_SPEEDS[text_speed]

func set_volume(bus: StringName, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)

func set_nsfw(on: bool) -> void:
	nsfw = on
	nsfw_changed.emit(on)

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
	config.set_value("game", "nsfw", nsfw)
	for key in NSFW_KEYS:
		config.set_value("nsfw", key, get(key))
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
	nsfw = config.get_value("game", "nsfw", nsfw)
	for key in NSFW_KEYS:
		set(key, config.get_value("nsfw", key, get(key)))
	shake = clampi(shake, 0, SHAKE_SCALES.size() - 1)
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

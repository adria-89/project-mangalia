extends Node

## Game progress, saved as JSON to user://save_DD_MM_YY_HH_MM_SS.prenadez the
## way Totenkerkar does it: every save is a new file, the newest one is what
## gets loaded, and only the last KEPT_SAVES stay (as backups).
##
## A save is made every morning, once the night card is paid: the night, the
## money, each girl's affection and how far her talk has got, and the drinks
## the girls have taught. Which girls After Hours offers (the ones whose bar
## you've filled) carries over to new games too. Quitting mid-day loses just that day; a game over
## goes back to that morning's save. Settings live in Settings
## (settings.cfg), not here.

const SAVE_DIR := "user://"
const SAVE_PREFIX := "save_"
const SAVE_EXTENSION := "prenadez"
const KEPT_SAVES := 5
## Bumped when the format changes, so old saves can be read differently.
const VERSION := 1

## The run being played. main.gd starts each day from these and fills them in
## each morning (see save_game()). The per-girl ones are keyed by id_of(her).
var night := 0
var money := 0
var affection := {}
## How many times she's visited, and which dialogue set she used last.
var visits := {}
var last_set := {}
## Names of the drinks taught so far (see CustomerData.lessons).
var taught: Array[String] = []
## The boss has given his speech (night 0 opens with it until then).
var intro_seen := false
## Girls you've filled the bar of, by id: they stay after closing (After Hours).
## Kept across new games.
var after_hours: Array[String] = []

## Before any run is loaded (the main menu's After Hours), who's been won over.
func _ready() -> void:
	after_hours.assign(_read_save().get("after_hours", []))

## She's offered in After Hours: won over, or every girl with the debug G toggle.
func stays_after_hours(data: Resource) -> bool:
	return Debug.all_girls or id_of(data) in after_hours

func win_over(data: Resource) -> void:
	if id_of(data) not in after_hours:
		after_hours.append(id_of(data))

## A girl's key in the save: her resource's file name, e.g. "lizard".
static func id_of(data: Resource) -> String:
	return data.resource_path.get_file().get_basename()

func has_save() -> bool:
	return not _latest_save_path().is_empty()

## A fresh run from night 0, saved right away (so a game over on the very
## first day has a morning to go back to).
func new_game() -> void:
	night = 0
	money = 0
	affection = {}
	visits = {}
	last_set = {}
	taught = []
	intro_seen = false
	save_game()

## The run as it was in the newest save. False if there is none (or it's unreadable).
func load_game() -> bool:
	var data := _read_save()
	if data.is_empty():
		return false
	night = int(data.get("night", 0))
	money = int(data.get("money", 0))
	affection = _floats(data.get("affection", {}))
	visits = _ints(data.get("visits", {}))
	last_set = _ints(data.get("last_set", {}))
	taught.assign(data.get("taught", []))
	intro_seen = bool(data.get("intro_seen", false))
	after_hours.assign(data.get("after_hours", []))
	return true

func save_game() -> void:
	var data := {
		"version": VERSION,
		"night": night,
		"money": money,
		"affection": affection,
		"visits": visits,
		"last_set": last_set,
		"taught": taught,
		"intro_seen": intro_seen,
		"after_hours": after_hours,
	}
	var file := FileAccess.open(_new_save_path(), FileAccess.WRITE)
	if file == null:
		push_error("Couldn't write the save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	_prune_old_saves()

## Opens the folder with the saves in the system's file browser.
func open_folder() -> void:
	OS.shell_open(ProjectSettings.globalize_path(SAVE_DIR))

# JSON gives every number back as a float.
func _floats(source: Variant) -> Dictionary:
	var result := {}
	if source is Dictionary:
		for key: String in source:
			result[key] = float(source[key])
	return result

func _ints(source: Variant) -> Dictionary:
	var result := {}
	if source is Dictionary:
		for key: String in source:
			result[key] = int(source[key])
	return result

## Every save on disk, oldest first.
func _save_files() -> Array[String]:
	var paths: Array[String] = []
	for file_name in DirAccess.get_files_at(SAVE_DIR):
		if file_name.begins_with(SAVE_PREFIX) and file_name.get_extension() == SAVE_EXTENSION:
			paths.append(SAVE_DIR + file_name)
	paths.sort_custom(func(a: String, b: String) -> bool:
		var time_a := FileAccess.get_modified_time(a)
		var time_b := FileAccess.get_modified_time(b)
		return time_a < time_b if time_a != time_b else a < b)
	return paths

func _latest_save_path() -> String:
	var saves := _save_files()
	return saves[-1] if not saves.is_empty() else ""

func _read_save() -> Dictionary:
	var path := _latest_save_path()
	if path.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _new_save_path() -> String:
	var now := Time.get_datetime_dict_from_system()
	return SAVE_DIR + "%s%02d_%02d_%02d_%02d_%02d_%02d.%s" % [SAVE_PREFIX, now.day, now.month, now.year % 100,
		now.hour, now.minute, now.second, SAVE_EXTENSION]

func _prune_old_saves() -> void:
	var saves := _save_files()
	while saves.size() > KEPT_SAVES:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(saves.pop_front()))

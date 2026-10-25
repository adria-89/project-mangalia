@tool
class_name AfterHoursGirl
extends Resource

## One girl's after-hours scene: her body (which parts, which colours), what
## she likes and what she says. It lives in her CustomerData (After Hours),
## which also gives the scene her name, voice and faces.

enum Consent { YES, ASK, NO }

@export_group("Body")
## Her skin, dark to light. Every grey part is coloured with this.
@export var skin_ramp: Gradient
## Insides: pussy, anus.
@export var flesh_ramp: Gradient
@export var line_color := Color(0.06, 0.06, 0.03)
## fapwall's skin details: patterns on her butt, back and legs (spots, scales,
## patches, seams, fur on the holes...). 1 = plain. Her ramps still colour it.
## Only a few skins have their own holes and futa (tools/fapwall/parts.py's
## HOLE_SKINS); the rest use skin 14's.
@export_range(1, 52) var skin_detail: int = 1
## Which variant of each part (frames in assets/placeholder/fapwall/parts).
@export_range(1, 7) var pussy_type: int = 1
@export_range(1, 6) var anus_type: int = 1
## Her own penis, where the pussy is (then the pussy can't be used). 0 = none.
@export_range(0, 6) var futa_type: int = 0
## Pubic hair style (fapwall's 11), and around the anus (2-5). 0 = shaved.
@export_range(0, 11) var pubic_hair: int = 0
@export_range(0, 5) var anal_hair: int = 0
## Hair colour; empty = her skin.
@export var hair_ramp: Gradient
## fapwall's 24 tails (2-24). 0 or 1 = no tail.
@export_range(0, 24) var tail_type: int = 0
## 1 = fapwall's size for that tail.
@export var tail_scale: float = 1.0
## Tail colour; empty = her skin.
@export var tail_ramp: Gradient
## Butt jiggle: higher stiffness = firmer, quicker.
@export var butt_stiffness: float = 120.0
@export var butt_damping: float = 7.0

@export_group("Size")
## Butt width and height (1 = fapwall's size), with what's on it (holes,
## tail, shadow). The legs have their own settings below.
@export var butt_size := Vector2(0.85, 0.85)
## Leg width and length (1 = fapwall's size).
@export var legs_size := Vector2(0.85, 1.0)
## Moves both legs from where fapwall puts them (rig pixels; x moves the left
## leg, the right one mirrors it, so +x brings them in toward the middle).
@export var legs_offset := Vector2(12.0, 0.0)
## How far the legs swing in toward the middle from the hips (degrees).
@export_range(-30.0, 30.0, 0.5) var leg_angle: float = 22.5
## How the legs are posed (fapwall's 8 leg poses; 1 = kneeling, spread).
@export_range(1, 8) var leg_pose: int = 1
## Her belly, tucked under her butt until a penis bulges it out: its size (1 = as
## drawn) and where it sits (rig pixels from the rig's belly_pos).
@export var belly_size := Vector2(1.0, 1.0)
@export var belly_offset := Vector2.ZERO
## How much a deep, thick penis in her anus bulges her belly (0 = never, 2 = a lot).
@export_range(0.0, 2.0, 0.05) var bulge: float = 1.0

@export_group("Clothes")
## fapwall's outfit (the same frame on her butt, back, thighs and shins), by
## its frame number; only the ones in tools/fapwall/parts.py's OUTFITS exist.
@export_enum("None:0", "139:139") var outfit: int = 0
## Garters, trims and bands over the butt (fapwall's "over"), likewise.
@export_enum("None:0", "16:16") var over: int = 0
## Tints all her clothes (white = fapwall's colours).
@export var clothes_tint := Color.WHITE

@export_group("Taste")
## Strokes per second she wants at each stage, warm-up to the edge.
@export var pace: PackedFloat32Array = [0.8, 1.1, 1.5, 2.0]
## How far off the pace still counts (0.35 = 35% either way).
@export var pace_tolerance: float = 0.35
## Arousal per stroke on pace (it takes 1.0 to reach the finish).
@export var arousal_per_stroke: float = 0.03
## Comfort lost per mistake is multiplied by this (2 = twice as touchy).
@export var touchiness: float = 1.0
## Ignored with her own penis (futa_type): anal is her only hole, so it's yes.
@export var anal: Consent = Consent.ASK
## Asked for anal, she says yes once comfort and arousal are at least this.
@export var anal_yes_comfort: float = 0.6
@export var anal_yes_arousal: float = 0.4
## Going deeper than fapwall's depth: 1 = she loves it (arousal, hearts),
## 0 = too much (costs comfort) until she's close to the edge.
@export_range(0.0, 1.0, 0.05) var likes_deep: float = 0.5
## Wants it inside: finishing inside is a good ending, pulling out a let-down
## (and the other way round when off).
@export var wants_inside: bool = true

@export_group("Lines")
## What she says, per event. One line is picked at random. Events: start,
## insert, stage_1, stage_2, stage_3, good, too_fast, too_slow, wrong_hole,
## slip, slap (a slap on her butt), slap_red (slapped a lot), ask_yes, ask_no, respected, pushed, angry_stop, edge, inside,
## outside, after, left_early, forced (taken past her no), deep, too_deep,
## all_in (the whole length), her_cum (she cums), not_yet (you came before her).
## With her own penis (futa_type), "futa_<event>" is said instead when she has it.
@export var lines: Dictionary[String, PackedStringArray] = {}

func line(event: String) -> String:
	var pool: PackedStringArray = lines.get(event, PackedStringArray())
	return pool[randi() % pool.size()] if not pool.is_empty() else ""

## Where the characters live: every CustomerData here with After Hours
## filled in is in the picker and the editor's preview lists.
const FOLDER := "res://customer/"

## Every character in FOLDER who stays after closing, by name, sorted.
static func all() -> Dictionary:
	var girls := {}
	for file in DirAccess.get_files_at(FOLDER):
		# Exported games rename resources to .remap; load by the original name.
		file = file.trim_suffix(".remap")
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var character := load(FOLDER + file) as CustomerData
		if character and character.after_hours:
			girls[character.display_name] = character
	var sorted := {}
	var names := girls.keys()
	names.sort()
	for girl_name in names:
		sorted[girl_name] = girls[girl_name]
	return sorted

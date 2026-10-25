@tool
class_name BodyRig
extends Node2D

## Rear view built from fapwall's parts (tools/fapwall/parts.py: one atlas
## per part, every variant in it) and animated in code, the way fapwall's
## timeline does it:
##
## 1. The tip pushes against the closed hole and squashes it (wider, flatter,
##    nudged in) for the last few pixels.
## 2. Pop: in one frame the closed hole is swapped for the open one. No fade.
## 3. Inside, the open lips are drawn twice with the penis between them: a
##    squashed back copy under it, the front copy over it, so they wrap the
##    shaft. Strokes widen the front a little and drag the back along.
##
## The penis comes from below into the pussy (tip up) and from above into
## the anus (tip down, fapwall's own art for it); out of her it turns to face
## whichever hole it's nearer to. It only presses on a hole while pushing
## (the mouse button held); otherwise it glides over them, so it can go past
## one to reach the other.
##
## Everything about how she looks is in her After Hours (AfterHoursGirl):
## skin detail, hole types, futa, pubic hair, tail, clothes, sizes, legs.
## Like fapwall, her butt and shadow breathe and her legs don't. Every deep
## stroke kicks the butt springs, the tail and the legs; near the end the
## legs tremble. Cum shows in the hole after a creampie and runs down her
## butt; pulled out, it lands on her butt. Her belly (tools/belly.py draws
## it) is tucked up under her butt, out of sight; the deeper and thicker the
## penis is in her anus, the more it bulges and pushes down out from under it,
## over her thighs.
##
## Feel: the closed hole resists (the anus more; she gets easier as she gets
## wet), jab at it too fast and you bounce off, push through and it pops
## open with an overshoot and a jolt through her. Inside, her body follows
## the penis on a spring and the cheeks ripple on each impact. Push hard
## past a refused anus and you force your way in (forced).
##
## Nothing is built until setup() gives it a girl. In the editor it shows
## preview_girl, and the "Her Body" group below edits her own After Hours
## (saved to her file).

## The tip started pressing on a hole (call block() to refuse it).
signal press_started(hole: Hole)
## The hole popped open. strength: about 0.4..1.2, from how hard it went in.
signal popped(hole: Hole, strength: float)
## Jabbed at the hole too fast: the tip bounced off it.
signal bounced(hole: Hole)
## Pushed hard past a refused hole and went in anyway.
signal forced(hole: Hole)
## The penis came out of a hole (backed out, or pull_out()).
signal pulled_out(hole: Hole)
## A deep stroke landed. strength: about 0..1, from how fast it went in.
signal thrust(strength: float)
## A stroke that turned back before deep_at (teasing). length: how far it
## went, in depth (shallow_min..deep_at).
signal shallow(length: float)

const PARTS_DIR := "res://assets/placeholder/fapwall/parts/"
const SKIN_SHADER: Shader = preload("res://afterhours/skin.gdshader")
const BELLY: Texture2D = preload("res://assets/placeholder/afterhours/belly.png")
## Frames in BELLY, in a grid BELLY_COLUMNS wide: flat (tucked under her
## butt) to fully bulged, about a pixel apart so it grows smoothly.
const BELLY_FRAMES := 48
const BELLY_COLUMNS := 8

enum Hole { PUSSY, ANUS }
const HOLE_PARTS := {Hole.PUSSY: "pussy", Hole.ANUS: "anus"}
## Which way (y) the tip goes in: up into the pussy, down into the anus.
const ENTRY_DIR := {Hole.PUSSY: -1.0, Hole.ANUS: 1.0}
## Her After Hours groups shown on the rig in the editor ("Her Body").
const EDITED_GROUPS := ["Body", "Clothes", "Size"]

## How each hole reacts, read off fapwall's timeline (its pixels, before
## rig.json's scale). squash: the closed hole's scale just before the pop;
## nudge: how far it's pushed (y). front/back: the open lips' scale shallow
## and deep (flips included), back_y: the back copy's offset from the front,
## shallow and deep.
const FEEL := {
	Hole.PUSSY: {
		squash = Vector2(1.26, 0.87), nudge = -4.1,
		front = [Vector2(0.95, 1.0), Vector2(0.98, 0.98)],
		back = [Vector2(0.95, -0.64), Vector2(0.98, -0.64)], back_y = [-1.4, -2.9],
	},
	Hole.ANUS: {
		squash = Vector2(1.39, 0.76), nudge = 3.5,
		front = [Vector2(0.94, -1.0), Vector2(0.98, -1.0)],
		back = [Vector2(0.94, 0.84), Vector2(0.98, 0.84)], back_y = [-13.2, -13.8],
	},
}
## fapwall's penis travel inside (its pixels): how far past the entrance the
## tip is when shallow and when deep.
const TIP_SHALLOW := 31.0
const TIP_DEEP := 56.0
## How far past the entrance (its pixels) the shaft still shows, inside the
## dark opening; the rest is inside her. The anus's opening is much smaller.
const SHOW_PAST := {Hole.PUSSY: 20.0, Hole.ANUS: 5.0}
## How far past the entrance (its pixels) the tip pushes before it pops in:
## the anus is tighter. Wet, it takes up to WET_EASE less.
const PRESS_DEPTH := {Hole.PUSSY: 20.0, Hole.ANUS: 30.0}
const WET_EASE := 0.4
## How tight each hole is inside: 0 slides freely, 1 barely follows the
## mouse. Wet, it's up to half as tight.
const GRIP := {Hole.PUSSY: 0.35, Hole.ANUS: 0.72}
## How far past a refused hole's entrance (its pixels) pushing forces it.
const FORCE_DEPTH := 55.0
## A stroke turns round once it's backed off this far (depth) from its
## deepest, or come back in this far from its shallowest, so mouse jitter
## isn't a stroke.
const STROKE_TURN := 0.12
## fapwall's left/right asymmetries: the right side uses this frame instead
## (a skin detail, an outfit). 1 = nothing there.
const SKIN_RIGHT := {49: 50, 50: 49}
const OUTFIT_RIGHT := {24: 25, 25: 24, 74: 1, 130: 1, 131: 1}
## The skin detail whose hole art exists for every type (the fallback).
const BASE_SKIN := 14
## Room (art pixels) either side of a penis's art for it to bend into, and
## the furthest its tip bends (see skin.gdshader's bend).
const BEND_PAD := 12.0
const BEND_MAX := 10.0

## Who's shown in the editor, to lay the scene out around her (every girl in
## AfterHoursGirl.FOLDER with After Hours filled in is in the list).
@export var preview_girl: String = "Lizard":
	set(value):
		preview_girl = value
		if Engine.is_editor_hint() and is_inside_tree():
			setup(_preview())
## The partner's penis (frame in its atlas) and colours.
@export_range(1, 23) var penis_type: int = 1:
	set(value):
		penis_type = value
		_rebuild_preview()
@export var penis_skin: Gradient
@export var penis_flesh: Gradient
## Her wetness on the penis (coat).
@export var coat_color := Color(0.9, 0.95, 1.0):
	set(value):
		coat_color = value
		if _penis_material:
			_penis_material.set_shader_parameter("coat_color", value)
## Editor only: how wet the penis looks in the preview, to tune the coat.
@export_range(0.0, 1.0, 0.05) var preview_coat: float = 0.0:
	set(value):
		preview_coat = value
		if Engine.is_editor_hint():
			coat = value
## Cum colour, dark to light.
@export var cum_dark := Color(0.82, 0.8, 0.72)
@export var cum_light := Color(1.0, 0.99, 0.95)

@export_group("Feel")
## How far the mouse travels (rig pixels) from just in to all the way in.
@export var stroke_length: float = 64.0
## Depth past this counts as a deep stroke.
@export var deep_at: float = 0.85
## A stroke that turns back before deep_at counts as a shallow one if it
## went at least this far (in depth).
@export var shallow_min: float = 0.3
## How hard a stroke at full speed kicks the butt (pixels per second).
@export var kick: float = 120.0
## How much everything bounces (springs, ripple, body follow). 0.5 = lively, 1 = cartoony.
@export var bounce: float = 0.5
## How much a penis bends as it moves (its tip lags behind, then wobbles
## back), hers too. 0 = stiff.
@export_range(0.0, 3.0, 0.05) var sway: float = 1.0
## How big the pop is when a hole opens.
@export var pop_strength: float = 1.0
## How far her body is shoved forward at full depth (rig pixels).
@export var follow: float = 2.5
## How much moving in and out pushes the cheeks (besides the hit at the end
## of a deep stroke). Small = barely moves.
@export var stroke_push: float = 40.0
## How much more of the penis can go in past fapwall's depth: 0 = fapwall's
## (about a fifth of it), 1 = all of it, down to the base. Strokes count at
## fapwall's deep point either way; past it is extra.
@export_range(0.0, 1.0, 0.05) var reach: float = 1.0
## How much the holes grip (lag and cling); 0 = smooth, 1 = as GRIP says.
@export_range(0.0, 2.0, 0.05) var grip_strength: float = 1.0
## How far her legs open outward while the penis is in her (degrees); they
## ease open and stay open, a bit wider as she gets aroused.
@export_range(0.0, 30.0, 0.5) var leg_spread: float = 8.0
## How much each stroke pushes them a little further out (degrees).
@export_range(0.0, 10.0, 0.25) var leg_pulse: float = 2.0
## How much of the penis always stays out, even all the way in (0.2 = a fifth).
@export_range(0.0, 0.8, 0.05) var base_out: float = 0.2
## Past fapwall's depth the penis goes this many pixels per pixel of mouse,
## so the whole length fits in the window.
@export var deep_gain: float = 2.0
## How much a hole wobbles as it snaps shut when the penis comes out.
@export var shut_bounce: float = 1.0
## Moving the tip faster than this (rig pixels per second) while pressing on
## a closed hole bounces it off.
@export var jab_speed: float = 900.0
## The tip presses on a hole when it crosses its entrance (up for the pussy,
## down for the anus) within this far of its centre (rig pixels).
@export var entry_half_width: float = 10.0
## Slapped red (see skin.gdshader's cheek_red): how much redder each slap
## makes the whole cheek (0..1), and seconds for a fully red cheek to calm down.
@export var mark_per_slap: float = 0.14
@export var mark_fade: float = 20.0
## A cheek this red (0..1) gets the "#" of welts (skin.gdshader's hurt),
## fading in over the next bit of red.
@export_range(0.0, 1.0, 0.05) var hurt_at: float = 0.5
## How fast the penis turns round between the holes (half turns per second).
@export var turn_speed: float = 5.0
## Out of her, it only turns round once the tip is this far (rig pixels)
## past the middle between the holes, so it doesn't flip back and forth there.
@export var turn_margin: float = 8.0
## How much a stroke swings the legs (thighs out, knees bend).
@export var leg_kick: float = 2.5
## How hard the legs tremble when she's close (radians).
@export var leg_tremble: float = 0.02
## fapwall's breathing: one slow stretch of the butt every this many seconds.
@export var breath_period: float = 2.07
@export_group("Belly")
## Where her belly's top middle sits at rest, in her butt's space (it
## follows her butt): tucked up under it, out of sight. Each girl moves it
## with belly_offset.
@export var belly_pos := Vector2(0, -12):
	set(value):
		belly_pos = value
		if _belly:
			_apply_size()
## Depth (see depth) where the bulge starts; it's full at the deepest.
@export var bulge_from: float = 1.2
## How far the belly drops out from under her butt at the biggest bulge, on
## top of what the frames do (rig pixels, her butt's space).
@export var bulge_drop: float = 0.0
## How much a stroke's kick stretches it for a moment (0 = not at all).
@export_range(0.0, 0.3, 0.01) var bulge_bounce: float = 0.08
## A shaft this wide (art pixels) bulges her by the girl's bulge; thicker
## more, thinner less.
@export var bulge_girth: float = 60.0
## Editor only: how bulged the preview is, to lay it out.
@export_range(0.0, 1.0, 0.05) var preview_bulge: float = 0.6:
	set(value):
		preview_bulge = value
		if Engine.is_editor_hint() and _belly:
			_bulge = value
			_apply_size()
@export_group("")

var hole := Hole.PUSSY
## Pushing hard past a refused hole forces it (off: a no just blocks).
var can_force := true
## Slaps leave a red mark (off in the settings: they don't).
var show_marks := true
## 0 = just in, 1 = fapwall's full depth, past 1 = deeper (see reach and
## max_depth()). Only used while inserted.
var depth := 0.0
var inserted := false
## The hole the tip is pressing on (-1 = none), and how hard (0..1, 1 pops in).
var pressing := -1
var press := 0.0
## Pushing on a hole she refused: 0..1 of the way to forcing it (it strains,
## she clenches and shakes).
var forcing := 0.0
## Where the tip is while out (her butt's space).
var aim := Vector2(0, 90)
## Her arousal, 0..1: her legs open wider and tremble near the end.
var arousal := 0.0
## Wetness, 0..1 (see skin.gdshader).
var shine := 0.0:
	set(value):
		shine = value
		_set_uniform("shine", value)
## Her wetness coating the penis, 0..1 (see skin.gdshader).
var coat := 0.0:
	set(value):
		coat = value
		if _penis_material:
			_penis_material.set_shader_parameter("coat", value)
var _penis_material: ShaderMaterial

var _girl: AfterHoursGirl
## In the editor: the character whose After Hours is shown (saved on edits).
var _character: CustomerData
var _rig: Dictionary
## rig.json's scale: fapwall pixels to rig pixels.
var _px := 1.0
var _atlases := {}
var _body: Node2D
var _shadow: Sprite2D
var _legs: Array[Node2D] = []
var _shins: Array[Node2D] = []
var _shin_base: Array[Transform2D] = []
var _halves: Array[Node2D] = []
## Each half's butt sprite (it has its own skin material, for its redness),
## and how red that cheek is from slaps (0..1).
var _butts: Array[Sprite2D] = []
var _marks: Array[float] = [0.0, 0.0]
var _half_base: Array[Vector2] = []
## Per hole, its state's container ("closed", "cum", "back", "front").
var _holes := {}
var _hole_base := {}
var _insides := {}
var _entrance := {}
## Holes she's been filled in (show their cum state).
var _filled := {}
var _creams: Array[Sprite2D] = []
var _futa: Node2D
var _futa_sprite: Sprite2D
## Her penis twitching (futa_spurt()), a spring.
var _futa_twitch := 0.0
var _futa_twitch_velocity := 0.0
## Her penis pumping as it shoots (futa_spurt()): + stretched longer and
## thinner, - squashed, a spring.
var _futa_pump := 0.0
var _futa_pump_velocity := 0.0
## The penises bending, springs: (bend, its velocity), see _bend_step().
## And where their tips were last frame (rig space; INF = start over).
var _bend := Vector2.ZERO
var _futa_bend := Vector2.ZERO
var _last_tip := Vector2.INF
var _futa_last_tip := Vector2.INF
## Refused hole: no pressing on it again until the tip has backed off out of it.
var _blocked := -1
## 0 = tip up (from below, the pussy), 1 = tip down (from above, the anus).
var _facing := 0.0
## The hole it's turning to face.
var _facing_hole := Hole.PUSSY
## The mouse button was held last time push() was called.
var _pushing := false
## Tracking strokes for shallow(): heading in or not, and the deepest and
## shallowest points of the current stroke.
var _going_in := false
var _stroke_peak := 0.0
var _stroke_from := 0.0
var _leg_swing: Array[float] = [0.0, 0.0]
var _leg_velocity: Array[float] = [0.0, 0.0]
## In the editor: what the preview girl looked like last time (see _process).
var _preview_state := ""
var _tail: Sprite2D
var _penis: Sprite2D
var _penis_clip: Polygon2D
var _materials: Array[ShaderMaterial] = []
## Her belly (over her legs, under her butt).
var _belly: Sprite2D
## How bulged she is, 0..about 1.5 (a spring toward what the penis does).
var _bulge := 0.0
var _bulge_velocity := 0.0
## Each penis art's shaft width (see _shaft_width()), by atlas and region.
var _shaft_widths := {}
var _spring: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _spring_velocity: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO]
var _tail_angle := 0.0
var _tail_velocity := 0.0
var _prev_depth := 0.0
var _depth_speed := 0.0
var _was_deep := false
var _flinch := 0.0
var _time := 0.0
## The hole the tip was blocked from was refused (not just bounced off):
## pushing hard past it forces it.
var _refused := false
## Springs: the pop overshoot, her body shoved by the penis, the lips
## dragged in and out, and the flattening on impact.
var _pop := 0.0
var _pop_velocity := 0.0
var _push := 0.0
var _push_velocity := 0.0
var _drag := 0.0
var _drag_velocity := 0.0
var _impact := 0.0
## Her legs spreading outward (degrees), a spring.
var _spread := 0.0
var _spread_velocity := 0.0
## The hole the penis just came out of, wobbling shut.
var _shut_hole := -1
var _shut := 0.0
var _shut_velocity := 0.0
## Kicks still to land: [seconds left, half, velocity] (the cheek ripple).
var _kicks: Array = []

func _ready() -> void:
	if Engine.is_editor_hint():
		setup(_preview())

func _validate_property(property: Dictionary) -> void:
	if property.name == "preview_girl":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(AfterHoursGirl.all().keys())

func _preview() -> AfterHoursGirl:
	_character = AfterHoursGirl.all().get(preview_girl)
	return _character.after_hours if _character else null

# "Her Body": in the editor, the preview girl's own After Hours (her body,
# clothes and sizes) shows here and edits go straight into her file.

func _get_property_list() -> Array[Dictionary]:
	var list: Array[Dictionary] = []
	if not Engine.is_editor_hint() or _girl == null:
		return list
	for property in _edited_properties():
		var shown: Dictionary = property.duplicate()
		shown.usage = PROPERTY_USAGE_EDITOR
		list.append(shown)
	return list

func _get(property: StringName) -> Variant:
	if Engine.is_editor_hint() and _girl and _is_edited(property):
		return _girl.get(property)
	return null

func _set(property: StringName, value: Variant) -> bool:
	if not (Engine.is_editor_hint() and _girl and _is_edited(property)):
		return false
	_girl.set(property, value)
	if _character:
		ResourceSaver.save(_character)
	setup(_girl)
	return true

## Her After Hours properties in EDITED_GROUPS, group headers included.
func _edited_properties() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var group := ""
	for property in _girl.get_property_list():
		if property.usage & PROPERTY_USAGE_GROUP:
			group = property.name
			if group in EDITED_GROUPS:
				out.append(property)
		elif group in EDITED_GROUPS and property.usage & PROPERTY_USAGE_EDITOR:
			out.append(property)
	return out

func _is_edited(property: StringName) -> bool:
	for shown in _edited_properties():
		if shown.name == property and not shown.usage & PROPERTY_USAGE_GROUP:
			return true
	return false

## In the editor: redraw the preview when her After Hours is edited anywhere.
func _process(_delta: float) -> void:
	if not Engine.is_editor_hint() or _girl == null:
		return
	var state := var_to_str(_edited_properties().map(func(p: Dictionary) -> Variant: return _girl.get(p.name)))
	if state != _preview_state:
		_preview_state = state
		setup(_girl)

## Builds her (again, if she was already built).
func setup(girl: AfterHoursGirl) -> void:
	var someone_else := girl != _girl
	_girl = girl
	for node in [_body, _shadow, _belly] + _legs:
		if node:
			node.queue_free()
	_body = null
	_shadow = null
	_legs.clear()
	_shins.clear()
	_shin_base.clear()
	_halves.clear()
	_butts.clear()
	_marks = [0.0, 0.0]
	_half_base.clear()
	_holes.clear()
	_hole_base.clear()
	_insides.clear()
	_creams.clear()
	_materials.clear()
	_tail = null
	_futa = null
	_futa_sprite = null
	_belly = null
	if someone_else:
		notify_property_list_changed() # "Her Body" shows the new girl
	if girl == null:
		return
	_rig = JSON.parse_string(FileAccess.get_file_as_string(PARTS_DIR + "rig.json"))
	_px = _rig.scale
	var skin := _material(girl.skin_ramp, girl.flesh_ramp)
	var hair := _material(girl.hair_ramp if girl.hair_ramp else girl.skin_ramp, girl.flesh_ramp)
	# Back to front, as fapwall layers them: shadow, legs, then her butt.
	_shadow = _sprite("shadow", "1", null, self)
	_shadow.position = _pos("shadow")
	_build_legs(skin)
	_build_belly(skin)
	_body = Node2D.new()
	add_child(_body)
	var back := _node(_body, _pos("back"))
	_sprite("back", _skin_key(0), skin, back)
	_sprite("outfit_back", _outfit_key(girl.outfit, 0), null, back, girl.clothes_tint)
	for side in 2:
		_build_half(side, skin)
	# Closed holes and the tail, the futa, then the insides and the open lips'
	# back copies; the penis; the front copies and the cum states on top.
	_build_hole_state(Hole.PUSSY, "closed", "pussy", skin, hair)
	if girl.tail_type > 1:
		var tail_skin := _material(girl.tail_ramp, girl.flesh_ramp) if girl.tail_ramp else skin
		_tail = _sprite("tail", str(girl.tail_type), tail_skin, _body)
		_tail.position = _pos("tail")
		_tail.scale = Vector2.ONE * girl.tail_scale
	_build_hole_state(Hole.ANUS, "closed", "anus", skin, hair)
	if has_penis():
		_futa = _node(_body, _pos("futa"))
		var futa_skin := skin.duplicate() as ShaderMaterial # it bends on its own
		_materials.append(futa_skin)
		futa_skin.set_shader_parameter("bend_pad", BEND_PAD)
		futa_skin.set_shader_parameter("base_at_top", true)
		_futa_sprite = _sprite("futa", _hole_key("futa", girl.futa_type), futa_skin, _futa, Color.WHITE, true)
		_bend_rect(_futa_sprite)
		_futa_bend = Vector2.ZERO
		_futa_last_tip = Vector2.INF
	for h: Hole in HOLE_PARTS:
		var part: String = HOLE_PARTS[h]
		_insides[h] = _sprite(part + "_hole", "1", skin, _body)
		_insides[h].position = _pos(part + "_hole")
		_entrance[h] = _insides[h].position
		_build_hole_state(h, "back", part + "_open", skin, hair)
	_penis_clip = Polygon2D.new()
	_penis_clip.clip_children = CanvasItem.CLIP_CHILDREN_ONLY
	_body.add_child(_penis_clip)
	_penis_material = _material(penis_skin, penis_flesh)
	_penis_material.set_shader_parameter("coat_color", coat_color)
	if Engine.is_editor_hint():
		coat = preview_coat
	_penis_material.set_shader_parameter("coat", coat)
	_penis_material.set_shader_parameter("bend_pad", BEND_PAD)
	_penis = _sprite("penis", str(penis_type), _penis_material, _penis_clip)
	for h: Hole in [Hole.ANUS, Hole.PUSSY]:
		_build_hole_state(h, "front", HOLE_PARTS[h] + "_open", skin, hair)
		_build_hole_state(h, "cum", HOLE_PARTS[h] + "_cum", skin, hair)
	_set_uniform("shine", shine)
	_apply_size()
	_update_holes()
	_update_penis()

## One butt half (the right one is the left mirrored, 1 px off centre like
## fapwall): her skin, then outfit, the over layer, and the cum
## that runs down it.
func _build_half(side: int, skin: ShaderMaterial) -> void:
	var pos := _pos("butt")
	var half := _node(_body, Vector2(pos.x if side == 0 else -pos.x + 0.6, pos.y))
	half.scale.x = 1.0 if side == 0 else -1.0
	var butt_skin := skin.duplicate() as ShaderMaterial
	_materials.append(butt_skin)
	var butt := _sprite("butt", _skin_key(side), butt_skin, half)
	_butts.append(butt)
	if butt.texture:
		# The cheek's middle: the middle of its art, nudged out and up.
		var middle := butt.offset + butt.texture.get_size() / 2.0 + Vector2(-8.0, -8.0)
		butt_skin.set_shader_parameter("cheek_center", middle)
	var tint := _girl.clothes_tint
	_sprite("outfit_butt", _outfit_key(_girl.outfit, side), null, half, tint)
	_sprite("over", _frame_key(_girl.over), null, half, tint)
	for cream: String in ["cream_butt_pussy", "cream_butt_anus"]:
		var drip := _sprite(cream, "1", null, half)
		drip.visible = false
		drip.set_meta("hole", Hole.PUSSY if cream == "cream_butt_pussy" else Hole.ANUS)
		drip.set_meta("side", side)
		_creams.append(drip)
	_halves.append(half)
	_half_base.append(half.position)

## One of a hole's looks (closed, open back/front, with cum): a container
## where fapwall puts it, the hole art, her pubic hair, and the cum on top.
func _build_hole_state(h: Hole, state: String, part: String, skin: ShaderMaterial, hair: ShaderMaterial) -> void:
	var holder := _node(_body, _pos(part))
	holder.scale.y = -1.0 if _rig.parts[part].flip_y else 1.0
	var type := _girl.pussy_type if h == Hole.PUSSY else _girl.anus_type
	_sprite(part, _hole_key(part, type), skin, holder, Color.WHITE, true)
	var hair_style := _girl.pubic_hair if h == Hole.PUSSY else _girl.anal_hair
	if hair_style > 0:
		var tag := "" if state == "closed" else ("_cum" if state == "cum" else "_open")
		if h == Hole.PUSSY:
			for layer: String in ["_bot", "_top"]:
				_sprite("hair_pussy" + tag + layer, str(hair_style), hair, holder, Color.WHITE, true)
		else:
			_sprite("hair_anus" + tag, str(hair_style), hair, holder, Color.WHITE, true)
	if state == "cum":
		_sprite("cream_pussy" if h == Hole.PUSSY else "cream_anus", "1", null, holder, Color.WHITE, true)
	if not _holes.has(h):
		_holes[h] = {}
	_holes[h][state] = holder
	_hole_base[holder] = holder.position

## Her belly, in her skin, hanging from its top middle.
func _build_belly(skin: ShaderMaterial) -> void:
	_belly = Sprite2D.new()
	_belly.texture = BELLY
	_belly.hframes = BELLY_COLUMNS
	_belly.vframes = ceili(float(BELLY_FRAMES) / BELLY_COLUMNS)
	_belly.material = skin
	_belly.centered = false
	_belly.offset = Vector2(-BELLY.get_width() / BELLY_COLUMNS / 2.0, 0)
	add_child(_belly)
	_bulge = preview_bulge if Engine.is_editor_hint() else 0.0

## The belly follows her butt (its size, its shove) and shows the frame for
## how bulged she is; a stroke's kick stretches it down for a moment.
func _place_belly(breathing: Vector2) -> void:
	if _belly == null:
		return
	var bulged := clampf(_bulge, 0.0, 1.0)
	_belly.frame = roundi(bulged * (BELLY_FRAMES - 1))
	_belly.position = _body.position + (belly_pos + _girl.belly_offset + Vector2(0, bulge_drop * bulged)) * _body.scale
	var kick := clampf(_bulge_velocity * 0.05, -1.0, 1.0) * bulge_bounce * bulged
	_belly.scale = _girl.belly_size * _girl.butt_size * breathing * Vector2(1.0 - kick * 0.5, 1.0 + kick)

## How bulged the penis makes her right now: only in her anus, from
## bulge_from to the deepest, times how thick it is and how much she bulges.
func _bulge_target() -> float:
	if not inserted or hole != Hole.ANUS or _girl.bulge <= 0.0 or not (Engine.is_editor_hint() or Settings.bulge):
		return 0.0
	var deep := clampf((depth - bulge_from) / maxf(max_depth() - bulge_from, 0.25), 0.0, 1.0)
	var girth := clampf(_shaft_width() / bulge_girth, 0.5, 1.6)
	return deep * girth * _girl.bulge

func _build_legs(skin: ShaderMaterial) -> void:
	var legs: Dictionary = _rig.legs
	var pose: Dictionary = legs.poses[clampi(_girl.leg_pose, 1, legs.poses.size()) - 1]
	var tint := _girl.clothes_tint
	for side in 2:
		var leg := Node2D.new()
		add_child(leg)
		var thigh := _node(leg, Vector2.ZERO)
		thigh.transform = _matrix(pose.thigh)
		_sprite("thigh", _skin_key(side), skin, thigh, Color.WHITE, true)
		_sprite("outfit_thigh", _outfit_key(_girl.outfit, side), null, thigh, tint, true)
		var shin := _node(leg, Vector2.ZERO)
		shin.transform = _matrix(pose.shin)
		_sprite("shin", _skin_key(side), skin, shin, Color.WHITE, true)
		_sprite("foot", _skin_key(side), skin, shin, Color.WHITE, true)
		_sprite("outfit_shin", _outfit_key(_girl.outfit, side), null, shin, tint, true)
		_legs.append(leg)
		_shins.append(shin)
		_shin_base.append(shin.transform)

func _physics_process(delta: float) -> void:
	if _body == null or Engine.is_editor_hint():
		return
	_time += delta
	# How fast it moves, as her body feels it: past fapwall's depth the extra
	# length counts for little (a long deep stroke isn't a harder one).
	var felt := minf(depth, 1.0) + maxf(depth - 1.0, 0.0) * 0.15
	_depth_speed = (felt - _prev_depth) / delta if inserted else 0.0
	_prev_depth = felt
	_update_stroke()
	_update_springs(delta)
	_update_facing(delta)
	_update_holes()
	_update_penis()
	_update_bends(delta)
	_flinch = move_toward(_flinch, 0.0, delta * 2.5)
	_update_marks(delta)
	_bulge_velocity += ((_bulge_target() - _bulge) * 90.0 - _bulge_velocity * 9.0) * delta
	_bulge = maxf(_bulge + _bulge_velocity * delta, 0.0)
	_update_feel(delta)
	# A flinch tenses everything up; the penis shoves her forward (up) and
	# she rocks back.
	var shaking := maxf(_flinch, forcing * 0.8)
	_body.position = Vector2(sin(_time * 40.0) * shaking * 2.0, _push)
	_apply_size()

## The tip moved from from to to (her butt's space) while out. pushing: the
## mouse button is held; without it the tip just glides. Pushing, crossing
## an entrance the way in (or starting to push right on it) starts pressing
## on it; pushing on PRESS_DEPTH past it pops it in. Letting go, backing off
## out of it or sliding off sideways lets go. Returns the hole it popped
## into this time, or -1.
func push(from: Vector2, to: Vector2, delta: float, pushing: bool) -> int:
	var speed := from.distance_to(to) / maxf(delta, 0.001)
	var started := pushing and not _pushing
	_pushing = pushing
	forcing = 0.0
	if _blocked >= 0:
		var at_blocked: Vector2 = _entrance[_blocked]
		var lined_up := absf(to.x - at_blocked.x) <= entry_half_width * 1.5
		if _past(_blocked, to) < 0.0:
			_blocked = -1
		elif _refused and lined_up and pushing and can_force:
			forcing = clampf(_past(_blocked, to) / (FORCE_DEPTH * _px), 0.0, 1.0)
			if forcing >= 1.0:
				# Pushed hard past her no.
				var taken := _blocked
				_blocked = -1
				_refused = false
				forcing = 0.0
				insert(taken as Hole)
				_pop_kick(1.2)
				forced.emit(taken)
				return taken
	if not pushing:
		pressing = -1
		press = 0.0
		return -1
	if pressing < 0:
		var crossed := _crossed_hole(from, to, started)
		if crossed < 0 or crossed == _blocked:
			return -1
		pressing = crossed
		press = 0.0
		press_started.emit(crossed)
		if pressing < 0:
			return -1 # refused
	var at: Vector2 = _entrance[pressing]
	if _past(pressing, to) < 0.0 or absf(to.x - at.x) > entry_half_width * 1.5:
		pressing = -1
		press = 0.0
		return -1
	if speed > jab_speed:
		# Too fast: it skids off the closed hole.
		var missed := pressing
		_blocked = missed
		_refused = false
		pressing = -1
		press = 0.0
		_flinch = maxf(_flinch, 0.4)
		for i in 2:
			_spring_velocity[i] += Vector2((i * 2 - 1) * 30.0, -50.0) * bounce
		bounced.emit(missed)
		return -1
	press = clampf(_past(pressing, to) / _press_depth(pressing), 0.0, 1.0)
	if press < 1.0:
		return -1
	var opened := pressing
	pressing = -1
	press = 0.0
	insert(opened as Hole)
	var strength := clampf(speed / 500.0, 0.4, 1.2)
	_pop_kick(strength)
	popped.emit(opened, strength)
	return opened

## How far the tip pushes on a closed hole before it pops: tighter for the
## anus, easier the wetter she is.
func _press_depth(h: int) -> float:
	return PRESS_DEPTH[h] * _px * (1.0 - WET_EASE * shine)

## The pop: the lips overshoot and wobble, the penis jumps in, she jolts.
func _pop_kick(strength: float) -> void:
	var power := strength * pop_strength
	_pop_velocity += 16.0 * power
	_push_velocity -= 90.0 * power * bounce
	_flinch = maxf(_flinch, 0.5 * power)
	for i in 2:
		_spring_velocity[i] += Vector2((i * 2 - 1) * 50.0, -130.0) * power * bounce
		_leg_velocity[i] += 4.0 * power
	_tail_velocity += 8.0 * power

## A stroke landed: power ~0.5 (off her pace) .. 1.5 (on it). The near cheek
## takes it first, the other a beat later; she flattens for a moment.
func impact(power: float) -> void:
	var hit := power * bounce
	_impact = minf(_impact + 0.6 * hit, 1.2)
	_push_velocity -= 20.0 * hit
	var first := randi() % 2
	for i in 2:
		var velocity := Vector2((i * 2 - 1) * kick * 0.3, -kick) * hit
		_kicks.append([0.0 if i == first else 0.06, i, velocity])
		_leg_velocity[i] += leg_kick * hit
	_tail_velocity += 5.0 * hit
	if _bulge > 0.05:
		_bulge_velocity += 3.0 * hit # the bump jumps with each stroke

func _update_feel(delta: float) -> void:
	# The pop's overshoot.
	_pop_velocity += (-_pop * 220.0 - _pop_velocity * 9.0) * delta
	_pop += _pop_velocity * delta
	# Her body follows the penis (shoved forward = up on screen) and rocks back.
	# Past fapwall's depth it keeps shoving her, a bit less per pixel.
	var shove := depth if depth <= 1.0 else 1.0 + (depth - 1.0) * 0.12
	var target := -shove * follow if inserted else 0.0
	_push_velocity += ((target - _push) * 260.0 - _push_velocity * 12.0) * delta
	if inserted and _depth_speed < 0.0:
		# A tight hole clings on the way out and tugs her back.
		_push_velocity += -_depth_speed * 40.0 * GRIP[hole] * grip_strength * bounce * delta
	_push = clampf(_push + _push_velocity * delta, -6.0, 3.0)
	# The lips drag with the penis: in on the in-stroke, out on the out-stroke.
	var dragging := clampf(_depth_speed / 8.0, -1.0, 1.0) if inserted else 0.0
	_drag_velocity += ((dragging - _drag) * 300.0 - _drag_velocity * 18.0) * delta
	_drag += _drag_velocity * delta
	_impact = move_toward(_impact, 0.0, delta * 4.0)
	# Her legs ease open while it's in her and stay open; each stroke nudges them.
	var spread_to := (leg_spread * (0.6 + 0.4 * arousal) + minf(depth, 1.0) * leg_pulse) if inserted else 0.0
	_spread_velocity += ((spread_to - _spread) * 40.0 - _spread_velocity * 12.0) * delta
	_spread += _spread_velocity * delta
	# The hole wobbling shut.
	_shut_velocity += (-_shut * 260.0 - _shut_velocity * 10.0) * delta
	_shut += _shut_velocity * delta
	# Kicks waiting to land (the second cheek's).
	for kick_left in _kicks.duplicate():
		kick_left[0] -= delta
		if kick_left[0] <= 0.0:
			_spring_velocity[kick_left[1]] += kick_left[2]
			_kicks.erase(kick_left)

## Refuse the hole being pressed on: let go of it until the tip backs off.
func block() -> void:
	_blocked = pressing
	_refused = true
	pressing = -1
	press = 0.0

## Came inside: the hole shows its cum, and it runs down one butt half, then
## the other.
func cum_inside(h: Hole) -> void:
	_filled[h] = true
	for side in 2:
		get_tree().create_timer(0.7 + side * 0.7).timeout.connect(_show_cream.bind(h, side))

## Pulled out: it lands on both halves.
func cum_outside() -> void:
	for drip in _creams:
		drip.visible = true

func _show_cream(h: Hole, side: int) -> void:
	for drip in _creams:
		if is_instance_valid(drip) and drip.get_meta("hole") == h and drip.get_meta("side") == side:
			drip.visible = true

## Size and breathing (the butt and shadow breathe, the legs don't), and the
## legs' own size, place and angle.
func _apply_size() -> void:
	var size := _girl.butt_size
	var breath := (sin(_time * TAU / breath_period) + 1.0) / 2.0 if not Engine.is_editor_hint() else 0.0
	var breathing := Vector2(1.0 - 0.01 * breath, 1.0 + 0.025 * breath)
	breathing *= Vector2(1.0 + 0.05 * _impact, 1.0 - 0.07 * _impact) # flattened by a stroke
	_body.scale = size * breathing
	_shadow.scale = size * breathing
	_place_belly(breathing)
	var legs: Dictionary = _rig.legs
	var x: float = legs.pos[0] + _girl.legs_offset.x
	var y: float = legs.pos[1] + _girl.legs_offset.y
	for side in 2:
		# The right leg is the left one mirrored, 1 px off centre like the butt.
		# leg_angle swings both feet in toward the middle.
		_legs[side].position = Vector2(x if side == 0 else -x + 0.6, y)
		_legs[side].scale = Vector2(_girl.legs_size.x * (1.0 if side == 0 else -1.0), _girl.legs_size.y)
		# Strokes swing the thighs out (and the knees bend); close to the end
		# they tremble. Both in the leg's own (mirrored) space, so the two match.
		var tremble := sin(_time * 37.0 + side * 1.7) * leg_tremble * maxf(smoothstep(0.6, 1.0, arousal), forcing * 1.5)
		_legs[side].rotation = (deg_to_rad(_girl.leg_angle - _spread) - _leg_swing[side] * 0.1 - tremble) * (-1.0 if side == 0 else 1.0)
		_shins[side].transform = _shin_base[side] * Transform2D(_leg_swing[side] * 0.15 + tremble * 2.0, Vector2.ZERO)

func _rebuild_preview() -> void:
	if Engine.is_editor_hint() and _body:
		setup(_girl)

## A point in rig space (the mouse) in her butt's own space, where the holes
## are: the butt is scaled by her size and breathing.
func to_body(point: Vector2) -> Vector2:
	return _body.transform.affine_inverse() * point

## Her butt's transform in rig space (its springs, breathing and size), for
## things that ride on her (SweatDrops).
func body_transform() -> Transform2D:
	return _body.transform if _body else Transform2D.IDENTITY

## The other way: a point in her butt's space (a hole) in rig space.
func from_body(point: Vector2) -> Vector2:
	return _body.transform * point

## The depth after one frame of heading for target: a tight hole lags
## behind the mouse (the anus more), less as she gets wet.
func grip_follow(target: float, delta: float) -> float:
	var grip := clampf(GRIP[hole] * grip_strength * (1.0 - 0.5 * shine), 0.0, 1.0)
	return lerpf(depth, target, 1.0 - exp(-lerpf(30.0, 5.0, grip) * delta))

## Mouse position (her butt's space, the tip where the mouse is) to depth while inside.
func depth_for(tip: Vector2) -> float:
	var pushed := (_past(hole, tip) - _press_depth(hole)) / stroke_length
	if pushed > 1.0:
		# Past fapwall's depth: deep_gain pixels of penis per pixel of mouse.
		pushed = 1.0 + (pushed - 1.0) * stroke_length * deep_gain / ((TIP_DEEP - TIP_SHALLOW) * _px)
	return clampf(pushed, 0.0, max_depth())

## The deepest depth can go: 1 (fapwall's) up to the whole penis (reach),
## leaving its base end at the entrance.
func max_depth() -> float:
	if _penis == null or _penis.texture == null:
		return 1.0
	var length := _penis.texture.get_size().y / _px * (1.0 - base_out) # some of it stays out
	var whole := (length - TIP_SHALLOW) / (TIP_DEEP - TIP_SHALLOW)
	return maxf(1.0, lerpf(1.0, whole, reach))

## The tip (her butt's space) has backed out of the hole it's in, past margin.
func is_out(tip: Vector2, margin: float) -> bool:
	return _past(hole, tip) < -margin

## How far point is past h's entrance the way in (negative = still outside).
func _past(h: int, point: Vector2) -> float:
	return (point.y - _entrance[h].y) * ENTRY_DIR[h]

func entrance(h: Hole) -> Vector2:
	return _entrance[h]

func insert(h: Hole) -> void:
	hole = h
	inserted = true
	depth = 0.0

func pull_out() -> void:
	if inserted:
		# It snaps shut with a wobble; faster out, bigger wobble.
		_shut_hole = hole
		pulled_out.emit(hole)
		_shut_velocity += (7.0 + clampf(-_depth_speed, 0.0, 8.0)) * shut_bounce
	inserted = false
	depth = 0.0
	pressing = -1
	press = 0.0
	aim = _entrance[hole] - Vector2(0, 6.0 * ENTRY_DIR[hole])
	# It flops as it comes free.
	_bend.y += (1.0 if randf() < 0.5 else -1.0) * 70.0 * sway
	_last_tip = Vector2.INF

## She has her own penis (futa): her pussy is behind it and can't be used.
## In the game the player's settings can take it away (futa off, or anal off:
## then her pussy is back, there has to be a way in).
func has_penis() -> bool:
	if _girl == null or _girl.futa_type <= 0:
		return false
	return Engine.is_editor_hint() or (Settings.futa and Settings.anal != 2)

## One spurt of her penis (she's cumming): it kicks, stretches long and
## thin, then bounces back. power: about 0.3..1.
func futa_spurt(power: float) -> void:
	_futa_twitch_velocity += 9.0 * power
	_futa_pump_velocity += 14.0 * power

## Where her penis's tip is, in rig space (for drips).
func futa_tip() -> Vector2:
	if _futa_sprite == null or _futa_sprite.texture == null:
		return Vector2.ZERO
	var tip := Vector2(0, _futa_sprite.offset.y + _futa_sprite.texture.get_size().y - 4.0)
	return to_local(_futa_sprite.to_global(tip))

## Shows or hides the penis (hidden while she jumps into view).
func show_penis(shown: bool) -> void:
	if _penis_clip:
		_penis_clip.visible = shown

## Wrong move: she tenses and shivers.
func flinch() -> void:
	_flinch = 1.0
	for i in 2:
		_spring_velocity[i] += Vector2(randf_range(-40.0, 40.0), -60.0)
		_leg_velocity[i] += randf_range(2.0, 4.0)
	_tail_velocity += 6.0

## A slap on one butt half (0 left, 1 right): it ripples hard, the other a
## little, she tenses up for a moment, and that cheek gets redder (red
## enough, a "#" of welts shows).
func slap(side: int) -> void:
	if show_marks and side < _butts.size():
		_marks[side] = minf(_marks[side] + mark_per_slap, 1.0)
	_spring_velocity[side] += Vector2((side * 2 - 1) * 70.0, -180.0) * bounce
	_spring_velocity[1 - side] += Vector2((side * 2 - 1) * 15.0, -45.0) * bounce
	_leg_velocity[side] += 3.0
	_tail_velocity += 7.0
	_flinch = maxf(_flinch, 0.3)

## The redness calms down slowly; the "#" of welts shows while the cheek is
## red enough.
func _update_marks(delta: float) -> void:
	for side in _butts.size():
		_marks[side] = move_toward(_marks[side], 0.0, delta / mark_fade)
		var mat := _butts[side].material as ShaderMaterial
		mat.set_shader_parameter("cheek_red", _marks[side])
		mat.set_shader_parameter("hurt", smoothstep(hurt_at, hurt_at + 0.15, _marks[side]))

## Where a slap lands on a butt half (0 left, 1 right), in her butt's space.
func cheek(side: int) -> Vector2:
	return _half_base[side] + Vector2(12.0 if side == 0 else -12.0, -18.0)

## The point (her butt's space) is on one of her butt halves, roughly.
func on_butt(point: Vector2) -> bool:
	for side in 2:
		if point.distance_to(_half_base[side]) < 64.0:
			return true
	return false

## The point (her butt's space) is near a hole's entrance, where a click is
## a push, not a slap.
func near_hole(point: Vector2) -> bool:
	for h: int in _entrance:
		if point.distance_to(_entrance[h]) < entry_half_width * 3.0:
			return true
	return false

## Climax: a big squeeze and shudder.
func climax() -> void:
	_flinch = 0.6
	for i in 2:
		_spring_velocity[i] += Vector2((i * 2 - 1) * 90.0, -220.0)
		_leg_velocity[i] += 6.0
	_tail_velocity += 10.0

## The hole whose entrance the tip crossed the way in, going from from to
## to, or -1. started: pushing just began, so a tip already resting on an
## entrance (not yet PRESS_DEPTH past it) counts too. Only a hole the penis
## is facing (done turning) counts, and a futa girl's pussy is behind her penis.
func _crossed_hole(from: Vector2, to: Vector2, started: bool) -> int:
	for h: Hole in _entrance:
		if h == Hole.PUSSY and has_penis():
			continue # behind her penis
		var facing := _facing > 0.9 if ENTRY_DIR[h] > 0.0 else _facing < 0.1
		var at: Vector2 = _entrance[h]
		var came_in := _past(h, from) <= 0.0 or (started and _past(h, from) < _press_depth(h))
		if facing and absf(to.x - at.x) <= entry_half_width and came_in and _past(h, to) > 0.0:
			return h
	return -1

## Out of her, the penis turns to face the nearer hole: tip down above the
## middle between them (the anus), tip up below it (the pussy), once it's
## turn_margin past the middle. While pushing it keeps facing the way it was.
func _update_facing(delta: float) -> void:
	var target: int = hole if inserted else pressing
	if target < 0:
		var middle: float = (_entrance[Hole.PUSSY].y + _entrance[Hole.ANUS].y) / 2.0
		if has_penis():
			target = Hole.ANUS
		elif _pushing:
			target = _facing_hole
		elif aim.y < middle - turn_margin:
			target = Hole.ANUS
		elif aim.y > middle + turn_margin:
			target = Hole.PUSSY
		else:
			target = _facing_hole
	_facing_hole = target as Hole
	_facing = move_toward(_facing, 1.0 if target == Hole.ANUS else 0.0, delta * turn_speed)

func _update_stroke() -> void:
	var deep := inserted and depth >= deep_at
	if deep and not _was_deep and _depth_speed > 0.0:
		# The scene says how hard it lands (impact()), on her pace or not.
		thrust.emit(clampf(_depth_speed / 6.0, 0.2, 1.0))
	_was_deep = deep
	_track_shallow()

## One that turned back short of deep_at is a shallow stroke.
func _track_shallow() -> void:
	if not inserted:
		_going_in = false
		_stroke_peak = 0.0
		_stroke_from = 0.0
		return
	if _going_in:
		_stroke_peak = maxf(_stroke_peak, depth)
		if depth < _stroke_peak - STROKE_TURN:
			_going_in = false
			var length := _stroke_peak - _stroke_from
			if _stroke_peak < deep_at and length >= shallow_min:
				shallow.emit(length)
			_stroke_from = depth
	else:
		_stroke_from = minf(_stroke_from, depth)
		if depth > _stroke_from + STROKE_TURN:
			_going_in = true
			_stroke_peak = depth

func _update_springs(delta: float) -> void:
	var moved := _depth_speed * delta # this frame's stroke (0 while out)
	for i in 2:
		var force := -_spring[i] * _girl.butt_stiffness - _spring_velocity[i] * _girl.butt_damping
		_spring_velocity[i] += force * delta
		# Every bit of the stroke pushes the cheeks (in: up and out; out: they
		# fall back), not only the deep end.
		_spring_velocity[i] += Vector2((i * 2 - 1) * 0.3, -1.0) * moved * stroke_push * bounce
		_spring[i] += _spring_velocity[i] * delta
		_spring[i] = _spring[i].limit_length(7.0)
		# Squash when pushed up, stretch when falling back (volume stays about the same).
		var squash := clampf(-_spring[i].y * 0.012, -0.14, 0.14)
		# Clenching against a forced push: the cheeks pull together.
		var clench := Vector2((1.0 if i == 0 else -1.0) * forcing * 4.0, 0.0)
		_halves[i].position = _half_base[i] + _spring[i] + clench
		_halves[i].scale = Vector2((1.0 + squash) * (-1.0 if i == 1 else 1.0), 1.0 - squash)
	for i in 2:
		var force := -_leg_swing[i] * 90.0 - _leg_velocity[i] * 8.0
		_leg_velocity[i] += force * delta
		_leg_swing[i] = clampf(_leg_swing[i] + _leg_velocity[i] * delta, -1.0, 1.0)
	if _tail:
		var force := -_tail_angle * 60.0 - _tail_velocity * 4.0
		_tail_velocity += force * delta
		_tail_angle += _tail_velocity * delta
		_tail.rotation = _tail_angle * 0.12 + sin(_time * 1.3) * 0.04
	if _futa:
		# Her penis swings with the butt.
		_futa_twitch_velocity += (-_futa_twitch * 300.0 - _futa_twitch_velocity * 9.0) * delta
		_futa_twitch += _futa_twitch_velocity * delta
		_futa.rotation = (_spring[0].x - _spring[1].x) * 0.01 + _spring[0].y * 0.008 + _futa_twitch * 0.15
		_futa_pump_velocity += (-_futa_pump * 280.0 - _futa_pump_velocity * 8.0) * delta
		_futa_pump += _futa_pump_velocity * delta
		_futa.scale = Vector2(1.0 - 0.12 * _futa_pump, 1.0 + 0.22 * _futa_pump)

func _update_holes() -> void:
	for h: Hole in _holes:
		var states: Dictionary = _holes[h]
		var feel: Dictionary = FEEL[h]
		var open := inserted and h == hole
		var filled: bool = _filled.get(h, false)
		# Shown or hidden outright, the way fapwall swaps them.
		states.closed.visible = not open and not filled
		states.cum.visible = not open and filled
		states.back.visible = open
		states.front.visible = open
		_insides[h].visible = open
		if open:
			# FEEL's scales include fapwall's flips.
			var front: Array = feel.front
			var back: Array = feel.back
			var back_y: Array = feel.back_y
			# The pop's overshoot widens them; the drag pulls them along.
			var stretched := Vector2(1.0 + _pop * 0.3 + maxf(_drag, 0.0) * 0.06, 1.0 + _pop * 0.15)
			var stretch := minf(depth, 1.0) # past fapwall's depth the lips stay as wide
			# A penis wider than the hole stretches it round the shaft.
			stretched.x *= _fit_width(h)
			states.front.scale = front[0].lerp(front[1], stretch) * stretched
			states.back.scale = back[0].lerp(back[1], stretch) * stretched
			_insides[h].scale = Vector2(stretched.x, 1.0)
			# A tighter hole drags further with the penis (the anus clings).
			var dragged: float = _drag * 3.0 * float(ENTRY_DIR[h]) * (1.0 + float(GRIP[h]) * grip_strength)
			states.back.position = _hole_base[states.back] + Vector2(0, (lerpf(back_y[0], back_y[1], stretch) + dragged) * _px)
			states.front.position = _hole_base[states.front] + Vector2(0, dragged * 0.4 * _px)
		else:
			var squash := press if h == pressing else 0.0
			var strain := forcing if h == _blocked else 0.0
			var closed: Node2D = states.closed
			# Just pulled out of: it wobbles (wide and flat, then tall, then still).
			var wobble := Vector2(1.0 + _shut * 0.25, 1.0 - _shut * 0.15) if h == _shut_hole else Vector2.ONE
			closed.scale = Vector2.ONE.lerp(feel.squash, squash) * wobble
			closed.position = _hole_base[closed] + Vector2(0, feel.nudge * squash * _px)
			if strain > 0.0:
				# Forced: it squashes past a normal press and trembles harder the further it's pushed.
				var shiver := sin(_time * 55.0) * 0.04 * strain
				closed.scale = Vector2.ONE.lerp(feel.squash * Vector2(1.15, 0.85), strain) + Vector2(shiver, -shiver)
				closed.position = _hole_base[closed] + Vector2(sin(_time * 47.0) * strain, feel.nudge * 1.3 * strain * _px)
			var cum: Node2D = states.cum
			cum.scale = Vector2(1.0, -1.0 if _rig.parts[HOLE_PARTS[h] + "_cum"].flip_y else 1.0) * wobble

func _update_penis() -> void:
	# The penis sits inside her butt (between the lips' layers) but isn't
	# hers: undo her butt's size on it. Points below are in her butt's space
	# (where the holes are) and go through _to_clip.
	_penis_clip.scale = Vector2.ONE / _body.scale
	# Tip down it's fapwall's other penis art, mirrored top to bottom: a half
	# turn plus a sideways flip.
	var from_above := _facing > 0.5
	_set_variant(_penis, "penis_back" if from_above else "penis", str(penis_type))
	_bend_rect(_penis)
	_penis.rotation = PI * _facing
	var flip := -1.0 if from_above else 1.0
	_penis.scale = Vector2(flip, 1.0)
	var tip_y := _penis.offset.y
	if inserted:
		# Inside: only the shaft outside her shows.
		var at: Vector2 = _entrance[hole]
		var way_in: float = ENTRY_DIR[hole]
		var in_deep := clampf(depth + _pop * 0.25, 0.0, max_depth()) # the pop shoves it in deeper for a moment
		_place_penis(Vector2(at.x, at.y + way_in * lerpf(TIP_SHALLOW, TIP_DEEP, in_deep) * _px), tip_y)
		_clip_inside(at.y + way_in * SHOW_PAST[hole] * _px, way_in)
	elif forcing > 0.0:
		# Forcing a refused hole: the tip pressed on it (drawn over it), the
		# penis squashed shorter and wider the harder it's pushed.
		var jammed: Vector2 = _entrance[_blocked]
		_penis.scale = Vector2(flip * (1.0 + 0.15 * forcing), 1.0 - 0.3 * forcing)
		_place_penis(Vector2(jammed.x, jammed.y + float(ENTRY_DIR[_blocked]) * 2.0 * forcing * _px), tip_y)
		_clip_inside(0.0, 0.0)
	elif pressing >= 0:
		# Pushing on the closed hole: lined up on it and drawn over it, the
		# way fapwall does it. It only goes inside once the hole pops open.
		var pressed: Vector2 = _entrance[pressing]
		_place_penis(Vector2(pressed.x, aim.y), tip_y)
		_clip_inside(0.0, 0.0)
	else:
		_place_penis(aim, tip_y)
		_clip_inside(0.0, 0.0)

## The penises bend as they move: the tip lags behind, then wobbles back.
## In a hole, or lined up on one, the partner's is held straight.
func _update_bends(delta: float) -> void:
	var tip := _body.transform * aim
	if inserted or pressing >= 0 or forcing > 0.0:
		_bend = _bend.lerp(Vector2.ZERO, 1.0 - exp(-30.0 * delta))
	elif _last_tip != Vector2.INF:
		_bend = _bend_step(_bend, tip.x - _last_tip.x, delta)
	_last_tip = tip
	_penis_material.set_shader_parameter("bend", _bend.x)
	if _futa_sprite:
		# Hers swings with her butt (see _update_springs); its tip lags that.
		var futa_tip_now := futa_tip()
		if _futa_last_tip != Vector2.INF:
			_futa_bend = _bend_step(_futa_bend, futa_tip_now.x - _futa_last_tip.x, delta)
		_futa_last_tip = futa_tip_now
		(_futa_sprite.material as ShaderMaterial).set_shader_parameter("bend", _futa_bend.x)

## One frame of a bend spring (bend, velocity), its tip having moved moved
## sideways (rig pixels): the faster it goes, the further the tip lags.
func _bend_step(spring: Vector2, moved: float, delta: float) -> Vector2:
	var lag := clampf(-moved / delta * 0.01 * sway, -BEND_MAX, BEND_MAX)
	var velocity := spring.y + ((lag - spring.x) * 220.0 - spring.y * 7.0) * delta
	return Vector2(clampf(spring.x + velocity * delta, -BEND_MAX, BEND_MAX), velocity)

## Tells a penis's material where its art is in the atlas, for the bend.
func _bend_rect(sprite: Sprite2D) -> void:
	var art := sprite.texture as AtlasTexture
	if art == null:
		return
	var size := art.atlas.get_size()
	var region := Rect2(art.region.position / size, art.region.size / size)
	(sprite.material as ShaderMaterial).set_shader_parameter("bend_rect", Vector4(region.position.x, region.position.y, region.size.x, region.size.y))

## The current penis art's usual shaft width (art pixels), worked out once
## per art: the middle of its row widths from a fifth to four fifths of the
## way down, so a wide head or base doesn't count.
func _shaft_width() -> float:
	var art := _penis.texture as AtlasTexture
	if art == null:
		return 0.0
	var key := "%s:%s" % [art.atlas.resource_path, art.region]
	if _shaft_widths.has(key):
		return _shaft_widths[key]
	var width := art.region.size.x
	var atlas_image := art.atlas.get_image()
	if atlas_image: # none to read headless
		var image := atlas_image.get_region(Rect2i(art.region))
		var widths: Array[int] = []
		for y in range(int(image.get_height() * 0.2), int(image.get_height() * 0.8)):
			var left := -1
			var right := -1
			for x in image.get_width():
				if image.get_pixel(x, y).a > 0.5:
					if left < 0:
						left = x
					right = x
			if left >= 0:
				widths.append(right - left + 1)
		if not widths.is_empty():
			widths.sort()
			width = widths[widths.size() / 2]
	_shaft_widths[key] = width
	return width

## How much wider the open hole has to be to fit the penis (1 = it fits):
## its shaft, as wide as it is around her, over the hole's opening.
func _fit_width(h: Hole) -> float:
	var shaft := _shaft_width()
	if shaft <= 0.0 or _insides[h].texture == null:
		return 1.0
	var width := shaft / _body.scale.x # the penis doesn't take her butt's size
	return clampf(width * 1.08 / _insides[h].texture.get_width(), 1.0, 2.0)

## Puts the penis's tip at tip (her butt's space), turned the way it faces.
func _place_penis(tip: Vector2, tip_y: float) -> void:
	_penis.position = _to_clip(tip) - Vector2(0, tip_y * _penis.scale.y).rotated(_penis.rotation)

## Hides the penis past y (her butt's space) going way_in (-1 up, 1 down);
## way_in 0 shows all of it.
func _clip_inside(y: float, way_in: float) -> void:
	var line := _to_clip(Vector2(0, y)).y
	var top := -900.0 if way_in >= 0.0 else line
	var bottom := 900.0 if way_in <= 0.0 else line
	_penis_clip.polygon = PackedVector2Array([Vector2(-900, top), Vector2(900, top), Vector2(900, bottom), Vector2(-900, bottom)])

## Her butt's space to the penis holder's (which undoes her butt's size).
func _to_clip(point: Vector2) -> Vector2:
	return point * _body.scale

# Variants: which frame of each part's atlas she uses.

## Her skin detail on a body part; side 1 (right) takes fapwall's asymmetric
## pair if there is one.
func _skin_key(side: int) -> String:
	var skin := _girl.skin_detail
	if side == 1:
		skin = SKIN_RIGHT.get(skin, skin)
	return str(skin)

## A hole (or futa) type in her skin detail; the base skin's art if her skin
## has none for it.
func _hole_key(part: String, type: int) -> String:
	var key := "%d_%d" % [_girl.skin_detail, type]
	return key if _rig.parts[part].variants.has(key) else "%d_%d" % [BASE_SKIN, type]

## Outfit frame for a side (0 = none).
func _outfit_key(outfit: int, side: int) -> String:
	if side == 1:
		outfit = OUTFIT_RIGHT.get(outfit, outfit)
	return _frame_key(outfit)

## 0 or 1 = nothing (fapwall's frame 1 is empty for clothes).
func _frame_key(frame: int) -> String:
	return str(frame) if frame > 1 else ""

# Building blocks.

func _node(parent: Node, at: Vector2) -> Node2D:
	var node := Node2D.new()
	node.position = at
	parent.add_child(node)
	return node

func _pos(part: String) -> Vector2:
	var pos: Array = _rig.parts[part].pos
	return Vector2(pos[0], pos[1])

func _matrix(m: Array) -> Transform2D:
	return Transform2D(Vector2(m[0], m[1]), Vector2(m[2], m[3]), Vector2(m[4], m[5]))

## A sprite of a part's variant. in_holder: placed by the part's own matrix
## in its container (fapwall's layout); otherwise at the parent's origin.
## material null = the part keeps its own colours (clothes, cum drips).
## An empty or missing variant gives an empty sprite.
func _sprite(part: String, key: String, material: ShaderMaterial, parent: Node, tint := Color.WHITE, in_holder := false) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.centered = false
	sprite.material = material
	sprite.self_modulate = tint
	if in_holder or _rig.parts[part].space != "act":
		sprite.transform = _matrix(_rig.parts[part].matrix)
	parent.add_child(sprite)
	_set_variant(sprite, part, key)
	return sprite

func _set_variant(sprite: Sprite2D, part: String, key: String) -> void:
	var tag := part + ":" + key
	if sprite.get_meta("variant", "") == tag:
		return
	sprite.set_meta("variant", tag)
	var variant: Dictionary = _rig.parts[part].variants.get(key, {})
	if variant.is_empty():
		sprite.texture = null
		return
	if not _atlases.has(part):
		_atlases[part] = load(PARTS_DIR + part + ".png")
	var texture := AtlasTexture.new()
	texture.atlas = _atlases[part]
	var rect: Array = variant.rect
	texture.region = Rect2(rect[0], rect[1], rect[2], rect[3])
	sprite.texture = texture
	sprite.offset = Vector2(variant.offset[0], variant.offset[1])

func _material(skin_ramp: Gradient, flesh_ramp: Gradient) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = SKIN_SHADER
	mat.set_shader_parameter("skin_ramp", _ramp_texture(skin_ramp))
	mat.set_shader_parameter("flesh_ramp", _ramp_texture(flesh_ramp))
	mat.set_shader_parameter("line_color", _girl.line_color)
	mat.set_shader_parameter("cum_dark", cum_dark)
	mat.set_shader_parameter("cum_light", cum_light)
	_materials.append(mat)
	return mat

func _ramp_texture(gradient: Gradient) -> GradientTexture1D:
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	texture.width = 64
	return texture

func _set_uniform(uniform: String, value: Variant) -> void:
	for mat in _materials:
		mat.set_shader_parameter(uniform, value)

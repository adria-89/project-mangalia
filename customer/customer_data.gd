@tool
class_name CustomerData
extends Resource

## Everything that makes one customer different: art, voice, jiggle feel, lines.

@export var display_name: String = ""
@export var texture: Texture2D
## Jiggle mask (white = moves). Also used as the cut-out for what is drawn
## in front of the counter.
@export var mask: Texture2D
## White on the eye whites, black elsewhere: the only part of her still
## visible when the lights go out. Optional.
@export var eyes_mask: Texture2D
## Where her mouth is on the texture (pixels from the top-left): the tankard
## is raised to here when she drinks.
@export var mouth := Vector2(100, 110)
## Still on placeholder art: only walks in on her own with the debug
## placeholders toggle on (F1, then P).
@export var placeholder := false
## Small talk before ordering, on her first visit.
@export var lines: PackedStringArray = []
## Talk for later visits: each is its own small talk + order. They're used in
## order once, then picked at random (never the same one twice in a row).
@export var extra_sets: Array[DialogueSet] = []

@export_group("Order")
## Said last on the first visit (and on later ones whose set has no order of
## its own); stays on screen until the drink arrives.
@export var order_line: String = "A beer. Full, not foam."
## One of these is picked depending on how the drink turned out.
@export var happy_lines: PackedStringArray = ["Now THAT is a beer."]
@export var meh_lines: PackedStringArray = ["...It'll do."]
@export var angry_lines: PackedStringArray = ["Are you joking? Half of it is on the counter."]
@export var empty_line: String = "It's EMPTY."
## Coins tossed for a good / okay drink (bad drinks get nothing).
@export var tip_good: int = 3
@export var tip_meh: int = 1

@export_group("Tastes")
## What she orders most of the time. The order lines above (and in her
## dialogue sets) are for this one. Empty = the bar's default (beer).
@export var favorite: Recipe
## Now and then (sometimes_chance) she orders one of these instead.
@export var sometimes: Array[Recipe] = []
@export_range(0.0, 1.0) var sometimes_chance: float = 0.3
## Once she's this drunk (beers' worth tonight), she mostly goes for these.
@export var drunk_orders: Array[Recipe] = []
@export var drunk_from: float = 2.0
## Never orders it; served it anyway, she's furious (hated_line).
@export var hated: Recipe
@export var hated_line: String = "I would NEVER drink this."
## Drinks she won't pick when trying something new (but will drink if they're
## on her own lists above).
@export var wont_try: Array[Recipe] = []
## What she says ordering something other than her favorite, by recipe name
## (e.g. "Motorină": "Fuel me up!"). Missing ones use the recipe's own line.
@export var order_lines: Dictionary = {}
## Reactions to anything but her favorite (the happy / meh / angry lines
## above are for the favorite). {drink} becomes what she ordered.
@export var other_happy_lines: PackedStringArray = ["Now THAT is a {drink}."]
@export var other_meh_lines: PackedStringArray = ["...It'll do, for a {drink}."]
@export var other_angry_lines: PackedStringArray = ["You call this a {drink}?"]
## Served something that isn't what she ordered at all.
@export var wrong_drink_line: String = "That's not what I ordered."
## Ordered it layered, got it mixed (or in the wrong order).
@export var muddy_line: String = "It was supposed to have layers..."
## The mix is off (too much of one thing).
@export var off_mix_line: String = "Something's off with the mix."

@export_group("Affection")
## Her bar on the night card is filled with this.
@export var color := Color(0.9, 0.55, 0.65)
## Her head on the night card: this square of her texture (pixels), shrunk.
@export var head_region := Rect2(30, 0, 140, 140)
## A drawn head icon instead of the cut-out above. Optional.
@export var head_icon: Texture2D

@export_group("Lessons")
## Drinks she teaches you, by recipe name: the first time she comes in once
## one is unlocked, she orders it with these lines instead of her small talk
## (the last one is the order and stays up until the drink arrives). Until
## she has, nobody else orders it.
@export var lessons: Dictionary[String, PackedStringArray] = {}

@export_group("Voice")
## Base pitch of the dialogue tick for this character.
@export var voice_pitch: float = 1.0
## Typing speed multiplier for her lines (0.5 = half as fast).
@export var text_speed: float = 1.0

@export_group("Jiggle")
## Small / medium / large: picks the sound her chest makes when she plops
## down or slams the tankard (customer.gd > BOING_SOUNDS). The jiggle feel
## itself is the numbers below, tuned per character to match.
enum Bust { SMALL, MEDIUM, LARGE }
@export var bust: Bust = Bust.MEDIUM
@export var jiggle_stiffness: float = 140.0
@export var jiggle_damping: float = 6.0
@export var jiggle_inertia: float = 1.0
@export var jiggle_max: float = 7.0

@export_group("Faces")
## Whole-sprite expression variants: same canvas as texture, so the masks fit
## all of them. Any left empty fall back to texture.
## Eyes closed, smiling: the happy reaction and the "ahh" after a drink.
@export var face_happy: Texture2D
## Puckered lips: the lean-in for a kiss, and while the tankard is at her lips.
@export var face_kiss: Texture2D
## One eye shut: a ȘUKAR! drink, and whenever she drops her tip.
@export var face_wink: Texture2D
## Transparent overlay (same canvas) stacked on top of any face: faded in
## after a kiss and once she's finished a drink she liked. Optional.
@export var blush: Texture2D
## Transparent overlay (same canvas): sweat drops etc. for when she gets
## nervous (a broken tankard, a bad beer). The blue gloom works without it.
@export var nervous: Texture2D

@export_group("After Hours")
## Her after-hours scene: body, tastes and lines (afterhours/afterhours_girl.gd).
## Empty = she doesn't stay after closing.
@export var after_hours: AfterHoursGirl

## Her head for the night card: head_icon if there is one, else head_region
## cut out of her texture.
func head() -> Texture2D:
	if head_icon != null:
		return head_icon
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = head_region
	return atlas

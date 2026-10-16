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

@export_group("Voice")
## Base pitch of the dialogue tick for this character.
@export var voice_pitch: float = 1.0
## Typing speed multiplier for her lines (0.5 = half as fast).
@export var text_speed: float = 1.0

@export_group("Jiggle")
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
## One eye shut: a SHUKAR! drink, and whenever she drops her tip.
@export var face_wink: Texture2D
## Transparent overlay (same canvas) stacked on top of any face: faded in
## after a kiss and once she's finished a drink she liked. Optional.
@export var blush: Texture2D
## Transparent overlay (same canvas): sweat drops etc. for when she gets
## nervous (a broken tankard, a bad beer). The blue gloom works without it.
@export var nervous: Texture2D

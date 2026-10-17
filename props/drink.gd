class_name Drink
extends Resource

## One kind of drink (beer, cola, rum...): how it looks in a container and
## how it behaves when poured onto others. See container_liquid.gd.

@export var name: String = ""
## Its body, seen through the glass.
@export var color: Color = Color(0.85, 0.55, 0.12)
## Its top, seen from above when there's no head on it.
@export var surface_color: Color = Color(0.98, 0.93, 0.78)
## Lighter drinks float on heavier ones (when poured gently); heavier ones
## sink through and mix in. Only the order matters, not the units.
@export var density: float = 1.0
## How much one full glass of it gets a customer drunk (beer = 1).
@export var strength: float = 0.0

@export_group("Foam")
## How much head it builds when poured, relative to beer (1). 0 = none, like a spirit.
@export var foaminess: float = 0.0
@export var foam_color: Color = Color(1.0, 0.97, 0.88)
## Fizzy: rising bubbles in it, and it foams up when mixed with a different
## fizzy drink (beer into cola...).
@export var carbonated: bool = false
@export var fizz_color: Color = Color(1.0, 0.82, 0.45)
@export_group("")

## The stream pouring from the tap or bottle (thinner, so a bit brighter than color).
@export var stream_color: Color = Color(0.9, 0.62, 0.15)

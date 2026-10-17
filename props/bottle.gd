@tool
class_name Bottle
extends ToonProp

## A bottle on the crate (bottle_rail.gd) or the rope (rum_rope.gd): what it
## pours and how. The origin is the middle of its base; it tips around its middle.

## The bottle being held right now (one at a time), or null.
static var in_hand: Bottle

@export var drink: Drink
## Where the drink comes out, in the bottle's own space (upright).
@export var mouth := Vector3(0.0, 0.6, 0.0)
## Height of its middle, where it tips around and hangs from the mouse.
@export var grip_height: float = 0.3

@export_group("Pour")
## Tip (degrees) at which drink starts coming out (and a cap pops).
@export var pour_from_deg: float = 70.0
## Fill per second (1.0 = a full glass) when tipped all the way.
@export var pour_rate: float = 0.25
## Stream width (px) all the way tipped, and its glugs (see PourStream).
@export var stream_width: float = 5.0
@export var glug_size: float = 1.6
@export var glug_spacing: float = 34.0
@export var pitch: float = 1.0
## How many full glasses one bottle pours before it's empty.
@export var glasses: float = 2.0

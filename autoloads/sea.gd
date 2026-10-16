extends Node

## The sea under the ship. Everything that should feel the waves reads from
## here: the view and the outside rock, props drift along the counter, drinks
## lean, the tap's stream slants and customers sway.

## 0 = flat calm, 1 = a normal night, 2 = storm.
@export var strength: float = 1.0
## Peak roll of the ship at strength 1.
@export var roll_degrees: float = 3.0
## Seconds for one full roll (right, left, back).
@export var roll_period: float = 7.0
## Peak up/down movement of the ship at strength 1, in screen pixels.
@export var heave_px: float = 6.0

## Current roll in radians. Positive = the ship's right side is down.
var roll := 0.0
## How fast the roll is changing (radians per second).
var roll_velocity := 0.0
## Current up/down offset of the ship, in pixels (positive = ship is up).
var heave := 0.0

var _time := 0.0

func _physics_process(delta: float) -> void:
	_time += delta
	var t := _time * TAU / roll_period
	# A main swell plus a smaller, faster one so it never feels like a metronome.
	var new_roll := deg_to_rad(roll_degrees) * strength * (sin(t) + 0.3 * sin(t * 2.3 + 1.0))
	roll_velocity = (new_roll - roll) / delta
	roll = new_roll
	heave = heave_px * strength * sin(t * 1.3 + 0.5)

## The true "up" as seen from the ship, in the 3D layer (counter along x).
func up_3d() -> Vector3:
	return Vector3(-sin(roll), cos(roll), 0.0)

## Pull along the counter from the lean (+x = to the right), in 3D units/s².
func counter_pull() -> float:
	return 9.0 * sin(roll)

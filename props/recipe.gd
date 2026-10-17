class_name Recipe
extends Resource

## Something a customer can order: which drinks, in what proportions, how
## much of it, and whether it's layered (main.gd judges the pour against it).

@export var name: String = ""
## The drinks in it. For a layered one, bottom layer first.
@export var drinks: Array[Drink] = []
## Each drink's share, in the same order (they don't need to add up to 1).
@export var shares: PackedFloat32Array = []
## Should come out as clean layers in the order above (mixed if off).
@export var layered: bool = false
## How full it should be (1 = a full tankard; a shot is much less).
@export_range(0.05, 1.0) var fill: float = 1.0
## Night (0 = the first) from which customers can order it.
@export var unlock_night: int = 0
## What a customer says ordering it, unless she has her own line for it.
@export var order_line: String = ""

## Fraction of the recipe that is this drink.
func share(drink: Drink) -> float:
	var total := 0.0
	for s in shares:
		total += s
	var i := drinks.find(drink)
	return shares[i] / total if i >= 0 and total > 0.0 else 0.0

## How far a mix (Drink -> amount) is from this recipe: 0 = spot on, 1 =
## nothing in common.
func difference(mix: Dictionary) -> float:
	var total := 0.0
	for drink: Drink in mix:
		total += mix[drink]
	if total <= 0.0:
		return 1.0
	var off := 0.0
	for drink: Drink in mix:
		off += absf(mix[drink] / total - share(drink))
	for drink in drinks:
		if not mix.has(drink):
			off += share(drink)
	return off / 2.0

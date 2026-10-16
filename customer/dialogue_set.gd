@tool
class_name DialogueSet
extends Resource

## One visit's worth of talk: some small talk, then the order (which stays up
## until the drink arrives).

@export var lines: PackedStringArray = []
## Leave empty to use the character's default order line.
@export var order_line: String = ""

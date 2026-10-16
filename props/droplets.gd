extends Node2D

## Drips for spills and splashes, drawn in screen space. The drip texture is
## white and gets tinted with the drink's color; each drop points along the
## way it's flying.

const DRIP_TEXTURE: Texture2D = preload("res://assets/ui/particle_drip.png")
## Direction the drip in the texture is "flying" (tail toward bottom-left).
const TEXTURE_DIRECTION := Vector2(22, -24)

@export var gravity: float = 500.0
@export var lifetime: float = 0.7
## Drop size relative to the 32 px texture.
@export var min_scale: float = 0.18
@export var max_scale: float = 0.3

var _drops: Array[Dictionary] = []

## floor_y: drops vanish when they fall back below it (e.g. into the drink
## they splashed out of). size scales the drops on top of min/max_scale.
func burst(at: Vector2, color: Color, count: int, spread: float = 60.0, up: float = 60.0,
		floor_y: float = INF, size: float = 1.0) -> void:
	for i in count:
		_drops.append({
			"pos": at + Vector2(randf_range(-2.0, 2.0), 0.0),
			"vel": Vector2(randf_range(-spread, spread), randf_range(-up, 0.0)),
			"color": color,
			"scale": randf_range(min_scale, max_scale) * size,
			"life": lifetime * randf_range(0.6, 1.0),
			"floor": floor_y,
		})

func _process(delta: float) -> void:
	for drop in _drops:
		drop.vel.y += gravity * delta
		drop.pos += drop.vel * delta
		drop.life -= delta
	_drops = _drops.filter(func(d: Dictionary) -> bool:
		return d.life > 0.0 and not (d.vel.y > 0.0 and d.pos.y > d.floor))
	queue_redraw()

func _draw() -> void:
	var size := DRIP_TEXTURE.get_size()
	for drop in _drops:
		var angle: float = (drop.vel as Vector2).angle() - TEXTURE_DIRECTION.angle()
		draw_set_transform((drop.pos as Vector2).floor(), angle, Vector2.ONE * drop.scale)
		draw_texture(DRIP_TEXTURE, -size / 2.0, drop.color)
	draw_set_transform(Vector2.ZERO)

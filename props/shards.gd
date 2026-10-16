extends Node2D

## Glass shards for a broken prop, drawn in screen space: little outlined
## triangles that jump up from where it smashed, spin and fall back down.

@export var gravity: float = 700.0
@export var lifetime: float = 1.1
@export var glass_color: Color = Color(0.82, 0.95, 1.0)
@export var shine_color: Color = Color.WHITE
@export var outline_color: Color = Color(0.1, 0.06, 0.04)

var _shards: Array[Dictionary] = []

## A burst at a screen point. toward_x: which way they fly (+1 right, -1 left),
## so shards from a corner jump in toward the middle of the screen.
func burst(at: Vector2, count: int, toward_x: float) -> void:
	for i in count:
		var size := randf_range(10.0, 18.0)
		var points := PackedVector2Array()
		for k in 3:
			var angle := TAU * k / 3.0 + randf_range(-0.6, 0.6)
			points.append(Vector2.from_angle(angle) * size * randf_range(0.6, 1.0))
		_shards.append({
			"pos": at + Vector2(randf_range(-6.0, 6.0), 0.0),
			"vel": Vector2(toward_x * randf_range(60.0, 200.0), -randf_range(200.0, 360.0)),
			"angle": randf() * TAU,
			"spin": randf_range(-14.0, 14.0),
			"points": points,
			"color": shine_color if randf() < 0.3 else glass_color,
			"life": lifetime * randf_range(0.7, 1.0),
		})

func _process(delta: float) -> void:
	for shard in _shards:
		shard.vel.y += gravity * delta
		shard.pos += shard.vel * delta
		shard.angle += shard.spin * delta
		shard.life -= delta
	_shards = _shards.filter(func(s: Dictionary) -> bool: return s.life > 0.0)
	queue_redraw()

func _draw() -> void:
	for shard in _shards:
		draw_set_transform((shard.pos as Vector2).floor(), shard.angle)
		var points: PackedVector2Array = shard.points
		draw_colored_polygon(points, shard.color)
		var outline := points.duplicate()
		outline.append(points[0])
		draw_polyline(outline, outline_color, 1.0)
	draw_set_transform(Vector2.ZERO)

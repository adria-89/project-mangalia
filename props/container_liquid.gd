extends Node3D

## Drink inside a container prop. Put it as a child of the prop (e.g. the
## ToonProp root); it measures the prop's meshes and fits itself inside.
## The surface stays level in world space, sloshes when the container
## accelerates, and spills over the rim when tilted or overfilled.

## Emitted when drink leaves the container: where (world) and how much (fraction of full).
signal spilled(world_point: Vector3, amount: float, is_foam: bool)

const LIQUID_SHADER: Shader = preload("res://shaders/liquid.gdshader")
const CELLS_NOISE: Texture2D = preload("res://assets/fx/noise/noise_cells.png")
const LUMP_NOISE: Texture2D = preload("res://assets/fx/noise/noise_big_cells.png")
const CLOUD_NOISE: Texture2D = preload("res://assets/fx/noise/noise_clouds.png")

@export_range(0.0, 1.0) var fill: float = 0.0
@export var liquid_color: Color = Color(0.85, 0.55, 0.12)
@export var surface_color: Color = Color(0.98, 0.93, 0.78)
@export var foam_color: Color = Color(1.0, 0.97, 0.88)

@export_group("Shape")
## Liquid radius as a fraction of the rim's inner corners (below 1 keeps it
## from poking through). The liquid copies the wall's number of sides, so
## close to 1 makes it touch the wall; above 1 if the rim has a lip that is
## narrower than the wall below it.
@export var inner_radius_ratio: float = 0.97
## Bottom thickness as a fraction of the height.
@export var base_ratio: float = 0.12

@export_group("Slosh")
@export var slosh_stiffness: float = 70.0
@export var slosh_damping: float = 3.5
@export var slosh_inertia: float = 0.06
@export var max_slosh: float = 0.7
## How fast drink pours out once the surface is past the rim.
@export var spill_rate: float = 4.0

@export_group("Foam")
## The head on top of the drink. Purely visual: it isn't counted as drink,
## doesn't spill and doesn't affect the rating. Heights are fractions of the
## container's height.
## Head built up per unit of drink poured in.
@export var foam_per_pour: float = 0.5
## Extra head when poured past full (per unit of overflow): it puffs up.
@export var foam_per_overflow: float = 3.0
## How fast the head settles down (per second) to the thin layer that stays.
@export var foam_settle: float = 0.03
@export var min_foam: float = 0.04
## How high above the rim the head can pile up.
@export var max_dome: float = 0.12
## Head whipped up by sloshing (per unit of slosh speed, per second).
@export var foam_slosh: float = 0.01

## Drink lost over the rim (fraction of full) since the container was last empty.
var spilled_total := 0.0
## Someone is drinking from it: tipping it doesn't spill (it goes in her mouth).
var drinking := false
## Current head height (fraction of the container height), see Foam.
var foam := 0.0

var _mesh_instance: MeshInstance3D
var _material: ShaderMaterial
var _axis_bottom := Vector3.ZERO # local, in the prop's space
var _axis_top := Vector3.ZERO
var _radius := 0.0
var _slosh := Vector2.ZERO
var _slosh_velocity := Vector2.ZERO
var _prev_point := Vector3.ZERO
var _prev_velocity := Vector3.ZERO
var _has_prev := false

func _ready() -> void:
	var prop := get_parent() as Node3D
	var all_points := _rim_points(prop, -INF)
	var box := AABB(all_points[0], Vector3.ZERO)
	for p in all_points:
		box = box.expand(p)
	# Find the body from the vertices around the top rim: the handle never
	# reaches them, and the rim's inner ring gives the inner wall radius.
	var rim_points := _rim_points(prop, box.end.y - box.size.y * 0.05)
	var rim_box := AABB(rim_points[0], Vector3.ZERO)
	for p in rim_points:
		rim_box = rim_box.expand(p)
	var center := rim_box.get_center()
	var inner := INF
	for p in rim_points:
		inner = minf(inner, Vector2(p.x - center.x, p.z - center.z).length())
	_radius = inner * inner_radius_ratio
	# The inner ring's corners: their count is the wall's number of sides,
	# and one of them tells how to turn the liquid so its corners line up.
	var corner_angles := {}
	var corner := Vector2.ZERO
	for p in rim_points:
		var d := Vector2(p.x - center.x, p.z - center.z)
		if d.length() <= inner * 1.02:
			# Same convention as CylinderMesh: angle 0 is +z, growing toward +x.
			corner_angles[roundi(rad_to_deg(atan2(d.x, d.y)))] = true
			corner = d
	var sides := corner_angles.size()
	if sides < 3 or sides > 32:
		sides = 16 # not a clean polygon: plain round cylinder
	var bottom := box.position.y + box.size.y * base_ratio
	var rim := box.end.y - box.size.y * 0.03
	_axis_bottom = Vector3(center.x, bottom, center.z)
	_axis_top = Vector3(center.x, rim, center.z)

	var cylinder := CylinderMesh.new()
	cylinder.top_radius = _radius
	cylinder.bottom_radius = _radius
	# Taller than the inside by max_dome, for the head to pile up over the rim.
	cylinder.height = (rim - bottom) * (1.0 + max_dome)
	cylinder.radial_segments = sides
	cylinder.rings = 1
	_material = ShaderMaterial.new()
	_material.shader = LIQUID_SHADER
	_material.set_shader_parameter("cells_noise", CELLS_NOISE)
	_material.set_shader_parameter("lump_noise", LUMP_NOISE)
	_material.set_shader_parameter("cloud_noise", CLOUD_NOISE)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "_Liquid"
	_mesh_instance.mesh = cylinder
	_mesh_instance.material_override = _material
	_mesh_instance.position = _axis_bottom + Vector3(0.0, cylinder.height / 2.0, 0.0)
	_mesh_instance.rotation.y = atan2(corner.x, corner.y)
	_mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	prop.add_child.call_deferred(_mesh_instance)

## Center of the opening, in the prop's own space (no tilt).
func axis_local() -> Vector3:
	return _axis_top

## Pour in some drink (fraction of a full container).
func add(amount: float) -> void:
	if fill <= 0.002:
		spilled_total = 0.0 # fresh pour
		foam = 0.0
	fill += amount
	foam += amount * foam_per_pour

## One gulp: the level drops by amount (fraction of full) over duration.
func gulp(amount: float, duration: float) -> void:
	var to := maxf(fill - amount, 0.0)
	create_tween().tween_property(self, "fill", to, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Screen-independent point at the middle of the surface, in world space.
func surface_world_point() -> Vector3:
	var prop := get_parent() as Node3D
	var bottom := prop.global_transform * _axis_bottom
	var top := prop.global_transform * _axis_top
	return bottom.lerp(top, clampf(fill, 0.0, 1.0))

## Middle of the head's top (the surface if there's no drink), in world space:
## where a stream poured in from above meets the drink.
func head_world_point() -> Vector3:
	var prop := get_parent() as Node3D
	var axis := prop.global_transform.basis * (_axis_top - _axis_bottom)
	var head := foam if fill > 0.002 else 0.0
	return surface_world_point() + axis * head

## Center of the opening and its (inner wall) radius, in world space.
func opening_world_center() -> Vector3:
	return (get_parent() as Node3D).global_transform * _axis_top

func opening_world_radius() -> float:
	var prop := get_parent() as Node3D
	return (prop.global_transform.basis * Vector3(_radius / inner_radius_ratio, 0.0, 0.0)).length()

## The point on the inner rim nearest a viewer (e.g. the camera), in world space:
## where the front wall starts hiding what's inside.
func front_rim_world_point(viewer: Vector3) -> Vector3:
	var top := opening_world_center()
	var toward := viewer - top
	toward.y = 0.0
	return top + toward.normalized() * opening_world_radius()
func _physics_process(delta: float) -> void:
	var prop := get_parent() as Node3D
	var level := surface_world_point()

	# Slosh: the surface lags behind the container's acceleration.
	if _has_prev:
		var velocity := (level - _prev_point) / delta
		var accel := (velocity - _prev_velocity) / delta
		_prev_velocity = velocity
		var force := -_slosh * slosh_stiffness - _slosh_velocity * slosh_damping \
			+ Vector2(accel.x, accel.z) * slosh_inertia
		_slosh_velocity += force * delta
	_prev_point = level
	_has_prev = true
	_slosh = (_slosh + _slosh_velocity * delta).limit_length(max_slosh)
	# Level with the true horizon (the ship leans under it), plus the slosh.
	var normal := (Sea.up_3d() + Vector3(_slosh.x, 0.0, _slosh.y)).normalized()

	_spill_over_rim(prop, level, normal, delta)
	if fill > 1.0:
		var excess := fill - 1.0
		fill = 1.0
		spilled_total += excess
		spilled.emit(prop.global_transform * _axis_top, excess, true)
		foam += excess * foam_per_overflow

	_update_foam(delta)

	if _mesh_instance != null:
		var bottom := prop.global_transform * _axis_bottom
		var top := prop.global_transform * _axis_top
		var height := (top - bottom).length()
		_mesh_instance.visible = fill > 0.002
		_material.set_shader_parameter("surface_point", surface_world_point())
		_material.set_shader_parameter("surface_normal", normal)
		_material.set_shader_parameter("foam_height", foam * height)
		_material.set_shader_parameter("axis_point", bottom)
		_material.set_shader_parameter("axis_up", (top - bottom).normalized())
		_material.set_shader_parameter("axis_height", height)
		_material.set_shader_parameter("radius", opening_world_radius() * inner_radius_ratio)
		_material.set_shader_parameter("liquid_color", liquid_color)
		_material.set_shader_parameter("surface_color", surface_color)
		_material.set_shader_parameter("foam_color", foam_color)

## The head settles toward a thin layer, sloshing whips it up a bit, and it
## never gets taller than the drink under it or higher than max_dome over the rim.
func _update_foam(delta: float) -> void:
	foam = move_toward(foam, min_foam, foam_settle * delta)
	foam += _slosh_velocity.length() * foam_slosh * delta
	foam = clampf(foam, 0.0, minf(fill, 1.0 + max_dome - fill))

## If the surface rises past the rim anywhere (tilt or slosh), drink pours out there.
func _spill_over_rim(prop: Node3D, level: Vector3, normal: Vector3, delta: float) -> void:
	if fill <= 0.002 or drinking:
		return
	var height := (prop.global_transform * _axis_top - prop.global_transform * _axis_bottom).length()
	var worst := 0.0
	var worst_point := Vector3.ZERO
	for i in 12:
		var angle := TAU * i / 12.0
		var rim_local := _axis_top + Vector3(cos(angle), 0.0, sin(angle)) * _radius
		var rim := prop.global_transform * rim_local
		var below_surface := -normal.dot(rim - level)
		if below_surface > worst:
			worst = below_surface
			worst_point = rim
	if worst > 0.0 and height > 0.0:
		var amount := minf(worst / height * spill_rate * delta, fill)
		fill -= amount
		spilled_total += amount
		spilled.emit(worst_point, amount, false)

## Mesh vertices (in the prop's space) at or above a height.
func _rim_points(prop: Node3D, min_y: float) -> PackedVector3Array:
	var to_local := prop.global_transform.affine_inverse()
	var points := PackedVector3Array()
	for node in prop.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if String(mi.name).begins_with("_") or mi.mesh == null:
			continue
		var xform := to_local * mi.global_transform
		for surface in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p := xform * v
				if p.y >= min_y:
					points.append(p)
	return points

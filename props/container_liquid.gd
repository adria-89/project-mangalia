extends Node3D

## Drink inside a container prop. Put it as a child of the prop (e.g. the
## ToonProp root); it measures the prop's meshes and fits itself inside.
## The surface stays level in world space, sloshes when the container
## accelerates, and spills over the rim when tilted or overfilled.
##
## The drink is a stack of layers, bottom first, each a mix of drinks (see
## Drink). A lighter drink poured gently floats on top as a new layer; poured
## roughly, or heavier than the top layer, it mixes into it. Sloshing blurs
## neighbouring layers into each other, and layers that end up alike merge.
## Spills and gulps take from the top.

## Emitted when drink leaves the container: where (world) and how much (fraction of full).
signal spilled(world_point: Vector3, amount: float, is_foam: bool)

const LIQUID_SHADER: Shader = preload("res://shaders/liquid.gdshader")
const CELLS_NOISE: Texture2D = preload("res://assets/fx/noise/noise_cells.png")
const LUMP_NOISE: Texture2D = preload("res://assets/fx/noise/noise_big_cells.png")
const CLOUD_NOISE: Texture2D = preload("res://assets/fx/noise/noise_clouds.png")
## Must match the array sizes in liquid.gdshader.
const MAX_LAYERS := 8

## What add() pours when it isn't told, and what raising fill adds to an empty one.
@export var default_drink: Drink = preload("res://props/drinks/beer.tres")

## Total drink in it (fraction of full), all layers together. Setting it
## lower takes drink off the top (gulps, spills); 0 empties it.
var fill: float:
	get:
		return _total()
	set(value):
		_set_fill(value)
## The top layer's body color (spill drips) and its top seen from above.
var liquid_color: Color:
	get:
		return _blend(_layers.back(), "color") if not _layers.is_empty() else default_drink.color
var surface_color: Color:
	get:
		return _blend(_layers.back(), "surface_color") if not _layers.is_empty() else default_drink.surface_color
## The head's color: follows whatever foamed it up.
var foam_color: Color = Color(1.0, 0.97, 0.88)

@export_group("Shape")
## Liquid radius as a fraction of the rim's inner corners (below 1 keeps it
## from poking through). The liquid copies the wall's number of sides, so
## close to 1 makes it touch the wall; above 1 if the rim has a lip that is
## narrower than the wall below it.
@export var inner_radius_ratio: float = 0.97
## Bottom thickness as a fraction of the height.
@export var base_ratio: float = 0.12
## Measure only this mesh (by node name), e.g. a bottle's body without its
## neck, label and cap. Empty = all of the prop's meshes.
@export var body_mesh: String = ""
## Where the ring of vertices that sets the wall's radius and sides is, as a
## fraction of the measured height (it takes the vertices up to 5% below
## it): the top (1) is a glass's rim; a bottle's is down its body, under
## the shoulder.
@export_range(0.0, 1.0) var measure_at: float = 1.0
## Where full is, as a fraction of the measured height.
@export_range(0.0, 1.0) var full_at: float = 0.97

@export_group("Slosh")
@export var slosh_stiffness: float = 70.0
@export var slosh_damping: float = 3.5
@export var slosh_inertia: float = 0.06
@export var max_slosh: float = 0.7
## How fast drink pours out once the surface is past the rim.
@export var spill_rate: float = 4.0
## Off for a bottle: tipping it pours through the stream instead (bottle_rail.gd).
@export var spills: bool = true

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
## Extra head when a fizzy drink mixes into a different fizzy one (per unit
## mixed): beer into cola foams up.
@export var reaction_foam: float = 2.0

@export_group("Layers")
## Slosh speed below which layers stay put (carrying it calmly is fine).
@export var slosh_mix_from: float = 0.5
## How fast neighbouring layers blend per unit of slosh speed over that, per second.
@export var slosh_mixing: float = 0.15
## How deep a hard pour reaches (fraction of full) at gentleness 0, less the
## gentler it is ((1 - gentleness)²). Until the top layer is that thick, the
## stream churns it with the layer below.
@export var punch_depth: float = 0.4
## Share of the pour that goes through when the top layer has just started.
@export var stir_strength: float = 0.6
## Neighbouring layers this alike (0 = same mix, 1 = nothing shared) become one.
@export var merge_below: float = 0.04

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
## Bottom first. Each layer maps Drink -> amount (fraction of full).
var _layers: Array[Dictionary] = []

func _ready() -> void:
	var prop := get_parent() as Node3D
	var all_points := _rim_points(prop, -INF, INF)
	var box := AABB(all_points[0], Vector3.ZERO)
	for p in all_points:
		box = box.expand(p)
	# Find the body from the vertices around the top rim (or measure_at): the
	# handle never reaches them, and the inner ring gives the inner wall radius.
	var ring_y := box.position.y + box.size.y * measure_at
	var rim_points := _rim_points(prop, ring_y - box.size.y * 0.05, ring_y + 0.0001)
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
	var rim := box.position.y + box.size.y * full_at
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

## Pour in some drink (fraction of a full container). gentleness 0..1: a
## gentle pour of a lighter drink floats on the top layer, a rough one mixes
## into it; a heavier drink always sinks and mixes in. Returns how much of
## the pour (0..1) mixed into a different drink, e.g. to show it swirling in.
func add(amount: float, drink: Drink = null, gentleness: float = 0.5) -> float:
	if drink == null:
		drink = default_drink
	if fill <= 0.002:
		_layers.clear() # fresh pour
		spilled_total = 0.0
		foam = 0.0
		foam_color = drink.foam_color
	var head := amount * foam_per_pour * drink.foaminess
	var mixing := 0.0
	if _layers.is_empty():
		_layers.append({drink: amount})
	else:
		var top: Dictionary = _layers.back()
		var mixed := amount
		if _share(top, drink) < 0.95:
			if drink.density < _density(top):
				mixed = amount * pow(1.0 - gentleness, 2.0)
			mixing = mixed / amount
		if drink.carbonated:
			head += mixed * (_fizz_share(top) - _share(top, drink)) * reaction_foam
		top[drink] = top.get(drink, 0.0) + mixed
		if amount - mixed > 0.0:
			_layers.append({drink: amount - mixed})
		mixing = maxf(mixing, _punch(amount, drink, gentleness))
		_merge_alike()
	if head > 0.0:
		foam_color = foam_color.lerp(drink.foam_color, head / (foam + head))
		foam += head
	return mixing

## A rough stream goes deeper than the top layer while that one is thin
## (see punch_depth): part of what was just poured ends up in the layer
## below instead. Returns how hard it punched through (0..1).
func _punch(amount: float, drink: Drink, gentleness: float) -> float:
	if _layers.size() < 2:
		return 0.0
	var depth := punch_depth * pow(1.0 - gentleness, 2.0)
	var top: Dictionary = _layers.back()
	var below: Dictionary = _layers[_layers.size() - 2]
	var thickness := _sum(top)
	if thickness >= depth or not top.has(drink):
		return 0.0
	var strength := 1.0 - thickness / depth
	var through := minf(amount * stir_strength * strength, top[drink])
	if drink.carbonated:
		foam += through * (_fizz_share(below) - _share(below, drink)) * reaction_foam
	top[drink] -= through
	below[drink] = below.get(drink, 0.0) + through
	return strength

## How much of each drink is in it (Drink -> fraction of full), all layers together.
func composition() -> Dictionary:
	var result := {}
	for layer in _layers:
		for drink: Drink in layer:
			result[drink] = result.get(drink, 0.0) + layer[drink]
	return result

## The layers, bottom first: each maps Drink -> amount. Don't change them.
func layers() -> Array[Dictionary]:
	return _layers

## One gulp: the level drops by amount (fraction of full) over duration.
func gulp(amount: float, duration: float) -> void:
	var to := maxf(fill - amount, 0.0)
	create_tween().tween_property(self, "fill", to, duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

## Screen-independent point at the middle of the surface, in world space.
func surface_world_point() -> Vector3:
	var prop := get_parent() as Node3D
	var bottom := prop.global_transform * _axis_bottom
	var top := prop.global_transform * _axis_top
	var amount := clampf(fill, 0.0, 1.0)
	var level := bottom.lerp(top, amount)
	# Tipped past lying flat (a bottle pouring), the drink runs to the other
	# end: measure the level from there instead, blending over the turn.
	var upright := (top - bottom).normalized().dot(Sea.up_3d())
	var flip := smoothstep(0.3, -0.3, upright)
	if flip > 0.0:
		level = level.lerp(top.lerp(bottom, amount), flip)
	return level

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
	_mix_layers(delta)

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
		_material.set_shader_parameter("surface_color", surface_color)
		_material.set_shader_parameter("foam_color", foam_color)
		_update_layer_uniforms()

## Hands the layers to the shader: where each one's top is (fraction of
## full), its color, and its fizz (color, alpha = how fizzy).
func _update_layer_uniforms() -> void:
	var tops := PackedFloat32Array()
	var colors := PackedColorArray()
	var fizz := PackedColorArray()
	var height := 0.0
	for layer in _layers:
		height += _sum(layer)
		tops.append(height)
		colors.append(_blend(layer, "color"))
		var f := _blend(layer, "fizz_color")
		f.a = _fizz_share(layer)
		fizz.append(f)
	tops.resize(MAX_LAYERS)
	colors.resize(MAX_LAYERS)
	fizz.resize(MAX_LAYERS)
	_material.set_shader_parameter("layer_count", _layers.size())
	_material.set_shader_parameter("layer_tops", tops)
	_material.set_shader_parameter("layer_colors", colors)
	_material.set_shader_parameter("layer_fizz", fizz)
	_material.set_shader_parameter("fill_level", minf(fill, 1.0))

## Sloshing harder than slosh_mix_from swaps a little drink between each
## pair of neighbouring layers, so they drift toward the same mix.
func _mix_layers(delta: float) -> void:
	var rate := maxf(_slosh_velocity.length() - slosh_mix_from, 0.0) * slosh_mixing * delta
	if rate <= 0.0 or _layers.size() < 2:
		return
	for i in _layers.size() - 1:
		_exchange(_layers[i], _layers[i + 1], minf(rate, 0.5))
	_merge_alike()

## Swaps fraction (of the smaller one) between two layers, each giving its own mix.
func _exchange(a: Dictionary, b: Dictionary, fraction: float) -> void:
	var total_a := _sum(a)
	var total_b := _sum(b)
	if total_a <= 0.0 or total_b <= 0.0:
		return
	var volume := fraction * minf(total_a, total_b)
	var from_a := {}
	for drink: Drink in a:
		from_a[drink] = a[drink] * volume / total_a
	var from_b := {}
	for drink: Drink in b:
		from_b[drink] = b[drink] * volume / total_b
	for drink: Drink in from_a:
		a[drink] -= from_a[drink]
		b[drink] = b.get(drink, 0.0) + from_a[drink]
	for drink: Drink in from_b:
		b[drink] -= from_b[drink]
		a[drink] = a.get(drink, 0.0) + from_b[drink]

## Neighbours that are nearly the same mix become one layer; past
## MAX_LAYERS the most alike pair is merged too.
func _merge_alike() -> void:
	var i := _layers.size() - 2
	while i >= 0:
		if _difference(_layers[i], _layers[i + 1]) < merge_below:
			_merge(i)
		i -= 1
	while _layers.size() > MAX_LAYERS:
		var best := 0
		for j in _layers.size() - 1:
			if _difference(_layers[j], _layers[j + 1]) < _difference(_layers[best], _layers[best + 1]):
				best = j
		_merge(best)

## Pours layer i + 1 into layer i.
func _merge(i: int) -> void:
	var upper: Dictionary = _layers[i + 1]
	for drink: Drink in upper:
		_layers[i][drink] = _layers[i].get(drink, 0.0) + upper[drink]
	_layers.remove_at(i + 1)

func _total() -> float:
	var total := 0.0
	for layer in _layers:
		total += _sum(layer)
	return total

## Lowering takes drink off the top; raising tops up the top layer as it is.
func _set_fill(value: float) -> void:
	value = maxf(value, 0.0)
	var current := _total()
	if value < current:
		var take := current - value
		while take > 0.0 and not _layers.is_empty():
			var top: Dictionary = _layers.back()
			var amount := _sum(top)
			if amount <= take:
				take -= amount
				_layers.pop_back()
			else:
				for drink: Drink in top:
					top[drink] *= (amount - take) / amount
				take = 0.0
		if _total() < 0.0005:
			_layers.clear()
	elif value > current:
		if _layers.is_empty() or current <= 0.0:
			_layers = [{default_drink: value}]
			return
		var top: Dictionary = _layers.back()
		var amount := _sum(top)
		for drink: Drink in top:
			top[drink] *= (amount + value - current) / amount

func _sum(layer: Dictionary) -> float:
	var total := 0.0
	for drink: Drink in layer:
		total += layer[drink]
	return total

## Fraction of a layer that is this drink.
func _share(layer: Dictionary, drink: Drink) -> float:
	var total := _sum(layer)
	return layer.get(drink, 0.0) / total if total > 0.0 else 0.0

## Fraction of a layer that is fizzy.
func _fizz_share(layer: Dictionary) -> float:
	var fizzy := 0.0
	for drink: Drink in layer:
		if drink.carbonated:
			fizzy += _share(layer, drink)
	return fizzy

func _density(layer: Dictionary) -> float:
	var density := 0.0
	for drink: Drink in layer:
		density += drink.density * _share(layer, drink)
	return density

## A Drink color property (color, fizz_color...) mixed by the layer's shares.
func _blend(layer: Dictionary, property: StringName) -> Color:
	var color := Color(0.0, 0.0, 0.0, 0.0)
	for drink: Drink in layer:
		color += (drink.get(property) as Color) * _share(layer, drink)
	return color

## How different two layers' mixes are: 0 = the same, 1 = nothing in common.
func _difference(a: Dictionary, b: Dictionary) -> float:
	var difference := 0.0
	var drinks := a.duplicate()
	drinks.merge(b)
	for drink: Drink in drinks:
		difference += absf(_share(a, drink) - _share(b, drink))
	return difference / 2.0

## The head settles toward a thin layer, sloshing whips it up a bit, and it
## never gets taller than the drink under it or higher than max_dome over the rim.
func _update_foam(delta: float) -> void:
	foam = move_toward(foam, min_foam, foam_settle * delta)
	foam += _slosh_velocity.length() * foam_slosh * delta
	foam = clampf(foam, 0.0, minf(fill, 1.0 + max_dome - fill))

## If the surface rises past the rim anywhere (tilt or slosh), drink pours out there.
func _spill_over_rim(prop: Node3D, level: Vector3, normal: Vector3, delta: float) -> void:
	if fill <= 0.002 or drinking or not spills:
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

## Mesh vertices (in the prop's space) between two heights, only from
## body_mesh if it's set.
func _rim_points(prop: Node3D, min_y: float, max_y: float) -> PackedVector3Array:
	var to_local := prop.global_transform.affine_inverse()
	var points := PackedVector3Array()
	for node in prop.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if String(mi.name).begins_with("_") or mi.mesh == null:
			continue
		if not body_mesh.is_empty() and String(mi.name) != body_mesh:
			continue
		var xform := to_local * mi.global_transform
		for surface in mi.mesh.get_surface_count():
			for v: Vector3 in mi.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				var p := xform * v
				if p.y >= min_y and p.y <= max_y:
					points.append(p)
	return points

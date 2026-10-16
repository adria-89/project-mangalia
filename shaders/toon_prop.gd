@tool
class_name ToonProp
extends Node3D

## Attach to a node that has an imported model (.glb) under it. Every mesh
## below gets the toon material (keeping its own texture and color) plus a
## black outline. The outline uses a copy of the mesh with averaged normals,
## so UV seams and hard edges don't split it open.

const TOON_SHADER: Shader = preload("res://shaders/toon.gdshader")
const OUTLINE_SHADER: Shader = preload("res://shaders/outline.gdshader")
const GLASS_SHADER: Shader = preload("res://shaders/glass.gdshader")
const OUTLINE_GLASS_SHADER: Shader = preload("res://shaders/outline_glass.gdshader")
const OUTLINE_NODE_NAME := "_Outline"

## Draw the whole prop as cartoon glass (so the drink inside shows) instead
## of the toon material. Tweak the look in glass.gdshader.
@export var glass: bool = false:
	set(value):
		glass = value
		_apply()

## Off = show the texture exactly as painted (no lantern light/shadow).
@export var use_lighting: bool = false:
	set(value):
		use_lighting = value
		_apply()
@export var outline_color: Color = Color.BLACK:
	set(value):
		outline_color = value
		_apply()
@export_range(0.0, 8.0, 0.5) var outline_thickness_px: float = 2.0:
	set(value):
		outline_thickness_px = value
		_apply()

func _ready() -> void:
	_apply()

func _apply() -> void:
	if not is_inside_tree():
		return
	var outline_mat := ShaderMaterial.new()
	outline_mat.shader = OUTLINE_GLASS_SHADER if glass else OUTLINE_SHADER
	# Glass draws back faces (0), then front faces (1), then the outline (2).
	outline_mat.render_priority = 2 if glass else 0
	outline_mat.set_shader_parameter("outline_color", outline_color)
	outline_mat.set_shader_parameter("thickness_px", outline_thickness_px)
	for mesh_instance in _find_meshes(self):
		_setup_mesh(mesh_instance, outline_mat)

func _find_meshes(node: Node) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for child in node.get_children():
		# Generated helpers (outline, liquid...) are named with a leading underscore.
		if String(child.name).begins_with("_"):
			continue
		if child is MeshInstance3D:
			found.append(child)
		found.append_array(_find_meshes(child))
	return found

func _setup_mesh(mesh_instance: MeshInstance3D, outline_mat: ShaderMaterial) -> void:
	var mesh := mesh_instance.mesh
	if mesh == null:
		return
	for surface in mesh.get_surface_count():
		var source := mesh.surface_get_material(surface)
		var mat := _glass_material_for(source) if glass else _toon_material_for(source)
		mesh_instance.set_surface_override_material(surface, mat)

	var outline := mesh_instance.get_node_or_null(OUTLINE_NODE_NAME) as MeshInstance3D
	if outline == null:
		outline = MeshInstance3D.new()
		outline.name = OUTLINE_NODE_NAME
		outline.mesh = _smoothed_copy(mesh)
		# Not saved into the scene; rebuilt every time it loads.
		mesh_instance.add_child(outline, false, Node.INTERNAL_MODE_BACK)
	outline.material_override = outline_mat

func _toon_material_for(source: Material) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = TOON_SHADER
	mat.set_shader_parameter("use_lighting", use_lighting)
	if source is BaseMaterial3D:
		var base := source as BaseMaterial3D
		mat.set_shader_parameter("albedo", base.albedo_color)
		if base.albedo_texture != null:
			mat.set_shader_parameter("albedo_texture", base.albedo_texture)
			mat.set_shader_parameter("use_texture", true)
	return mat

## Back-face pass with the front-face pass as its next_pass.
func _glass_material_for(source: Material) -> ShaderMaterial:
	var back := _glass_pass(source, true)
	back.render_priority = 0
	var front := _glass_pass(source, false)
	front.render_priority = 1
	back.next_pass = front
	return back

func _glass_pass(source: Material, back_pass: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = GLASS_SHADER
	mat.set_shader_parameter("back_pass", back_pass)
	if source is BaseMaterial3D and (source as BaseMaterial3D).albedo_texture != null:
		mat.set_shader_parameter("albedo_texture", (source as BaseMaterial3D).albedo_texture)
		mat.set_shader_parameter("use_texture", true)
	return mat

## Same geometry, but every vertex at the same position shares one averaged
## normal, so the inflated outline hull stays closed.
func _smoothed_copy(mesh: Mesh) -> ArrayMesh:
	var result := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var sums := {}
		for i in vertices.size():
			var key := vertices[i].snappedf(0.0001)
			sums[key] = sums.get(key, Vector3.ZERO) + normals[i]
		var smoothed := PackedVector3Array()
		smoothed.resize(vertices.size())
		for i in vertices.size():
			smoothed[i] = (sums[vertices[i].snappedf(0.0001)] as Vector3).normalized()
		var outline_arrays := []
		outline_arrays.resize(Mesh.ARRAY_MAX)
		outline_arrays[Mesh.ARRAY_VERTEX] = vertices
		outline_arrays[Mesh.ARRAY_NORMAL] = smoothed
		outline_arrays[Mesh.ARRAY_INDEX] = arrays[Mesh.ARRAY_INDEX]
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, outline_arrays)
	return result

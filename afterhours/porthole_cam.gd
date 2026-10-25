@tool
class_name PortholeCam
extends Node2D

## Her face in a brass porthole: a live cam of how she feels, since the rear
## view doesn't show it. Uses her bar sprites (CustomerData faces, blush and
## nervous overlays), cropped to a circle around her face. In the editor it
## shows preview so the scene can be laid out by eye.

enum Face { DEFAULT, HAPPY, KISS, WINK }

## Whose face is shown in the editor (every girl in AfterHoursGirl.FOLDER
## is in the list).
@export var preview: String = "Lizard":
	set(value):
		preview = value
		if Engine.is_editor_hint() and is_inside_tree():
			setup(_preview())

@export var radius: float = 38.0
## How big her sprite is drawn inside, so her whole head fits the ring.
@export var face_scale: float = 0.5:
	set(value):
		face_scale = value
		if Engine.is_editor_hint() and is_inside_tree():
			setup(_data)
## How far above her mouth the circle is centred (sprite pixels).
@export var face_above_mouth: float = 34.0:
	set(value):
		face_above_mouth = value
		if Engine.is_editor_hint() and is_inside_tree():
			setup(_data)
@export var ring_color := Color(0.72, 0.52, 0.22)
@export var ring_dark := Color(0.36, 0.24, 0.1)

var _data: CustomerData
var _face: Sprite2D
var _blush: Sprite2D
var _nervous: Sprite2D
var _ring: Node2D
var _glass: Polygon2D
var _blush_amount := 0.0
var _nervous_amount := 0.0
var _bob := 0.0
var _time := 0.0
var _shake := 0.0

func _ready() -> void:
	_ring = Node2D.new()
	_ring.draw.connect(_draw_ring)
	add_child(_ring)
	if Engine.is_editor_hint():
		setup(_preview())

func _validate_property(property: Dictionary) -> void:
	if property.name == "preview":
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = ",".join(AfterHoursGirl.all().keys())

func _preview() -> CustomerData:
	return AfterHoursGirl.all().get(preview)

## Puts her face in (again, if there was one).
func setup(data: CustomerData) -> void:
	_data = data
	if _glass:
		_glass.queue_free()
		_glass = null
	_face = null
	_blush = null
	_nervous = null
	if data == null:
		return
	var glass := Polygon2D.new()
	_glass = glass
	glass.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	glass.color = Color(0.1, 0.12, 0.16)
	var circle := PackedVector2Array()
	for i in 32:
		circle.append(Vector2.from_angle(TAU * i / 32.0) * radius)
	glass.polygon = circle
	add_child(glass)
	move_child(glass, 0) # under the ring
	var center := _data.mouth - Vector2(0, face_above_mouth)
	_face = _layer(glass, _data.texture, center)
	_blush = _layer(glass, _data.blush, center)
	_nervous = _layer(glass, _data.nervous, center)
	set_mood(_blush_amount, _nervous_amount, _bob)

func _process(delta: float) -> void:
	if _face == null or Engine.is_editor_hint():
		return
	_time += delta
	_shake = move_toward(_shake, 0.0, delta * 3.0)
	var offset := Vector2(sin(_time * 50.0) * _shake * 2.0, sin(_time * 3.0) * _bob)
	for layer in [_face, _blush, _nervous]:
		if layer:
			layer.position = layer.get_meta("base") + offset
	if _blush:
		_blush.modulate.a = _blush_amount
	if _nervous:
		_nervous.modulate.a = _nervous_amount

func set_face(face: Face) -> void:
	if _face == null:
		return
	var texture: Texture2D = [_data.texture, _data.face_happy, _data.face_kiss, _data.face_wink][face]
	_face.texture = texture if texture else _data.texture

## blush 0..1, nervous 0..1, bob = how hard she rocks (pixels).
func set_mood(blush: float, nervous: float, bob: float) -> void:
	_blush_amount = blush
	_nervous_amount = nervous
	_bob = bob
	if _blush:
		_blush.modulate.a = blush
	if _nervous:
		_nervous.modulate.a = nervous

## A jolt (wrong move, climax).
func jolt() -> void:
	_shake = 1.0

func _layer(parent: Node, texture: Texture2D, center: Vector2) -> Sprite2D:
	if texture == null:
		return null
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.scale = Vector2.ONE * face_scale
	sprite.set_meta("base", -center * face_scale)
	sprite.position = -center * face_scale
	parent.add_child(sprite)
	return sprite

func _draw_ring() -> void:
	_ring.draw_arc(Vector2.ZERO, radius + 3.0, 0.0, TAU, 40, ring_dark, 8.0)
	_ring.draw_arc(Vector2.ZERO, radius + 2.0, 0.0, TAU, 40, ring_color, 5.0)
	for i in 8:
		_ring.draw_circle(Vector2.from_angle(TAU * i / 8.0 + 0.2) * (radius + 2.0), 1.5, ring_dark)

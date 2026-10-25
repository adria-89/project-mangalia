@tool
class_name SweatDrops
extends Node2D

## Sweat on her as she gets worked up (the lizard's nervous drops). Put it
## under the Rig: it follows her butt (its springs, breathing and size), so
## lay the drops out on her in the editor. Each drop (a child Sprite2D) shows
## up at its own amount, in child order, and slowly trickles down and fades,
## over and over.

## How far a drop trickles down before it fades (rig pixels).
@export var trickle: float = 6.0
## Seconds for one trickle.
@export var period: float = 3.0
## How solid a drop gets at most (subtle).
@export_range(0.0, 1.0, 0.05) var max_alpha: float = 0.8
## The amount the first drop shows up at; the last one shows up at 1.
@export_range(0.0, 1.0, 0.05) var first_at: float = 0.25
## Editor only: how sweaty she looks in the preview.
@export_range(0.0, 1.0, 0.05) var preview_amount: float = 1.0

## 0..1: how sweaty she is (the scene gives it her arousal).
var amount := 0.0

var _time := 0.0

func _process(delta: float) -> void:
	_time += delta
	var rig := get_parent() as BodyRig
	if rig:
		transform = rig.body_transform()
	var shown := preview_amount if Engine.is_editor_hint() else amount
	var drops := get_children()
	for i in drops.size():
		var drop := drops[i] as Sprite2D
		if drop == null:
			continue
		var at := lerpf(first_at, 1.0, float(i) / maxf(drops.size() - 1, 1))
		var strength := clampf((shown - at) / 0.15 + 1.0, 0.0, 1.0) if shown > 0.0 else 0.0
		# Each drop on its own beat: in, down, gone.
		var cycle := fmod(_time / period + i * 0.37, 1.0)
		drop.offset = Vector2(0, cycle * trickle)
		drop.modulate.a = strength * max_alpha * sin(PI * cycle)

class_name ViolinBow
extends AudioStreamPlayer

## The penis as a violin bow: sliding in or out of her plays a note, held for
## as long as it keeps moving (the clips loop their middle, see their import
## loop points), louder the faster it goes, gone when it stops like a bow
## lifted off the string. Every change of direction is a new bow stroke and
## the next clip in clips. How deep it is picks the note, snapped to scale,
## gliding between notes like a finger on the string. It plays on top of the
## thrust sounds. The scene calls bow() every frame.

@export var clips: Array[AudioStream] = []

@export_group("Melody")
## The notes it can play, in semitones up from the lowest (one octave of
## the Romanian minor, the lăutari's scale, by default). Higher notes go up
## an octave at a time.
@export var scale: PackedInt32Array = [0, 2, 3, 6, 7, 9, 10]
## How many notes of the scale (going up through the octaves) depth covers.
@export var notes: int = 10
## The lowest note, in semitones from the clips' own pitch.
@export var lowest: int = -7
## Depth (see BodyRig.depth) per note: 0 depth plays the lowest note.
@export var depth_per_note: float = 0.16
## Seconds to slide from one note to the next.
@export var glide: float = 0.04

@export_group("Bowing")
## Depth per second that plays at full volume.
@export var full_speed: float = 3.0
## Slower than this (depth per second) and the bow is off the string.
@export var stop_speed: float = 0.25
## Its loudest, on top of the thrust sounds (dB).
@export var loudest_db: float = -6.0
## Seconds to swell in and to die away.
@export var attack: float = 0.03
@export var release: float = 0.09

var _clip := -1
var _direction := 0
var _loudness := 0.0
var _pitch := 1.0
var _prev_depth := 0.0
var _speed := 0.0

func _ready() -> void:
	bus = &"Violin"
	volume_db = -80.0

## One frame of bowing: depth is how deep the penis is, inside her or not.
func bow(depth: float, inside: bool, delta: float) -> void:
	if delta <= 0.0:
		return
	# Smoothed, so a jumpy mouse frame doesn't flip the bow.
	_speed = lerpf(_speed, (depth - _prev_depth) / delta if inside else 0.0, 1.0 - exp(-delta / 0.03))
	_prev_depth = depth
	var moving := inside and absf(_speed) > stop_speed
	if moving:
		var direction := 1 if _speed > 0.0 else -1
		if direction != _direction or not playing:
			_stroke(direction)
	elif not inside:
		_direction = 0
	# Louder the faster it moves; swells in quick, dies away a bit slower.
	var target := clampf(absf(_speed) / full_speed, 0.0, 1.0) if moving else 0.0
	_loudness = move_toward(_loudness, target, delta / (attack if target > _loudness else release))
	volume_db = linear_to_db(maxf(_loudness, 0.0001)) + loudest_db
	if _loudness <= 0.0 and playing:
		stop()
	# The note for this depth, slid to.
	_pitch = lerpf(_pitch, _note_pitch(depth), 1.0 - exp(-delta / maxf(glide, 0.001)))
	pitch_scale = _pitch

## A new bow stroke: the next clip, from its start (the attack).
func _stroke(direction: int) -> void:
	_direction = direction
	if clips.is_empty():
		return
	_clip = (_clip + 1) % clips.size()
	stream = clips[_clip]
	if _loudness <= 0.0:
		_pitch = _note_pitch(_prev_depth) # a fresh note starts on pitch
	play()

## The scale note at this depth, as a pitch scale.
func _note_pitch(depth: float) -> float:
	var step := clampi(floori(depth / depth_per_note), 0, notes - 1)
	var semitones := lowest + scale[step % scale.size()] + 12 * (step / scale.size())
	return pow(2.0, semitones / 12.0)

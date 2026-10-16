extends Node3D

## Tip coins. Customers toss them onto the counter, where they bounce, spin
## and settle flat; clicking one collects it (the money HUD flies it away).

## A coin was clicked: where it was on screen.
signal collected(screen_position: Vector2)
## A tossed coin just left her hand (or wherever it came from).
signal launched

const COIN_SCENE: PackedScene = preload("res://props/lei.tscn")
const CLINKS: Array[AudioStream] = [
	preload("res://audio/coin1.ogg"),
	preload("res://audio/coin2.ogg"),
	preload("res://audio/coin3.ogg"),
	preload("res://audio/coin4.ogg"),
]

@export var coin_scale: float = 0.06
@export var gravity: float = 9.0
@export var bounce: float = 0.45
## Counter limits (x/z), same as the props layer.
@export var counter_min := Vector2(-1.6, -3.95)
@export var counter_max := Vector2(1.6, -3.15)
## Coins lying on the counter slide when the ship leans harder than this (3D units/s²).
@export var drift_static: float = 0.35
## How close (screen px) a click must be to a coin.
@export var click_radius: float = 14.0

## Each coin: node, velocity, spin axis/speed, and whether it has settled.
var _coins: Array[Dictionary] = []
var _players: Array[AudioStreamPlayer] = []

func _ready() -> void:
	for i in 4:
		var player := AudioStreamPlayer.new()
		add_child(player)
		_players.append(player)

## Throw a handful of coins from a point (e.g. the customer) toward the player.
## height: multiplies how high they fly.
## stagger: seconds between one coin and the next (0 = all at once).
func toss(from: Vector3, count: int, height: float = 1.0, stagger: float = 0.12) -> void:
	for i in count:
		var coin: Node3D = COIN_SCENE.instantiate()
		add_child(coin)
		coin.scale = Vector3.ONE * coin_scale
		coin.position = from + Vector3(randf_range(-0.08, 0.08), 0.0, 0.0)
		coin.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		_coins.append({
			"node": coin,
			"velocity": Vector3(randf_range(-0.6, 0.6), randf_range(1.6, 2.3) * height, randf_range(0.5, 1.1)),
			"spin_axis": Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized(),
			"spin": randf_range(10.0, 20.0),
			"settled": false,
			"delay": i * stagger,
		})
		coin.visible = false

func _physics_process(delta: float) -> void:
	var launched_now := false
	for c in _coins:
		var coin: Node3D = c.node
		if c.delay > 0.0:
			c.delay -= delta
			continue
		if not coin.visible:
			coin.visible = true
			launched.emit()
			launched_now = true
		if c.settled:
			_drift(c, delta)
			continue
		var velocity: Vector3 = c.velocity
		velocity.y -= gravity * delta
		coin.position += velocity * delta
		coin.rotate(c.spin_axis, c.spin * delta)
		# Bounce off the counter's ends.
		if coin.position.x < counter_min.x or coin.position.x > counter_max.x:
			coin.position.x = clampf(coin.position.x, counter_min.x, counter_max.x)
			velocity.x *= -0.5
		if coin.position.z < counter_min.y or coin.position.z > counter_max.y:
			coin.position.z = clampf(coin.position.z, counter_min.y, counter_max.y)
			velocity.z *= -0.5
		# Land on the counter.
		if coin.position.y <= 0.0 and velocity.y < 0.0:
			coin.position.y = 0.0
			if velocity.y < -0.6:
				velocity = Vector3(velocity.x * 0.6, -velocity.y * bounce, velocity.z * 0.6)
				c.spin *= 0.6
				_clink(clampf(-velocity.y, 0.3, 1.0))
			else:
				_settle(c)
		c.velocity = velocity
	if launched_now:
		# A bright "ting" as they pop out (once per batch, not per coin).
		_clink(0.8, randf_range(1.25, 1.4))

## Something hit the counter: coins lying on it hop and clatter again,
## more the closer they are to where it hit (3D x).
func jolt(origin_x: float, strength: float) -> void:
	for c in _coins:
		if not c.settled:
			continue
		var coin: Node3D = c.node
		var near := clampf(1.0 - absf(coin.position.x - origin_x) / 2.0, 0.3, 1.0) * strength
		c.settled = false
		c.velocity = Vector3(randf_range(-0.25, 0.25), randf_range(0.9, 1.3) * near, randf_range(-0.1, 0.15))
		c.spin_axis = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		c.spin = randf_range(6.0, 12.0) * near

## Settled coins creep downhill when the ship leans hard enough.
func _drift(c: Dictionary, delta: float) -> void:
	var coin: Node3D = c.node
	var drift: float = c.get("drift", 0.0)
	var pull := Sea.counter_pull()
	if absf(pull) > drift_static:
		drift += pull * delta
	drift *= exp(-4.0 * delta)
	c.drift = drift
	coin.position.x = clampf(coin.position.x + drift * delta, counter_min.x, counter_max.x)

## Lay it flat (face up, random turn) once it stops bouncing.
func _settle(c: Dictionary) -> void:
	c.settled = true
	var coin: Node3D = c.node
	var flat := Basis(Vector3.UP, randf() * TAU).scaled(Vector3.ONE * coin_scale)
	create_tween().tween_property(coin, "basis", flat, 0.15)
	coin.position.y = 0.009 # the model hangs below its origin; this keeps it on the counter

## pitch: 0 = the usual slight random variation.
func _clink(strength: float, pitch: float = 0.0) -> void:
	for player in _players:
		if not player.playing:
			player.stream = CLINKS.pick_random()
			player.volume_db = linear_to_db(strength)
			player.pitch_scale = pitch if pitch > 0.0 else randf_range(0.95, 1.1)
			player.play()
			return

## Collect the coin under a click, if any. Returns true if one was taken.
func try_collect(screen: Vector2) -> bool:
	var camera := get_viewport().get_camera_3d()
	for i in range(_coins.size() - 1, -1, -1):
		var c: Dictionary = _coins[i]
		var coin: Node3D = c.node
		if not coin.visible:
			continue
		var on_screen := camera.unproject_position(coin.global_position)
		if on_screen.distance_to(screen) <= click_radius:
			_coins.remove_at(i)
			coin.queue_free()
			collected.emit(on_screen)
			return true
	return false

## Sweep every coin off the counter (e.g. a new night).
func clear() -> void:
	for c in _coins:
		(c.node as Node3D).queue_free()
	_coins.clear()

func count() -> int:
	return _coins.size()

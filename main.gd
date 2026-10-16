extends Node2D

## The bar: customers come in one at a time, chat, and order a beer. Pour it
## at the tap and set it down (or flick it) in front of her; she judges how
## full it is and how much you spilled, reacts, drinks, tosses a tip on the
## counter and leaves. Click the coins to collect them.
##
## Each character's lines live in its CustomerData resource
## (customer/lizard.tres, cat.tres); expand them under Customers in the
## Inspector of the Main node to edit.
##
## Controls: drag the tankard, hover the left edge for the tap, click a
## customer to poke her, click elsewhere / Space to advance dialogue,
## 1 / 2 to call a specific customer, N to skip to the end of the day,
## R to restart.

const CUSTOMER_SCENE: PackedScene = preload("res://customer/customer.tscn")

enum Phase { ARRIVING, TALKING, WAITING, REACTING, LEAVING }
enum Mood { ANGRY, MEH, HAPPY }
## How a served drink is rated: shown as a word on screen and tallied on the night card.
enum Rating { PERFECT, GOOD, MEH, SPILLED, BAD, EMPTY }

## Per rating: the word that pops up, its color and size (1 = full size).
const RATING_STYLES := {
	Rating.PERFECT: ["SHUKAR!", Color(1, 0.85, 0.35), 1.0],
	Rating.GOOD: ["MISHTO!", Color(1, 0.93, 0.65), 0.8],
	Rating.MEH: ["meh...", Color(0.75, 0.72, 0.68), 0.65],
	Rating.SPILLED: ["TULAI!", Color(1, 0.45, 0.2), 0.8],
	Rating.BAD: ["AOLEU!", Color(0.9, 0.15, 0.1), 0.8],
	Rating.EMPTY: ["DUMNEZO", Color(0.9, 0.15, 0.1), 0.9],
}
## How she drinks, per mood: gulps, seconds per gulp, pause between gulps,
## gulp strength. Happy chugs, meh sips, angry takes one grudging swig.
const DRINK_STYLES := {
	Mood.HAPPY: [4, 0.22, 0.1, 1.0],
	Mood.MEH: [2, 0.5, 0.45, 0.5],
	Mood.ANGRY: [1, 0.4, 0.0, 1.3],
}

@export var customers: Array[CustomerData] = [
	preload("res://customer/lizard.tres"),
	preload("res://customer/cat.tres"),
]
## Which of the customers above walk in on their own (the names must follow
## the list order). The 1 / 2 keys can still call anyone. None ticked = all.
@export_flags("Lizard", "Cat") var arriving: int = 1
@export var enter_x: float = -140.0
## Real seconds the clock takes to go from the start of the day to night.
@export var day_seconds: float = 120.0
## How far into the day (0..1) the sky starts turning to night.
@export var dusk_start: float = 0.5

@export_group("Nightly costs")
## Paid from all your lei at the end of each day; both go up every night.
@export var drinks_cost_base: int = 3
@export var drinks_cost_per_night: int = 2
@export var fuel_cost_base: int = 2
@export var fuel_cost_per_night: int = 2

@export_group("Judging")
## Fill at or above this counts as a proper pour.
@export var good_fill: float = 0.85
@export var okay_fill: float = 0.5
## Spilling more than this (fraction of a full tankard) costs one mood step.
@export var messy_spill: float = 0.25
## How far (3D units, sideways) from her the drink may land and still count as served.
@export var serve_reach: float = 0.5

@export_group("Kisses")
## A pour counts as perfect at or above this fill, spilling no more than this.
## Every perfect beer gets you a kiss on the screen.
@export var perfect_fill: float = 0.9
@export var perfect_spill: float = 0.1
## Bonus lei that fly out of the kiss.
@export var kiss_bonus: int = 2
@export_group("")
## Lei per tankard that fell off the counter, paid on the night's receipt.
@export var broken_tankard_cost: int = 2
## Slapstick screen shake when one smashes: how hard (pixels) and how long it
## takes to die down (seconds).
@export var break_shake_pixels: float = 9.0
@export var break_shake_seconds: float = 0.7## Where she pushes the empty: this far to her side (3D units), clear of her chest.
@export var set_aside_distance: float = 0.9
## How snappy that shove is: higher = faster and shorter glide.
@export var set_aside_friction: float = 7.0

@onready var _bubble: Node2D = $SpeechBubble
@onready var _props: Node2D = $BarProps
@onready var _coins: Node3D = $BarProps/SubViewport/Coins
@onready var _money: Node2D = $MoneyHud
@onready var _music: AudioStreamPlayer = $Music
@onready var _clock: Control = $ShiftClock
@onready var _card: CanvasLayer = $NightCard
@onready var _night_sky: Sprite2D = $Sky/SkyNight
@onready var _kisses: CanvasLayer = $KissLayer
@onready var _ship_view: Node = $ShipView

var _customer: Node2D
var _next_index := 0
var _phase := Phase.ARRIVING
var _served_item: Node3D
var _mood := Mood.MEH
var _rating := Rating.MEH
## How many drinks got each rating today (indexed by Rating).
var _tally: Array[int] = []
## Tankards smashed today.
var _broken := 0
## Which night it is (0 until the first night card).
var night := 0
var _day_time := 0.0
var _day_running := true
## Money at the start of the day, to show what this day earned.
var _day_start_money := 0
## She finished the drink and pushed the empty tankard aside.
var _drink_done := true
## Per character: how many times she's visited, and which dialogue set she used last.
var _visits := {}
var _last_set := {}

func _ready() -> void:
	_bubble.line_started.connect(_on_line_started)
	_bubble.last_line_shown.connect(_on_last_line_shown)
	_bubble.finished.connect(_on_dialogue_finished)
	_props.item_settled.connect(_on_item_settled)
	_props.item_broke.connect(_on_item_broke)
	_coins.collected.connect(_money.fly_coin)
	_music.finished.connect(_music.play) # placeholder track: just loop it
	_tally.resize(Rating.size())
	_spawn(_next_arriving(-1))

func _process(delta: float) -> void:
	if not _day_running:
		return
	_day_time += delta
	var progress := _day_time / day_seconds
	_clock.show_progress(progress)
	# Dusk: the night sky slowly fades in over the day sky.
	_night_sky.modulate.a = smoothstep(dusk_start, 1.0, progress)
	if _day_time >= day_seconds:
		_end_day()

## Night falls: pause, pay the bills on the title card, reset the bar while
## it's black, next day. Can't pay: game over, start again from scratch.
func _end_day() -> void:
	_day_running = false
	await _lights_out()
	var drinks := drinks_cost_base + drinks_cost_per_night * night
	var fuel := fuel_cost_base + fuel_cost_per_night * night
	var earned: int = _money.money - _day_start_money
	var broken_cost := _broken * broken_tankard_cost
	var left: int = _money.money - drinks - fuel - broken_cost
	_card.blacked_out.connect(_reset_bar, CONNECT_ONE_SHOT)
	await _card.play(night, _tally_text(), earned, drinks, fuel, _broken, broken_cost, left)
	if left < 0:
		# Still under the waves from the night card: start over behind them.
		Transition.reload_scene()
		return
	_money.set_money(left)
	night += 1
	_day_time = 0.0
	_day_start_money = left
	_clock.show_progress(0.0)
	get_tree().paused = false
	_day_running = true

## Today's drinks for the night card, e.g. "2 SHUKAR!  1 meh...". Only
## ratings that happened are listed.
func _tally_text() -> String:
	var parts := PackedStringArray()
	for rating in Rating.size():
		if _tally[rating] > 0:
			parts.append("%d %s" % [_tally[rating], RATING_STYLES[rating][0]])
	return "  ".join(parts) if not parts.is_empty() else "No drinks served"

## Closing time: everything freezes where it is and the lantern goes out at
## once. All black except the sea through the porthole and the customer's eye
## whites, which blink once. Leaves the game paused (for the night card).
func _lights_out() -> void:
	get_tree().paused = true
	_set_lights(0.0)
	# These timers run while paused (process_always), so the blink still happens.
	await get_tree().create_timer(0.9).timeout
	if is_instance_valid(_customer):
		_customer.blink()
	await get_tree().create_timer(0.9).timeout

## Room brightness, 1 = lit, 0 = lights out. The sky and sea aren't touched.
func _set_lights(level: float) -> void:
	for node: CanvasItem in [$Background, $Counter, $TapTray, $BarProps, $SpeechBubble, $MoneyHud, $ShiftClock]:
		node.modulate = Color(level, level, level, node.modulate.a)
	_kisses.set_brightness(level)
	if is_instance_valid(_customer):
		_customer.set_lights_out(1.0 - level)

func _reset_bar() -> void:
	_set_lights(1.0)
	_night_sky.modulate.a = 0.0
	_kisses.clear() # the waves washed them off
	_tally.fill(0)
	_broken = 0
	_coins.clear()
	_props.reset_props()
	_spawn(_next_arriving(-1))

func _spawn(index: int) -> void:
	_bubble.stop()
	if is_instance_valid(_served_item):
		_props.lower_from_drink(_served_item) # if she was mid-drink
		_props.set_locked(_served_item, false)
	_served_item = null
	_drink_done = true
	if is_instance_valid(_customer):
		_customer.queue_free()
	var customer := CUSTOMER_SCENE.instantiate()
	customer.data = customers[index]
	customer.position.x = enter_x
	customer.seated.connect(_on_customer_seated.bind(customer))
	customer.left.connect(_on_customer_left.bind(customer))
	customer.slammed.connect(_on_slammed.bind(customer))
	add_child(customer)
	move_child(customer, $Counter.get_index())
	_customer = customer
	_next_index = _next_arriving(index)
	_phase = Phase.ARRIVING

## The next customer after index (in list order, wrapping) that's ticked in
## arriving; the same one again if she's the only one.
func _next_arriving(index: int) -> int:
	for i in range(1, customers.size() + 1):
		var next := posmod(index + i, customers.size())
		if arriving == 0 or arriving & (1 << next):
			return next
	return posmod(index + 1, customers.size())

func _on_customer_seated(customer: Node2D) -> void:
	await get_tree().create_timer(0.5).timeout
	if customer != _customer:
		return
	_phase = Phase.TALKING
	var data: CustomerData = customer.data
	_bubble.start(_pick_dialogue(data), data.voice_pitch, data.text_speed, true)

## Small talk + order for this visit. Set 0 is her first-visit talk, then her
## extra sets; each is used once in order, after that random, never repeating
## the last one.
func _pick_dialogue(data: CustomerData) -> PackedStringArray:
	var count := 1 + data.extra_sets.size()
	var visit: int = _visits.get(data, 0)
	_visits[data] = visit + 1
	var pick := visit
	if visit >= count:
		pick = randi() % count
		if count > 1 and pick == _last_set.get(data, -1):
			pick = (pick + 1) % count
	_last_set[data] = pick
	var lines: PackedStringArray
	var order := data.order_line
	if pick == 0:
		lines = data.lines.duplicate()
	else:
		var dialogue_set := data.extra_sets[pick - 1]
		lines = dialogue_set.lines.duplicate()
		if not dialogue_set.order_line.is_empty():
			order = dialogue_set.order_line
	lines.append(order)
	return lines

func _on_line_started(_index: int) -> void:
	if is_instance_valid(_customer):
		_customer.bounce()

## She has ordered: now wait for a drink (one may already be in front of her).
func _on_last_line_shown() -> void:
	if _phase != Phase.TALKING:
		return
	_phase = Phase.WAITING
	for item: Node3D in _props.items():
		_on_item_settled(item)

func _on_item_settled(item: Node3D) -> void:
	if _phase != Phase.WAITING or _props.liquid_of(item) == null:
		return
	if _in_front_of_customer(item):
		_serve(item)

## A tankard fell off the end of the counter and smashed: a jolt of the view
## (the shards and the new tankard are BarProps' job); it's paid at night.
func _on_item_broke(_item: Node3D, _at: Vector2) -> void:
	_broken += 1
	_ship_view.shake(break_shake_pixels, break_shake_seconds)
	if is_instance_valid(_customer) and _customer.is_seated():
		_customer.nervous()

func _in_front_of_customer(item: Node3D) -> bool:
	var her: Vector3 = _props.counter_point(Vector2(_customer.position.x, 270.0))
	var drink: Vector3 = _props.counter_position(item)
	# Sideways close to her, and not right at the front edge (that's your side).
	return absf(drink.x - her.x) < serve_reach and drink.z < -3.2

func _serve(item: Node3D) -> void:
	_phase = Phase.REACTING
	_served_item = item
	_props.set_locked(item, true)
	var liquid: Node = _props.liquid_of(item)
	var data: CustomerData = _customer.data
	var line := _judge(liquid.fill, liquid.spilled_total, data)
	_bubble.stop()
	_bubble.start(PackedStringArray([line]), data.voice_pitch, data.text_speed)
	_customer.react(_mood)
	if _mood == Mood.ANGRY:
		_customer.nervous()
	var perfect: bool = liquid.fill >= perfect_fill and liquid.spilled_total <= perfect_spill
	print("Served: fill %.3f (need >= %.2f), spilled %.3f (need <= %.2f) -> perfect: %s" \
		% [liquid.fill, perfect_fill, liquid.spilled_total, perfect_spill, perfect])
	if perfect:
		_rating = Rating.PERFECT
		_customer.wink() # instead of the happy squint
	_tally[_rating] += 1
	var style: Array = RATING_STYLES[_rating]
	_kisses.shout(style[0], style[1], style[2])
	_drink_done = false
	_finish_drink(item, liquid.fill > 0.0, perfect)

## A perfect beer earned a kiss: she leans in and smacks one on the screen,
## and a couple of bonus lei fly from the print into the money counter.
func _kiss(customer: Node2D) -> void:
	await get_tree().create_timer(0.7).timeout # after her happy hops
	if customer != _customer or not customer.is_seated():
		return
	customer.blow_kiss()
	await customer.kiss_landed
	var spot: Vector2 = _kisses.stamp()
	_ship_view.shake(4.0)
	for i in kiss_bonus:
		_money.fly_coin(spot)
		await get_tree().create_timer(0.12).timeout

## Kiss first if it was perfect, then drink it. Happy: she swings the empty
## out to the side at mouth height and slams it down there. Otherwise she
## sets it down and shoves it out of the way.
func _finish_drink(item: Node3D, has_drink: bool, kiss: bool) -> void:
	var customer := _customer
	if kiss:
		await _kiss(customer)
	var raised := false
	if has_drink and customer == _customer and is_instance_valid(item):
		raised = await _drink(item, customer)
	else:
		await get_tree().create_timer(0.6).timeout
	if customer != _customer or not is_instance_valid(item):
		_drink_done = true
		return
	if raised and _mood == Mood.HAPPY:
		_props.slam_from_drink(item, _aside_x(customer))
		await _props.slammed_down
		if customer == _customer:
			customer.slam_bounce()
			await get_tree().create_timer(0.3).timeout
	else:
		if raised:
			await _lower(item, customer)
			if customer != _customer:
				_drink_done = true
				return
			if _mood == Mood.ANGRY:
				customer.react(Mood.ANGRY) # a sour stomp
			await get_tree().create_timer(0.4).timeout
		_set_aside(item, customer)
		while _props.is_sliding(item):
			await get_tree().process_frame
	_drink_done = true

## She raises the tankard to her mouth and empties it in gulps (how depends
## on her mood, see DRINK_STYLES). Returns true if it's still up at her mouth.
func _drink(item: Node3D, customer: Node2D) -> bool:
	var liquid: Node = _props.liquid_of(item)
	await get_tree().create_timer(0.3).timeout
	if customer != _customer or not _props.raise_to_drink(item, customer.mouth_screen_position()):
		liquid.fill = 0.0
		return false
	customer.start_drinking()
	await get_tree().create_timer(0.45).timeout # up at her lips
	var style: Array = DRINK_STYLES[_mood]
	var gulps: int = style[0]
	var sip: float = liquid.fill / gulps
	for i in gulps:
		if customer != _customer:
			return false
		liquid.gulp(liquid.fill if i == gulps - 1 else sip, style[1])
		_props.gulp_nudge()
		customer.gulp(style[3])
		await get_tree().create_timer(style[1] + style[2]).timeout
	if customer != _customer:
		return false
	customer.finish_drinking(_mood != Mood.ANGRY)
	if _mood == Mood.HAPPY:
		customer.ahh()
		await get_tree().create_timer(0.35).timeout
	return customer == _customer

## Set a raised tankard back down on the counter and wait until it's there.
func _lower(item: Node3D, customer: Node2D) -> void:
	_props.lower_from_drink(item)
	while _props.is_drinking(item) and customer == _customer:
		await get_tree().process_frame

## Where (3D x on the counter) she puts the empty: to a random side of her,
## the other side if that one would run off the counter.
func _aside_x(customer: Node2D) -> float:
	var her: Vector3 = _props.counter_point(Vector2(customer.position.x, 270.0))
	var side := -1.0 if randf() < 0.5 else 1.0
	var target_x := her.x + side * set_aside_distance
	if target_x < _props.counter_min.x or target_x > _props.counter_max.x:
		target_x = her.x - side * set_aside_distance
	return target_x

## Shove the tankard to _aside_x(). A slide covers velocity / friction.
func _set_aside(item: Node3D, customer: Node2D) -> void:
	var from: Vector3 = _props.counter_position(item)
	_props.push(item, Vector3((_aside_x(customer) - from.x) * set_aside_friction, 0.0, 0.0), set_aside_friction)

func _on_slammed(strength: float, customer: Node2D) -> void:
	var her: Vector3 = _props.counter_point(Vector2(customer.position.x, 270.0))
	_props.jolt(her.x, strength)
	_coins.jolt(her.x, strength)

## Sets the mood and rating (perfect is decided by the caller) and returns
## what she says about the drink.
func _judge(fill: float, spilled: float, data: CustomerData) -> String:
	if fill < 0.05:
		_mood = Mood.ANGRY
		_rating = Rating.EMPTY
		return data.empty_line
	if fill >= good_fill:
		_mood = Mood.HAPPY
	elif fill >= okay_fill:
		_mood = Mood.MEH
	else:
		_mood = Mood.ANGRY
	if spilled > messy_spill and _mood > Mood.ANGRY:
		_mood = (_mood - 1) as Mood
		_rating = Rating.SPILLED
	else:
		_rating = [Rating.BAD, Rating.MEH, Rating.GOOD][_mood]
	match _mood:
		Mood.HAPPY:
			return Array(data.happy_lines).pick_random()
		Mood.MEH:
			return Array(data.meh_lines).pick_random()
		_:
			return Array(data.angry_lines).pick_random()

func _on_dialogue_finished() -> void:
	if _phase == Phase.REACTING:
		_tip_and_leave()

func _tip_and_leave() -> void:
	_phase = Phase.LEAVING
	var customer := _customer
	var data: CustomerData = customer.data
	var tip := data.tip_good if _mood == Mood.HAPPY else (data.tip_meh if _mood == Mood.MEH else 0)
	# Tip once the tankard is out of the way, so the coins are seen coming out.
	while not _drink_done and customer == _customer:
		await get_tree().process_frame
	if customer != _customer:
		return
	await get_tree().create_timer(0.8).timeout
	if tip > 0:
		# The whole handful bursts out of her cleavage at once, with one big chest pop.
		var from: Vector3 = _props.world_point_at_depth(customer.cleavage_screen_position(), -3.9)
		_coins.toss(from, tip, 1.5, 0.0)
		customer.chest_pop()
		customer.wink()
	await get_tree().create_timer(1.0).timeout
	while not _drink_done and customer == _customer:
		await get_tree().process_frame
	if customer != _customer:
		return
	if is_instance_valid(_served_item):
		_props.set_locked(_served_item, false)
	customer.stand_up()

func _on_customer_left(customer: Node2D) -> void:
	if customer == _customer:
		_spawn(_next_index)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_instance_valid(_customer) and _customer.is_seated() \
				and _customer.hit_test(event.position):
			_customer.poke()
		else:
			_bubble.advance()
	elif event.is_action_pressed("ui_accept"):
		_bubble.advance()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1:
				_spawn(0)
			KEY_2:
				_spawn(1)
			KEY_N:
				_day_time = day_seconds
			KEY_R:
				Transition.reload_scene()

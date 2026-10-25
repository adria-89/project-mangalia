extends Node2D

## The bar: customers come in one at a time, chat, and order a drink (a
## Recipe: beer, a Mangaliene...; what she orders depends on her tastes in
## CustomerData, how drunk she is and what the bar has unlocked by tonight).
## Pour it at the tap and the bottle crate and set it down (or flick it) in
## front of her; she judges how full it is, how much you spilled, the mix and,
## for layered drinks, the layers. She reacts, drinks, tosses a tip on the
## counter and leaves. Click the coins to collect them.
##
## Each character's lines live in its CustomerData resource
## (customer/lizard.tres, cat.tres, strigoi.tres); expand them under
## Customers in the Inspector of the Main node to edit.
##
## Night 0 opens with the boss (Intro > boss): he says his piece, leaves you
## the bar and walks out. New drinks are taught by the girls (CustomerData >
## Lessons): nobody orders one before its teacher has.
##
## Controls: drag the tankard, hover the left edge for the tap, click a
## customer to poke her, click elsewhere / Space to advance dialogue,
## F1 for the debug overlay and its keys (autoloads/debug.gd).

const CUSTOMER_SCENE: PackedScene = preload("res://customer/customer.tscn")

enum Phase { ARRIVING, TALKING, WAITING, REACTING, LEAVING }
enum Mood { ANGRY, MEH, HAPPY }
## How a served drink is rated: shown as a word on screen and tallied on the night card.
enum Rating { PERFECT, GOOD, MEH, SPILLED, BAD, EMPTY }

## Per rating: the word that pops up, its color and size (1 = full size).
const RATING_STYLES := {
	Rating.PERFECT: ["ȘUKAR!", Color(1, 0.85, 0.35), 1.0],
	Rating.GOOD: ["MIȘTO!", Color(1, 0.93, 0.65), 0.8],
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
	preload("res://customer/strigoi.tres"),
]
## Which of the customers above walk in on their own (the names must follow
## the list order). The 1 / 2 / 3 debug keys can still call anyone. None
## ticked = all. Ones still on placeholder art (CustomerData.placeholder) only
## walk in with the debug P toggle, ticked or not.
@export_flags("Lizard", "Cat", "Strigoi") var arriving: int = 1
@export var enter_x: float = -140.0
## Opens the first day: sits down, says his lines (no order), leaves you the
## bar and walks out. The clock waits for him. Empty = straight to the girls.
@export var boss: CustomerData = preload("res://customer/callimachi.tres")
## The cola crate and the rum bundle stay put away until a drink with theirs
## in it can be ordered (unlocked and taught).
@export var crate_drink: Drink = preload("res://props/drinks/cola.tres")
@export var rope_drink: Drink = preload("res://props/drinks/rum.tres")
## How hard he backhands a drink you push at him mid-speech (3D units/second).
## It usually flies off the end; that tankard isn't on your bill.
@export var swat_speed: float = 12.0
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

@export_group("Nights")
## How rough the sea is each night (Sea.strength: 0 calm .. 2 storm), the
## first night first; nights past the end keep the last one.
@export var sea_by_night: PackedFloat32Array = [0.4, 0.7, 1.0, 1.4, 1.8]
## The sea builds up over the day: this much rougher by nightfall (0.25 = +25%).
@export var sea_build_up: float = 0.25
## How fast the sea changes toward that (strength per second), so it never jumps.
@export var sea_change_speed: float = 0.1
## Every drink the bar serves: now and then she tries one off her own list.
@export var menu: Array[Recipe] = [
	preload("res://props/recipes/beer.tres"),
	preload("res://props/recipes/rum.tres"),
	preload("res://props/recipes/cola.tres"),
	preload("res://props/recipes/cuba_libre.tres"),
	preload("res://props/recipes/motorina.tres"),
	preload("res://props/recipes/prenadez.tres"),
	preload("res://props/recipes/mangaliene.tres"),
]
## Chance she orders a drink that's new on the menu tonight (curious).
@export_range(0.0, 1.0) var new_drink_chance: float = 0.35
## Added to each customer's sometimes_chance every night.
@export var sometimes_per_night: float = 0.05
## Chance per night (night 3 = 3x) that she tries something not on her list.
@export var try_other_per_night: float = 0.08
## None of these chances go above this, so favorites still come up.
@export_range(0.0, 1.0) var max_variety: float = 0.6

@export_group("Judging")
## Ordered when a customer has no favorite (and on the first night).
@export var default_recipe: Recipe = preload("res://props/recipes/beer.tres")
## Fill at or above this counts as a proper pour.
@export var good_fill: float = 0.85
@export var okay_fill: float = 0.5
## Spilling more than this (fraction of a full tankard) costs one mood step.
@export var messy_spill: float = 0.25
## How far (3D units, sideways) from her the drink may land and still count as served.
@export var serve_reach: float = 0.5
## Seconds a drink must sit in front of her before she takes it: pick it back
## up in time to change your mind.
@export var serve_delay: float = 0.6
## How far the mix may be off the recipe (0..1, see Recipe.difference)
## before it costs a mood step, and before it's the wrong drink altogether.
@export var close_mix: float = 0.15
@export var wrong_mix: float = 0.5
## A layered drink needs its layers this clean (0..1) and in the right order,
## or it costs a mood step.
@export var clean_layers: float = 0.75
## Layers thinner than this (fraction of full) don't count for the order.
@export var min_layer: float = 0.03

@export_group("Kisses")
## A pour counts as perfect at or above this fill, spilling no more than this.
## Every perfect beer gets you a kiss on the screen.
@export var perfect_fill: float = 0.9
@export var perfect_spill: float = 0.1
## ...and with the mix this close, and layers (if any) this clean.
@export var perfect_mix: float = 0.1
@export var perfect_layers: float = 0.9
## Bonus lei that fly out of the kiss.
@export var kiss_bonus: int = 2
@export_group("Affection")
## What each girl's bar holds (shown on the night card). Full = she'd ask you
## to stay after closing.
@export var affection_max: float = 10.0
## Per drink, by how she took it: a ȘUKAR! (the kiss), happy, meh, angry.
@export var affection_perfect: float = 2.0
@export var affection_happy: float = 1.0
@export var affection_meh: float = 0.0
@export var affection_angry: float = -1.0
## Extra when it was her favorite and she liked it.
@export var affection_favorite: float = 0.5
## Extra (on top of angry) when you served the one she hates.
@export var affection_hated: float = -1.0
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
## Set down in front of her, taken once _serve_left runs out (see serve_delay).
var _pending_serve: Node3D
var _serve_left := 0.0
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
## Beers each regular has had tonight (keyed by CustomerData). Slept off overnight.
var _drunk := {}
## What the current customer ordered.
var _order: Recipe
## What each regular ordered last (keyed by CustomerData).
var _last_order := {}
## Names of the drinks the girls have taught you so far (see CustomerData.lessons).
var _taught := {}
## Each girl you've met: her affection (0..affection_max), and what it was
## when the day started (the night card fills her bar from there).
var _affection := {}
var _affection_start := {}
## The last drink judged was the one she hates.
var _got_hated := false
## Tankards the boss knocked away (see _swat()).
var _swatted := {}

func _ready() -> void:
	_bubble.line_started.connect(_on_line_started)
	_bubble.last_line_shown.connect(_on_last_line_shown)
	_bubble.finished.connect(_on_dialogue_finished)
	_props.item_settled.connect(_on_item_settled)
	_props.item_broke.connect(_on_item_broke)
	_coins.collected.connect(_money.fly_coin)
	_music.finished.connect(_music.play) # placeholder track: just loop it
	_tally.resize(Rating.size())
	_load_run()
	Sea.strength = _sea_tonight()
	Debug.info = _debug_info
	_update_stations()
	if boss != null and not SaveManager.intro_seen:
		_day_running = false
		_add_customer(boss)
		_next_index = _next_arriving(-1)
	else:
		_spawn(_next_arriving(-1))

func _process(delta: float) -> void:
	_update_pending_serve(delta)
	if not _day_running:
		return
	_day_time += delta
	var progress := _day_time / day_seconds
	var sea := _sea_tonight() * (1.0 + sea_build_up * minf(progress, 1.0))
	if Debug.sea >= 0.0:
		sea = Debug.sea
	Sea.strength = move_toward(Sea.strength, sea, sea_change_speed * delta)
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
	await _card.play(night, _tally_text(), earned, drinks, fuel, _broken, broken_cost, left, _affection_rows())
	_affection_start = _affection.duplicate()
	if left < 0:
		# Still under the waves from the night card: back to this morning's save behind them.
		SaveManager.load_game()
		Transition.reload_scene()
		return
	_money.set_money(left)
	night += 1
	_update_stations()
	_day_time = 0.0
	_day_start_money = left
	_save_run()
	_clock.show_progress(0.0)
	get_tree().paused = false
	_day_running = true

## The day starts from SaveManager's run: the night, the money, each girl's
## affection and talk so far, and what the girls have taught.
func _load_run() -> void:
	night = SaveManager.night
	_money.set_money(SaveManager.money)
	_day_start_money = SaveManager.money
	for data in customers:
		var id := SaveManager.id_of(data)
		if SaveManager.affection.has(id):
			_affection[data] = SaveManager.affection[id]
		if SaveManager.visits.has(id):
			_visits[data] = SaveManager.visits[id]
		if SaveManager.last_set.has(id):
			_last_set[data] = SaveManager.last_set[id]
	_affection_start = _affection.duplicate()
	for drink_name in SaveManager.taught:
		_taught[drink_name] = true

## A new morning: the run so far goes into a fresh save.
func _save_run() -> void:
	SaveManager.night = night
	SaveManager.money = _money.money
	SaveManager.intro_seen = true # every morning comes after his speech
	SaveManager.affection.clear()
	SaveManager.visits.clear()
	SaveManager.last_set.clear()
	for data: CustomerData in _affection:
		SaveManager.affection[SaveManager.id_of(data)] = _affection[data]
		if _affection[data] >= affection_max:
			SaveManager.win_over(data)
	for data: CustomerData in _visits:
		SaveManager.visits[SaveManager.id_of(data)] = _visits[data]
	for data: CustomerData in _last_set:
		SaveManager.last_set[SaveManager.id_of(data)] = _last_set[data]
	SaveManager.taught.assign(_taught.keys())
	SaveManager.save_game()

## Today's drinks for the night card, e.g. "2 ȘUKAR!  1 meh...". Only
## ratings that happened are listed.
func _tally_text() -> String:
	var parts := PackedStringArray()
	for rating in Rating.size():
		if _tally[rating] > 0:
			parts.append("%d %s" % [_tally[rating], RATING_STYLES[rating][0]])
	return "  ".join(parts) if not parts.is_empty() else "No drinks served"

## A row per girl met so far, in list order, for the night card: her head,
## her color, and her bar at the start and end of today (0..1).
func _affection_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for data in customers:
		if _affection.has(data):
			rows.append({
				"head": data.head(),
				"color": data.color,
				"from": _affection_start.get(data, 0.0) / affection_max,
				"to": _affection[data] / affection_max,
			})
	return rows

## How she took the drink moves her affection (see Affection in the inspector).
func _add_affection(data: CustomerData, perfect: bool, favorite: bool) -> void:
	var change: float = [affection_angry, affection_meh, affection_happy][_mood]
	if perfect:
		change = affection_perfect
	if favorite and _mood == Mood.HAPPY:
		change += affection_favorite
	if _got_hated:
		change += affection_hated
	_affection[data] = clampf(_affection.get(data, 0.0) + change, 0.0, affection_max)

## Closing time: the lantern flickers and fades out (you can still play
## meanwhile), then everything freezes where it is. All black except the sea
## through the porthole and the customer's eye whites, which blink once. Leaves
## the game paused (for the night card).
func _lights_out() -> void:
	var tween := create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	# Flicker: a few quick dips, then it dies.
	var from := 1.0
	for level: float in [0.35, 0.9, 0.2, 0.7]:
		tween.tween_method(_set_lights, from, level, 0.06)
		tween.tween_interval(0.08)
		from = level
	tween.tween_method(_set_lights, from, 0.0, 0.45).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	await tween.finished
	get_tree().paused = true
	# These timers run while paused (process_always), so the blink still happens.
	await get_tree().create_timer(0.9).timeout
	if is_instance_valid(_customer):
		_customer.blink()
	await get_tree().create_timer(0.9).timeout

## Room brightness, 1 = lit, 0 = lights out. The sky and sea aren't touched.
func _set_lights(level: float) -> void:
	for node: CanvasItem in [$Background, $Counter, $TapTray, $BottleRail, $RumRope, $BarProps, $SpeechBubble, $MoneyHud, $ShiftClock]:
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
	_drunk.clear()
	_coins.clear()
	_props.reset_props()
	$BottleRail.restock()
	$RumRope.restock()
	_spawn(_next_arriving(-1))

func _spawn(index: int) -> void:
	_add_customer(customers[index])
	_next_index = _next_arriving(index)

## Clears the counter of whoever was there and sends this one walking in.
func _add_customer(data: CustomerData) -> void:
	_bubble.stop()
	if is_instance_valid(_served_item):
		_props.lower_from_drink(_served_item) # if she was mid-drink
		_props.set_locked(_served_item, false)
	_served_item = null
	_pending_serve = null
	_drink_done = true
	if _is_boss(_customer):
		_day_running = true # a debug key called someone in over him
	if is_instance_valid(_customer):
		_customer.queue_free()
	var customer := CUSTOMER_SCENE.instantiate()
	customer.data = data
	customer.drunk = _drunk.get(data, 0.0)
	# Wide ones (the boss) start further out, so they don't pop in on screen.
	customer.position.x = minf(enter_x, -data.texture.get_width() / 2.0 * customer.display_scale)
	customer.seated.connect(_on_customer_seated.bind(customer))
	customer.left.connect(_on_customer_left.bind(customer))
	customer.slammed.connect(_on_slammed.bind(customer))
	add_child(customer)
	move_child(customer, $Counter.get_index())
	_customer = customer
	_phase = Phase.ARRIVING

## The next customer after index (in list order, wrapping) that walks in on
## her own; the same one again if she's the only one.
func _next_arriving(index: int) -> int:
	for i in range(1, customers.size() + 1):
		var next := posmod(index + i, customers.size())
		if _walks_in(next):
			return next
	return posmod(index + 1, customers.size())

## Ticked in arriving (or none are), and not on placeholder art unless the
## debug P toggle lets those in.
func _walks_in(index: int) -> bool:
	if customers[index].placeholder:
		return Debug.placeholders
	return arriving == 0 or arriving & (1 << index)

func _is_boss(customer: Node2D) -> bool:
	return is_instance_valid(customer) and boss != null and customer.data == boss

func _on_customer_seated(customer: Node2D) -> void:
	await get_tree().create_timer(0.5).timeout
	if customer != _customer:
		return
	_phase = Phase.TALKING
	var data: CustomerData = customer.data
	if _is_boss(customer):
		_bubble.start(data.lines, data.voice_pitch, data.text_speed)
		return
	if not _affection.has(data):
		_affection[data] = 0.0 # met her: she gets a row on the night card
	_bubble.start(_pick_dialogue(data), data.voice_pitch, data.text_speed, true)

## Small talk + order for this visit. A drink she still has to teach you comes
## first (its lesson lines). Otherwise set 0 is her first-visit talk, then her
## extra sets; each is used once in order, after that random, never repeating
## the last one.
func _pick_dialogue(data: CustomerData) -> PackedStringArray:
	var lesson := _next_lesson(data)
	if lesson != null:
		_taught[lesson.name] = true
		_update_stations() # she's about to point at it
		_order = lesson
		_last_order[data] = lesson
		return data.lessons[lesson.name].duplicate()
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
	# Those order lines are for her favorite; anything else has its own.
	_order = _pick_order(data)
	if _order != _favorite(data):
		order = data.order_lines.get(_order.name, _order.order_line)
	lines.append(order)
	return lines

## Tonight's sea strength, before it builds up over the day.
func _sea_tonight() -> float:
	if sea_by_night.is_empty():
		return 1.0
	return sea_by_night[mini(night, sea_by_night.size() - 1)]

## What she orders this visit. Never the same odd drink twice in a row (her
## favorite can repeat).
func _pick_order(data: CustomerData) -> Recipe:
	var order := _roll_order(data)
	if order == _last_order.get(data) and order != _favorite(data):
		order = _roll_order(data)
	_last_order[data] = order
	return order

## Once she's drunk enough, mostly one of her drunk orders; otherwise maybe
## whatever is new on the menu tonight, one she sometimes has, or (more often
## every night) something else off the menu; else her favorite. Only drinks
## unlocked by tonight; never the one she hates or ones she won't try.
func _roll_order(data: CustomerData) -> Recipe:
	var drunk: float = _drunk.get(data, 0.0)
	var drunk_picks := _unlocked(data.drunk_orders, data)
	if drunk >= data.drunk_from and not drunk_picks.is_empty() and randf() < 0.7:
		return drunk_picks.pick_random()
	var favorite := _favorite(data)
	var others: Array[Recipe] = []
	var fresh: Array[Recipe] = []
	for recipe in _unlocked(menu, data):
		if recipe != favorite and recipe not in data.wont_try:
			others.append(recipe)
			if recipe.unlock_night == night:
				fresh.append(recipe)
	if not fresh.is_empty() and randf() < new_drink_chance:
		return fresh.pick_random()
	var sometimes := _unlocked(data.sometimes, data)
	var sometimes_chance := minf(data.sometimes_chance + sometimes_per_night * night, max_variety)
	if not sometimes.is_empty() and randf() < sometimes_chance:
		return sometimes.pick_random()
	if not others.is_empty() and randf() < minf(try_other_per_night * night, max_variety):
		return others.pick_random()
	if _is_unlocked(favorite):
		return favorite
	return default_recipe

func _favorite(data: CustomerData) -> Recipe:
	return data.favorite if data.favorite != null else default_recipe

## On the menu by tonight, and taught if anyone who walks in teaches it.
func _is_unlocked(recipe: Recipe) -> bool:
	return _on_menu(recipe) and not _needs_lesson(recipe)

func _on_menu(recipe: Recipe) -> bool:
	return Debug.unlock_all or recipe.unlock_night <= night

## Not taught yet, and its teacher walks in (one who doesn't can't hold it back).
func _needs_lesson(recipe: Recipe) -> bool:
	if _taught.has(recipe.name):
		return false
	for i in customers.size():
		if customers[i].lessons.has(recipe.name) and _walks_in(i):
			return true
	return false

## Brings out the crate / the rum once something with cola / rum can be ordered.
func _update_stations() -> void:
	$BottleRail.locked = not _serves(crate_drink)
	$RumRope.locked = not _serves(rope_drink)

func _serves(drink: Drink) -> bool:
	for recipe in menu:
		if drink in recipe.drinks and _is_unlocked(recipe):
			return true
	return false

## The first drink on the menu tonight that she has yet to teach, or null.
func _next_lesson(data: CustomerData) -> Recipe:
	for recipe in menu:
		if data.lessons.has(recipe.name) and not _taught.has(recipe.name) and _on_menu(recipe):
			return recipe
	return null

func _unlocked(recipes: Array[Recipe], data: CustomerData) -> Array[Recipe]:
	var result: Array[Recipe] = []
	for recipe in recipes:
		if _is_unlocked(recipe) and recipe != data.hated:
			result.append(recipe)
	return result

func _on_line_started(_index: int) -> void:
	if is_instance_valid(_customer):
		_customer.bounce()

## She has ordered: now wait for a drink (one may already be in front of her).
func _on_last_line_shown() -> void:
	if _phase != Phase.TALKING or _is_boss(_customer):
		return
	_phase = Phase.WAITING
	for item: Node3D in _props.items():
		_on_item_settled(item)

func _on_item_settled(item: Node3D) -> void:
	if _props.liquid_of(item) == null:
		return
	if _is_boss(_customer) and _customer.is_seated() and _props.placed_by_hand(item) \
			and _in_front_of_customer(item):
		_swat(item, _customer)
		return
	if _phase != Phase.WAITING:
		return
	# Only what you set down yourself: not a glass the sea slid over to her.
	if _props.placed_by_hand(item) and _in_front_of_customer(item):
		_pending_serve = item
		_serve_left = serve_delay

## She takes the drink once it's sat in front of her for serve_delay, unless
## it was picked back up or the sea moved it off meanwhile.
func _update_pending_serve(delta: float) -> void:
	if _pending_serve == null:
		return
	var item := _pending_serve
	if _phase != Phase.WAITING or _props.is_held(item) or not _props.placed_by_hand(item) \
			or not _in_front_of_customer(item):
		_pending_serve = null
		return
	_serve_left -= delta
	if _serve_left <= 0.0:
		_pending_serve = null
		_serve(item)

## A tankard fell off the end of the counter and smashed: a jolt of the view
## (the shards and the new tankard are BarProps' job); it's paid at night.
## A drink pushed at the boss mid-speech: he stomps and backhands it down the
## counter (it may well fly off the end and smash).
func _swat(item: Node3D, boss_node: Node2D) -> void:
	await get_tree().create_timer(0.25).timeout
	if boss_node != _customer or not is_instance_valid(item) or _props.is_held(item):
		return
	boss_node.react(Mood.ANGRY)
	boss_node.nervous()
	var from: Vector3 = _props.counter_position(item)
	var her: Vector3 = _props.counter_point(Vector2(boss_node.position.x, 270.0))
	var side := 1.0 if from.x >= her.x else -1.0
	_swatted[item] = true
	_props.push(item, Vector3(side * swat_speed, 0.0, 0.0), set_aside_friction * 0.3)

func _on_item_broke(item: Node3D, _at: Vector2) -> void:
	if not _swatted.erase(item): # the boss's doing isn't yours to pay
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
	var order := _order if _order != null else default_recipe
	var line := _judge(liquid, order, data)
	var forced := Debug.force_perfect
	if forced:
		Debug.force_perfect = false
		_mood = Mood.HAPPY
		line = (Array(data.happy_lines).pick_random() as String).format({"drink": order.name})
	_bubble.stop()
	_bubble.start(PackedStringArray([line]), data.voice_pitch, data.text_speed)
	_customer.react(_mood)
	if _mood == Mood.ANGRY:
		_customer.nervous()
	var mix: float = order.difference(liquid.composition())
	var layers := _layer_quality(liquid, order) if order.layered else 1.0
	var perfect: bool = forced or _mood == Mood.HAPPY and liquid.fill >= perfect_fill * order.fill \
		and liquid.spilled_total <= perfect_spill and mix <= perfect_mix and layers >= perfect_layers
	print("Served %s: fill %.3f (need >= %.2f), spilled %.3f (need <= %.2f), mix off %.2f, layers %.2f -> perfect: %s" \
		% [order.name, liquid.fill, perfect_fill * order.fill, liquid.spilled_total, perfect_spill, mix, layers, perfect])
	if perfect:
		_rating = Rating.PERFECT
		_customer.wink() # instead of the happy squint
	_add_affection(data, perfect, order == _favorite(data))
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
	var data: CustomerData = customer.data
	# Rum hits harder than beer, cola not at all (Drink.strength).
	var mix: Dictionary = liquid.composition()
	var booze := 0.0
	for drink: Drink in mix:
		booze += mix[drink] * drink.strength
	_drunk[data] = _drunk.get(data, 0.0) + booze
	customer.drunk = _drunk[data]
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
## what she says about the drink. How full (against what the order calls
## for) sets the mood; spilling a lot, a mix that's off and muddy layers
## each cost a step. Not her drink at all (or the one she hates): angry.
func _judge(liquid: Node, order: Recipe, data: CustomerData) -> String:
	var fill: float = liquid.fill / order.fill
	var spilled: float = liquid.spilled_total
	_got_hated = false
	if fill < 0.05:
		_mood = Mood.ANGRY
		_rating = Rating.EMPTY
		return data.empty_line
	var mix: Dictionary = liquid.composition()
	var off := order.difference(mix)
	if data.hated != null and data.hated != order and data.hated.difference(mix) < close_mix:
		_mood = Mood.ANGRY
		_rating = Rating.BAD
		_got_hated = true
		return data.hated_line
	if off > wrong_mix:
		_mood = Mood.ANGRY
		_rating = Rating.BAD
		return data.wrong_drink_line
	if fill >= good_fill:
		_mood = Mood.HAPPY
	elif fill >= okay_fill:
		_mood = Mood.MEH
	else:
		_mood = Mood.ANGRY
	var complaint := ""
	if off > close_mix and _mood > Mood.ANGRY:
		_mood = (_mood - 1) as Mood
		complaint = data.off_mix_line
	if order.layered and _layer_quality(liquid, order) < clean_layers and _mood > Mood.ANGRY:
		_mood = (_mood - 1) as Mood
		complaint = data.muddy_line
	if spilled > messy_spill and _mood > Mood.ANGRY:
		_mood = (_mood - 1) as Mood
		_rating = Rating.SPILLED
	else:
		_rating = [Rating.BAD, Rating.MEH, Rating.GOOD][_mood]
	if not complaint.is_empty():
		return complaint
	# Her own lines are about her favorite; anything else gets the other ones.
	var favorite := order == _favorite(data)
	var lines: PackedStringArray
	match _mood:
		Mood.HAPPY:
			lines = data.happy_lines if favorite else data.other_happy_lines
		Mood.MEH:
			lines = data.meh_lines if favorite else data.other_meh_lines
		_:
			lines = data.angry_lines if favorite else data.other_angry_lines
	return (Array(lines).pick_random() as String).format({"drink": order.name})

## How well a layered drink came out (0..1): how pure its layers are, by
## amount; 0 if they aren't in the recipe's order (bottom first). Layers
## thinner than min_layer are ignored for the order.
func _layer_quality(liquid: Node, order: Recipe) -> float:
	var sequence: Array[Drink] = []
	var clean := 0.0
	var total := 0.0
	for layer: Dictionary in liquid.layers():
		var amount := 0.0
		var top_drink: Drink
		for drink: Drink in layer:
			amount += layer[drink]
			if top_drink == null or layer[drink] > layer[top_drink]:
				top_drink = drink
		if amount <= 0.0:
			continue
		clean += layer[top_drink]
		total += amount
		if amount >= min_layer and (sequence.is_empty() or sequence.back() != top_drink):
			sequence.append(top_drink)
	if total <= 0.0 or sequence != order.drinks:
		return 0.0
	return clean / total

func _on_dialogue_finished() -> void:
	if _phase == Phase.REACTING:
		_tip_and_leave()
	elif _phase == Phase.TALKING and _is_boss(_customer):
		# "Five minutes." He's off; the day starts once he's out the door.
		_phase = Phase.LEAVING
		_customer.stand_up()

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
		if _is_boss(customer):
			_day_running = true
			_swatted.clear() # ones that stayed on the counter count again
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
	elif Debug.key(event):
		_debug_key(event.keycode)

## The debug keys, only while the F1 overlay is up (see Debug.KEYS).
func _debug_key(keycode: Key) -> void:
	match keycode:
		KEY_1, KEY_2, KEY_3:
			var index: int = keycode - KEY_1
			if index < customers.size():
				_spawn(index)
				Debug.note("Called " + customers[index].display_name)
		KEY_P:
			Debug.placeholders = not Debug.placeholders
			_update_stations()
			Debug.note("Placeholder customers walk in: %s" % _on_off(Debug.placeholders))
			if is_instance_valid(_customer):
				_next_index = _next_arriving(customers.find(_customer.data))
		KEY_H:
			if is_instance_valid(_customer):
				_customer.drunk += 1.0
				_customer.hiccup()
				Debug.note("%s drunk: %.1f" % [_customer.data.display_name, _customer.drunk])
		KEY_K:
			Debug.force_perfect = not Debug.force_perfect
			Debug.note("Next drink perfect: %s" % _on_off(Debug.force_perfect))
		KEY_U:
			Debug.unlock_all = not Debug.unlock_all
			_update_stations()
			Debug.note("Every drink unlocked: %s" % _on_off(Debug.unlock_all))
		KEY_S:
			# auto -> 0 -> 1 -> 2 -> auto
			Debug.sea = -1.0 if Debug.sea >= 2.0 else Debug.sea + 1.0 if Debug.sea >= 0.0 else 0.0
			Debug.note("Sea: " + ("auto" if Debug.sea < 0.0 else "%.0f" % Debug.sea))
		KEY_M:
			_money.set_money(_money.money + 20)
			Debug.note("+20 lei")
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			night = maxi(night + (1 if keycode == KEY_BRACKETRIGHT else -1), 0)
			_update_stations()
			Debug.note("Night %d" % night)
		KEY_N:
			_day_time = day_seconds
			Debug.note("Day ended")
		KEY_R:
			Transition.reload_scene()
		KEY_A:
			var shift := Input.is_key_pressed(KEY_SHIFT)
			AfterHoursScene.next_girl = load("res://customer/strigoi.tres" if shift else "res://customer/lizard.tres")
			Debug.note("After hours: " + ("Striggy" if shift else "Lizard"))
			Transition.change_scene("res://afterhours/afterhours.tscn")

func _on_off(on: bool) -> String:
	return "ON" if on else "off"

## What the F1 overlay shows about the bar.
func _debug_info() -> String:
	var text := "Night %d   %d%% of the day   %d lei
" % [night, int(100.0 * _day_time / day_seconds), _money.money]
	text += "Sea %.2f (%s)
" % [Sea.strength, "auto" if Debug.sea < 0.0 else "fixed"]
	if is_instance_valid(_customer):
		text += "%s: %s, drunk %.1f
" % [_customer.data.display_name,
			Phase.keys()[_phase].to_lower(), _customer.drunk]
		text += "Order: %s
" % (_order.name if _order != null else "-")
	text += "Next: %s
" % customers[_next_index].display_name
	text += "Placeholders %s  Unlock %s  Perfect %s" % [
		_on_off(Debug.placeholders), _on_off(Debug.unlock_all), _on_off(Debug.force_perfect)]
	return text

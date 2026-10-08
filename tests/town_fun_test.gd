extends Node
## Headless test of Free Drive's things to do (docs/DESIGN.md §23):
##   - the layout: the pitch and its goals, the paint shop, the pads, the bus stops on the
##     road with their shelters on the grass, the ramps' run-ups on the island's grass;
##   - the football: a car kicks it, and kicked into a goal it pays and comes back;
##   - cones: a car knocks them over, and they stand up again once it has gone;
##   - the fountain splashes a car driving past; a ramp throws the car in the air, over coins;
##   - a treat rides on the roof and is eaten up; a delivery goes from the pizza place to a
##     house and pays; the lost puppy is found, follows the car and goes home to the pet shop;
##   - the paint shop's pad asks for the car's next paint;
##   - the fire engine: swapped to on its pad, its hose puts out a fire, and back on the pad
##     the car again; the bus: passengers get on at one stop and off (paying) at another;
##   - rain: the puddles fill and are slippery, and dry up after.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/town_fun_test.tscn
## Exit code 0 = all passed.

const TOWN_SCENE := preload("res://game/screens/town.tscn")

var screen: TownScreen
var _coins_found := 0
var _jumped: Array[Node] = []
var _landed: Array[Node] = []
var _painted: Array[StringName] = []
var _failures: PackedStringArray = []


func _enter_tree() -> void:
	EventSystem.UI_settings_requested.connect(func() -> void:
		EventSystem.UI_settings_changed.emit({"sound_volume": 0.0, "music_volume": 0.0, "fullscreen": false,
			"auto_accelerate": false, "steering_help": false, "difficulty": &"normal"}))
	EventSystem.PRO_state_requested.connect(func() -> void:
		EventSystem.PRO_state_changed.emit({"setups": [load("res://game/configs/setups/starter.tres")],
			"equipped": &"starter", "coins": 0, "paint": {}}))
	EventSystem.PRO_coins_found.connect(func(amount: int) -> void: _coins_found += amount)
	EventSystem.CAR_jumped.connect(func(car: Node) -> void: _jumped.append(car))
	EventSystem.CAR_landed.connect(func(car: Node) -> void: _landed.append(car))
	EventSystem.PRO_paint_requested.connect(func(id: StringName) -> void: _painted.append(id))


func _ready() -> void:
	screen = TOWN_SCENE.instantiate()
	add_child(screen)
	await _frames(5)
	await _layout()
	await _football()
	await _cones()
	await _fountain_and_ramp()
	await _errands()
	await _paint()
	await _fire_engine()
	await _bus()
	await _rain()
	if _failures.is_empty():
		print("ALL TOWN FUN TESTS PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _layout() -> void:
	var town: Town = screen.town
	_check(town.pitch.has_area() and town.goals.size() == 2, "the pitch has two goals")
	_check(town.surface_at(town.pitch.get_center()) == &"grass", "the pitch is grass")
	_check(town.places.any(func(p: Dictionary) -> bool: return p["id"] == "paint_shop"), "the paint shop is a place")
	for pad: Rect2 in [town.fire_pad, town.bus_pad, town.paint_pad]:
		_check(pad.has_area() and town.surface_at(Vector2(pad.get_center().x, pad.end.y - 20.0)) == &"asphalt",
			"a pad reaches the street (%s)" % pad)
	_check(town.houses.size() >= 8, "deliveries have houses to go to (%d)" % town.houses.size())
	for stop: Dictionary in town.bus_stops:
		_check(_on_road(town, stop["stop"]) and town.surface_at(stop["kerb"]) == &"asphalt"
			and town.surface_at(stop["shelter"]) == &"grass", "a bus stop is in the lane, its shelter on the grass (%s)" % stop["stop"])
	var grass := Island.outline(-Island.BEACH)
	for ramp: Dictionary in town.ramps:
		var runway: Rect2 = ramp["runway"]
		var corners := [runway.position, Vector2(runway.end.x, runway.position.y), runway.end, Vector2(runway.position.x, runway.end.y)]
		_check(corners.all(func(c: Vector2) -> bool: return Geometry2D.is_point_in_polygon(c, grass))
			and not town.streets_rect().intersects(runway), "a ramp's run-up lies on the grass round the town (%s)" % ramp["at"])
		_check(town.surface_at(ramp["at"]) == &"asphalt", "and it is paved")


func _football() -> void:
	var town: Town = screen.town
	var ball: Kickable = screen.ball
	var car := screen.car
	var start := ball.global_position
	_put(car, start + Vector2(-300, 0), 0.0)
	await _drive(1.0)
	_check(ball.global_position.distance_to(start) > 150.0, "driving into the ball kicks it (%.0f px)" % ball.global_position.distance_to(start))
	await _seconds(2.0)
	# Into the left goal: the ball on the goal line, the car pushing it in.
	var goal: Rect2 = town.goals[0]
	_put(car, Vector2(goal.end.x + 400.0, goal.get_center().y), PI)
	ball.velocity = Vector2.ZERO
	ball.global_position = Vector2(goal.end.x + 120.0, goal.get_center().y)
	var before := _coins_found
	await _drive(1.4)
	await _seconds(0.5)
	_check(_coins_found - before >= screen.GOAL_PAY, "a goal pays %d (paid %d)" % [screen.GOAL_PAY, _coins_found - before])
	_put(car, town.pitch.get_center() + Vector2(0, 600), 0.0)
	await _seconds(2.0)
	_check(ball.global_position.distance_to(town.pitch.get_center()) < 10.0, "and the ball is back on the centre spot")


func _cones() -> void:
	var town: Town = screen.town
	var car := screen.car
	var ramp: Dictionary = town.ramps[0]
	var stack: Vector2 = ramp["at"] + ramp["throw"] * (TownLayout.RUNWAY_AFTER + 220.0)
	var cones := screen.kickables.filter(func(k: Kickable) -> bool:
		return k.kind == Kickable.Kind.CONE and k.home.distance_to(stack) < 300.0)
	_put(car, stack - ramp["throw"] * 450.0, ramp["throw"].angle())
	await _drive(1.2)
	var down := cones.filter(func(k: Kickable) -> bool: return k.knocked).size()
	_check(down >= 3, "driving into a stack of cones knocks them over (%d of %d)" % [down, cones.size()])
	_put(car, stack + Vector2(0, 1500), 0.0)
	await _seconds(Kickable.STAND_UP_AFTER + 2.0)
	var standing := cones.filter(func(k: Kickable) -> bool: return not k.knocked and k.global_position.distance_to(k.home) < 2.0).size()
	_check(standing == cones.size(), "once the car has gone they stand up again where they were (%d of %d)" % [standing, cones.size()])


func _fountain_and_ramp() -> void:
	var town: Town = screen.town
	var car := screen.car
	_put(car, town.fountain_at + Vector2(-650, 0), 0.0)
	await _drive(0.9)
	_check(screen._fountain_rest > 0.0, "driving past the fountain splashes the car")
	var ramp: Dictionary = town.ramps[0]
	_put(car, ramp["at"] - ramp["throw"] * (TownLayout.RUNWAY_BEFORE - 60.0), ramp["throw"].angle())
	_jumped.clear()
	_landed.clear()
	var before := _coins_found
	await _drive(2.4)
	await _seconds(0.5)
	_check(car in _jumped and car in _landed, "the ramp throws the car into the air, and it lands")
	_check(not car.has_node(^"Hop") and car.get_node(^"Body").scale == Vector2.ONE, "and it is back to its size")
	_check(_coins_found - before >= 2 * screen.COIN_VALUE, "it collects the coins over the landing (paid %d)" % (_coins_found - before))


func _errands() -> void:
	var town: Town = screen.town
	var car := screen.car
	var errands: TownErrands = screen.errands
	# A treat on the roof, eaten up after a while.
	await _visit("ice_cream_shop")
	var roof := car.get_node_or_null(^"Body/RoofLoad")
	_check(roof != null, "the ice cream parlour puts an ice cream on the roof")
	_put(car, car.global_position + Vector2(0, 300), 0.0)
	await _seconds(TownErrands.TREAT_SECONDS + 1.0)
	_check(not is_instance_valid(roof) or roof.is_queued_for_deletion(), "and it is eaten up after %d s" % TownErrands.TREAT_SECONDS)
	# A pizza to a house.
	await _visit("pizza_place")
	_check(errands.errand == &"delivery" and town.houses.any(func(h: Dictionary) -> bool: return h["door"] == errands.target),
		"the pizza place sends a pizza to a house")
	_check(car.has_node(^"Body/RoofLoad"), "the pizza rides on the roof")
	var before := _coins_found
	_put(car, errands.target + Vector2(0, 60), 0.0)
	await _frames(10)
	_check(errands.errand == &"" and _coins_found - before == TownErrands.DELIVERY_PAY,
		"pulling up at the house delivers it (paid %d)" % (_coins_found - before))
	# The lost puppy (after the short rest once an errand is done).
	await _seconds(3.2)
	await _visit("pet_shop")
	_check(errands.errand == &"puppy" and not errands.puppy_following, "the pet shop's puppy is lost")
	_put(car, errands.target + Vector2(-150, 0), 0.0)
	await _frames(5)
	_check(errands.puppy_following, "driving up to the puppy finds it")
	var puppy: Sprite2D = errands._puppy
	await _drive(1.0)
	await _seconds(0.6)
	_check(puppy.global_position.distance_to(car.global_position) < 320.0, "it follows the car (%.0f px behind)"
		% puppy.global_position.distance_to(car.global_position))
	before = _coins_found
	_put(car, errands.target + Vector2(0, 60), 0.0)
	await _frames(10)
	_check(errands.errand == &"" and _coins_found - before == TownErrands.PUPPY_PAY,
		"bringing it to the pet shop's door takes it home (paid %d)" % (_coins_found - before))


func _paint() -> void:
	var town: Town = screen.town
	var car := screen.car
	_put(car, town.paint_pad.get_center() + Vector2(0, 300), 0.0)
	await _frames(3)
	_put(car, town.paint_pad.get_center(), -PI / 2.0)
	await _frames(5)
	_check(_painted == [&"starter"], "the paint shop's pad asks for the car's next paint (%s)" % [_painted])


func _fire_engine() -> void:
	var town: Town = screen.town
	var car := screen.car
	await _onto_pad(car, town.fire_pad)
	var engine := screen.fire_engine
	_check(screen.riding == &"fire_engine" and screen.player == engine and engine.visible and not car.visible,
		"the fire station's pad swaps the car for the fire engine")
	_check(not car.is_in_group(&"cars") and car.collision_layer == 0, "the car is put away while the engine is out")
	var duty: FireDuty = screen.fire_duty
	_check(duty.fires.size() == FireDuty.FIRES, "fires are burning round town (%d)" % duty.fires.size())
	var fire: Dictionary = duty.fires[0]
	var from: Vector2 = fire["at"] + Vector2(-380, 0)
	_put(engine, from, 0.0)
	var before := _coins_found
	Input.action_press(&"handbrake")
	await _seconds(FireDuty.DOUSE_SECONDS + 0.5)
	Input.action_release(&"handbrake")
	_check(fire not in duty.fires and _coins_found - before == FireDuty.PAY, "the hose puts a fire out (paid %d)" % (_coins_found - before))
	await _seconds(FireDuty.RESPAWN + 0.5)
	_check(duty.fires.size() == FireDuty.FIRES, "and another starts somewhere else")
	await _onto_pad(engine, town.fire_pad)
	_check(screen.riding == &"car" and screen.player == car and car.visible and not engine.visible and car.is_in_group(&"cars"),
		"back on the pad, the car again")
	_check(duty.fires.is_empty() and not duty.active, "and the fires are gone")


func _bus() -> void:
	var town: Town = screen.town
	var car := screen.car
	await _onto_pad(car, town.bus_pad)
	var bus := screen.bus
	_check(screen.riding == &"bus" and screen.player == bus, "the school's pad swaps the car for the bus")
	var route: BusRoute = screen.bus_route
	var first: Dictionary = town.bus_stops[0]
	var waiting: int = route._waiting[0].size()
	_put(bus, first["stop"], first["along"].angle())
	await _frames(5)
	_check(waiting > 0 and route.riding.size() == waiting and route._waiting[0].is_empty(),
		"stopping at a bus stop, the animals waiting get on (%d)" % route.riding.size())
	var second: Dictionary = town.bus_stops[1]
	var riders := route.riding.size()
	var before := _coins_found
	_put(bus, second["stop"], second["along"].angle())
	await _frames(5)
	_check(_coins_found - before == BusRoute.PAY * riders, "at the next stop they get off and pay (%d)" % (_coins_found - before))
	await _onto_pad(bus, town.bus_pad)
	_check(screen.riding == &"car" and screen.player == car, "back at the school, the car again")


func _rain() -> void:
	var town: Town = screen.town
	var weather: TownWeather = screen.weather
	var puddle: Vector3 = town.puddles[0]
	var at := Vector2(puddle.x, puddle.y)
	_check(town.surface_at(at) == &"asphalt", "a dry puddle is just road")
	weather.rain_now(12.0)
	await _seconds(TownWeather.WET_IN + 1.0)
	_check(weather.raining and town.wet and town.surface_at(at) == &"puddle", "in the rain the puddles fill and are slippery")
	await _seconds(6.0 + TownWeather.DRY_OUT)
	_check(not weather.raining and not town.wet and town.surface_at(at) == &"asphalt", "after the rain they dry up")


# --- helpers ------------------------------------------------------------------------------

## Pull up at the first shop door of this kind.
func _visit(place_id: String) -> void:
	var car := screen.car
	for place: Dictionary in screen.town.places:
		if place["id"] == place_id:
			_put(car, place["door"] + Vector2(0, 400), 0.0)
			await _frames(3)
			_put(car, place["door"] + Vector2(0, 40), 0.0)
			await _frames(5)
			return


## Onto a swap pad (from just off it, so it is armed) and through the fade.
func _onto_pad(vehicle: Car, pad: Rect2) -> void:
	_put(vehicle, pad.get_center() + Vector2(0, pad.size.y / 2.0 + 300.0), -PI / 2.0)
	await _frames(3)
	_put(vehicle, pad.get_center(), -PI / 2.0)
	await _seconds(1.0)


func _on_road(town: Town, p: Vector2) -> bool:
	return town.streets_rect().has_point(p) and town.surface_at(p) == &"asphalt" \
		and not town.lawns.any(func(lawn: Rect2) -> bool: return lawn.grow(TownLayout.SIDEWALK).has_point(p))


func _put(vehicle: Car, at: Vector2, angle: float) -> void:
	vehicle.global_position = at
	vehicle.rotation = angle
	vehicle.velocity = Vector2.ZERO
	vehicle.reset_physics_interpolation()


## Full throttle for `seconds`.
func _drive(seconds: float) -> void:
	Input.action_press(&"accelerate")
	await _seconds(seconds)
	Input.action_release(&"accelerate")
	await _frames(2)


func _seconds(seconds: float) -> void:
	await _frames(int(seconds * 60.0))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, message: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + message)
	if not ok:
		_failures.append(message)

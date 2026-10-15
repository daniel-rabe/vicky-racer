extends Node
## Headless checks for street races and pop-up challenges (docs/DESIGN.md §30):
##   - every route goes round the town's roads, and its start line is clear of the pads;
##   - pulling up on a start line shows the card; R / Y starts the race: the racers line up,
##     the traffic pulls in and waits, the player is held for 3, 2, 1, GO;
##   - the racers drive the route round the corners on their own;
##   - passing the rings in order to the line finishes: a place, coins, the traffic goes again;
##   - a ramp jump is measured, and drifting in the quay's zone earns stars, paid on leaving.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/street_test.tscn
## Exit code 0 = all passed. Uses its own save and settings files, deleted afterwards.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://street_test.cfg"
const SETTINGS := "user://street_test_settings.cfg"
const TESTS := 4

var _failures: PackedStringArray = []
var _main: Node
var _manager: GarageManager
var _finished := 0


func _ready() -> void:
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_main = MAIN.instantiate()
	_main.get_node("GarageManager").save_path = SAVE
	_main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(_main)
	_manager = _main.get_node("GarageManager")
	await _frames(5)
	_screen().get_node("%Play").pressed.emit()
	var town: TownScreen = await _wait_for("Town")
	await _frames(10)
	_test_routes(town)
	await _test_race(town)
	await _test_jump(town)
	await _test_drift(town)
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_check(_finished == TESTS, "every test ran to its end (%d / %d)" % [_finished, TESTS])
	if _failures.is_empty():
		print("ALL STREET TESTS PASSED")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures.append(message)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _screen() -> Node:
	for child in _main.get_node("ScreenSlot").get_children():
		if not child.is_queued_for_deletion():
			return child
	return null


func _wait_for(screen_name: String, seconds := 3.0) -> Node:
	for i in int(seconds * 60.0):
		var screen := _screen()
		if screen and screen.name == screen_name:
			await _frames(3)
			return screen
		await _frames(1)
	return _screen()


func _put(car: Car, at: Vector2, angle := 0.0) -> void:
	car.global_position = at
	car.rotation = angle
	car.velocity = Vector2.ZERO
	car.reset_physics_interpolation()


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


func _test_routes(town: TownScreen) -> void:
	print("routes")
	for start: Dictionary in town.street_race.starts:
		var spec: Dictionary = start["route"]
		_check(StreetRace.route_ok(town.town, spec), "%s goes round the roads" % spec["name"])
		var pads := [town.town.wash_pad, town.town.fire_pad, town.town.bus_pad, town.town.paint_pad]
		for door: Dictionary in town.town.doors:
			pads.append(door["pad"])
		var across := Vector2.RIGHT.rotated(start["angle"]).orthogonal().abs()
		var half := across * (TownLayout.ROAD_HALF + 70.0) + (Vector2.ONE - across) * 60.0
		var line := Rect2(start["at"] - half, half * 2.0)
		_check(not pads.any(func(r: Rect2) -> bool: return r.grow(20.0).intersects(line)),
			"  its start line is clear of the pads (%s)" % start["at"])
	_finished += 1


func _test_race(town: TownScreen) -> void:
	print("a street race")
	var race := town.street_race
	var start: Dictionary = race.starts[0]
	_put(town.car, start["at"] - Vector2.RIGHT.rotated(start["angle"]) * 60.0, start["angle"])
	await _frames(3)
	_check(race.shown == start, "pulling up on the start line shows the card")
	var coins: int = _manager.profile.coins
	await _press(&"race_start")
	_check(race.running and race.racers.size() == 3, "R / Y starts it, with three racers")
	_check(town.traffic.all(func(c: Car) -> bool: return c.frozen and c.collision_layer == 0), "  the traffic pulls in and waits")
	_check(town.player.frozen, "  the player waits for GO")
	await _frames(200)
	_check(not town.player.frozen and race.racers.all(func(r: Car) -> bool: return not r.frozen), "GO: off they go")
	await _frames(900)
	var driver: RouteDriver = race.racers[0].get_node(^"RouteDriver")
	_check(driver.progress > 4000.0, "the racers drive the route round the corners (%.0f px in 15 s)" % driver.progress)
	var done := [0]
	race.finished.connect(func(_r: Dictionary, place: int) -> void: done[0] = place)
	for ring in race.rings.duplicate():
		_put(town.car, ring)
		await _frames(2)
	_check(done[0] >= 1 and not race.running, "through every ring to the line: finished, %d" % done[0])
	await _frames(3)
	_check(_manager.profile.coins == coins + StreetRace.PAY[done[0] - 1], "  and paid for the place (%d)" % (_manager.profile.coins - coins))
	_check(town.traffic.all(func(c: Car) -> bool: return not c.frozen), "  the traffic goes again")
	_put(town.car, start["at"] + Vector2(0, 800))
	await _frames(200)
	_check(race.racers.is_empty() and town.get_node("World/Cars").get_children().filter(func(c: Node) -> bool:
		return c.name.begins_with("StreetRacer") and not c.is_queued_for_deletion()).is_empty(), "  and the racers drive off")
	_finished += 1


func _test_jump(town: TownScreen) -> void:
	print("ramp jumps")
	_put(town.car, Vector2(3000, 2560))
	EventSystem.CAR_jumped.emit(town.car)
	_put(town.car, Vector2(3480, 2560))
	EventSystem.CAR_landed.emit(town.car)
	_check(town.challenges.last_jump == 12.0, "a jump is measured in metres (%d m)" % town.challenges.last_jump)
	var coins: int = _manager.profile.coins
	EventSystem.CAR_jumped.emit(town.car)
	_put(town.car, Vector2(4100, 2560))
	EventSystem.CAR_landed.emit(town.car)
	await _frames(2)
	_check(town.challenges.best_jump == 16.0 and _manager.profile.coins == coins + TownChallenges.JUMP_PAY,
		"a longer one is the best, and pays")
	_finished += 1


func _test_drift(town: TownScreen) -> void:
	print("the drift zone")
	var zone := TownChallenges.DRIFT_ZONE
	_put(town.car, zone.get_center(), 0.0)
	for i in 100:
		town.car.velocity = Vector2(0, 700 if i % 2 == 0 else -700)  # sideways, to and fro: a drift
		await _frames(1)
	var stars := town.challenges.stars
	_check(stars >= 3, "drifting in the zone earns stars (%d)" % stars)
	var coins: int = _manager.profile.coins
	_put(town.car, zone.position - Vector2(300, 300))
	await _frames(3)
	_check(town.challenges.stars == 0 and _manager.profile.coins == coins + stars, "driving out pays a coin a star")
	_finished += 1

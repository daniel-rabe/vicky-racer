extends Node
## Headless checks for candy land (docs/DESIGN.md §34):
##   - driving east from the ring road's south-east corner goes over the bridge into candy land:
##     asphalt on the bridge, the road on to Candy Lane and the lane, pink candy beside it,
##     chocolate in the lake, and sprinkles fall out there;
##   - the bridge's rails keep a car on it, and the island's shore keeps it on the candy;
##   - a jelly pad on Candy Lane bounces a car into the air;
##   - a boat sails under the bridge, and cannot get out to sea through the outer limit there;
##   - the Candy Lane gate stands in candy land.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/candy_test.tscn
## Exit code 0 = all passed. Uses its own save and settings files, deleted afterwards.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://candy_test.cfg"
const SETTINGS := "user://candy_test_settings.cfg"
const TESTS := 4

var _failures: PackedStringArray = []
var _main: Node
var _finished := 0


func _ready() -> void:
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_main = MAIN.instantiate()
	_main.get_node("GarageManager").save_path = SAVE
	_main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(_main)
	await _frames(5)
	_screen().get_node("%Play").pressed.emit()
	await _wait_for("Town")
	await _frames(10)
	await _test_bridge()
	await _test_walls()
	await _test_jelly()
	await _test_boat()
	Input.action_release(&"accelerate")
	Input.action_release(&"steer_left")
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_check(_finished == TESTS, "every test ran to its end (%d / %d)" % [_finished, TESTS])
	if _failures.is_empty():
		print("ALL CANDY TESTS PASSED")
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


func _put(node: Node2D, at: Vector2, angle := 0.0) -> void:
	node.global_position = at
	node.rotation = angle
	if node is CharacterBody2D:
		node.velocity = Vector2.ZERO
	node.reset_physics_interpolation()


func _test_bridge() -> void:
	print("over the bridge")
	var town: TownScreen = _screen()
	var start := Vector2(CandyIsland.ROAD_FROM + 100.0, CandyIsland.BRIDGE_Y + 70.0)
	_put(town.car, start, 0.0)
	await _frames(3)
	var on_bridge := town.town.surface_at(Vector2(11500, CandyIsland.BRIDGE_Y))
	Input.action_press(&"accelerate")
	var reached := false
	for i in 900:
		await _frames(1)
		if CandyIsland.contains(town.car.global_position) and town.car.global_position.x > CandyIsland.shore_x() + 300.0:
			reached = true
			break
	Input.action_release(&"accelerate")
	_check(on_bridge == &"asphalt", "the bridge is a road (%s)" % on_bridge)
	_check(reached, "driving east from the ring road's corner reaches candy land (at %s)" % town.car.global_position.round())
	_check(town.town.surface_at(town.car.global_position) == &"asphalt", "  on a road that runs on to Candy Lane")
	await _frames(10)
	_check(town.candy_land.sprinkling, "  where sprinkles fall")
	var lane := CandyIsland.lane_at(-PI / 2.0)
	_check(town.town.surface_at(lane) == &"asphalt" and town.town.surface_at(lane + Vector2(0, 300)) == &"candy",
		"  Candy Lane is a road, with candy beside it")
	_check(town.town.surface_at(CandyIsland.LAKE) == &"chocolate", "  the lake is chocolate")
	var gate: Array = town.gates.filter(func(g: RaceGate) -> bool: return g.config.track_id == CandyIsland.CANDY_LANE)
	_check(gate.size() == 1 and CandyIsland.contains(gate[0].slot) and town.town.surface_at(gate[0].stopwatch) == &"candy",
		"  the Candy Lane gate and its stopwatch stand in it")
	_put(town.car, start, 0.0)
	await _frames(10)
	_check(not town.candy_land.sprinkling, "back in town, no sprinkles")
	_finished += 1


func _test_walls() -> void:
	print("rails and shores")
	var town: TownScreen = _screen()
	# Steering hard off the side of the bridge, both ways.
	for angle in [-PI / 2.0, PI / 2.0]:
		_put(town.car, Vector2(11800, CandyIsland.BRIDGE_Y), angle)
		await _frames(3)
		Input.action_press(&"accelerate")
		await _frames(80)
		Input.action_release(&"accelerate")
		var y := town.car.global_position.y
		_check(absf(y - CandyIsland.BRIDGE_Y) < CandyIsland.BRIDGE_HALF, "the bridge's rail keeps a car on it (%.0f from the middle)" % (y - CandyIsland.BRIDGE_Y))
	# Driving off the island's east shore.
	_put(town.car, CandyIsland.CENTRE + Vector2(CandyIsland.RADII.x - 400.0, 0), 0.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	await _frames(200)
	Input.action_release(&"accelerate")
	_check(CandyIsland.contains(town.car.global_position), "the shore keeps it on the candy (at %s)" % town.car.global_position.round())
	_finished += 1


func _test_jelly() -> void:
	print("jelly")
	var town: TownScreen = _screen()
	var a: float = CandyIsland.JELLY_ANGLES[0]
	var along := CandyIsland.lane_along(a)
	_put(town.car, CandyIsland.lane_at(a) - along * 500.0, along.angle())
	await _frames(3)
	Input.action_press(&"accelerate")
	var bounced := false
	for i in 240:
		await _frames(1)
		if CarHop.airborne(town.car):
			bounced = true
			break
	Input.action_release(&"accelerate")
	_check(bounced, "a jelly pad on Candy Lane bounces a car into the air")
	await _frames(60)
	_put(town.car, Vector2(CandyIsland.ROAD_FROM + 100.0, CandyIsland.BRIDGE_Y + 70.0), 0.0)
	await _frames(5)
	_finished += 1


func _test_boat() -> void:
	print("boats")
	var town: TownScreen = _screen()
	town._swap_now(&"boat")
	await _frames(5)
	var boat: Car = town.player
	_put(boat, Vector2(11700, CandyIsland.BRIDGE_Y - 500.0), PI / 2.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	var passed := false
	for i in 300:
		await _frames(1)
		if boat.global_position.y > CandyIsland.BRIDGE_Y + 300.0:
			passed = true
			break
	Input.action_release(&"accelerate")
	_check(passed, "a boat sails under the bridge (at %s)" % boat.global_position.round())
	var limit_x := Island.world().end.x + Island.SEA
	_put(boat, Vector2(limit_x - 400.0, CandyIsland.BRIDGE_Y), 0.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	await _frames(240)
	Input.action_release(&"accelerate")
	_check(boat.global_position.x < limit_x + 20.0, "and cannot get out past the outer limit there (x %.0f, limit %.0f)" % [boat.global_position.x, limit_x])
	_finished += 1

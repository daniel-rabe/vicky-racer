extends Node
## Headless checks for toy town (docs/DESIGN.md §36):
##   - driving south from the ring road's south-west corner goes over the bridge into toy town:
##     asphalt on the bridge and the toy road, the play mat beside it, sand by the sea, and
##     confetti falls out there;
##   - the bridge's rails keep a car on it, and the island's shore keeps it on the island;
##   - the toy train goes round its track, says CHOO CHOO! to a car beside it, and nudges a car
##     standing on its track out of the way;
##   - a boat sails under the bridge, and cannot get out to sea through the outer limit there;
##   - the Toy Town gate stands in toy town.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/toy_test.tscn
## Exit code 0 = all passed. Uses its own save and settings files, deleted afterwards.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://toy_test.cfg"
const SETTINGS := "user://toy_test_settings.cfg"
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
	await _test_train()
	await _test_boat()
	Input.action_release(&"accelerate")
	Input.action_release(&"steer_left")
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_check(_finished == TESTS, "every test ran to its end (%d / %d)" % [_finished, TESTS])
	if _failures.is_empty():
		print("ALL TOY TESTS PASSED")
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
	var start := Vector2(ToyIsland.BRIDGE_X + 70.0, ToyIsland.ROAD_FROM + 100.0)
	_put(town.car, start, PI / 2.0)
	await _frames(3)
	var on_bridge := town.town.surface_at(Vector2(ToyIsland.BRIDGE_X, 9800.0))
	Input.action_press(&"accelerate")
	var reached := false
	for i in 900:
		await _frames(1)
		if ToyIsland.contains(town.car.global_position) and town.car.global_position.y > ToyIsland.shore_y() + 300.0:
			reached = true
			break
	Input.action_release(&"accelerate")
	_check(on_bridge == &"asphalt", "the bridge is a road (%s)" % on_bridge)
	_check(reached, "driving south from the ring road's corner reaches toy town (at %s)" % town.car.global_position.round())
	_check(town.town.surface_at(town.car.global_position) == &"asphalt", "  on a road that runs on to the toy road")
	await _frames(10)
	_check(town.toy_town.confetti_on, "  where confetti falls")
	var road := ToyIsland.CENTRE + Vector2(ToyIsland.ROAD_HALF_SIZE.x, 0)
	_check(town.town.surface_at(road) == &"asphalt" and town.town.surface_at(road + Vector2(350, 0)) == &"playmat",
		"  the toy road is a road, with the play mat beside it")
	_check(town.town.surface_at(ToyIsland.outline(-50.0)[0]) == &"beach", "  and sand by the sea")
	var gate: Array = town.gates.filter(func(g: RaceGate) -> bool: return g.config.track_id == ToyIsland.TOY_TOWN)
	_check(gate.size() == 1 and ToyIsland.contains(gate[0].slot) and town.town.surface_at(gate[0].stopwatch) == &"playmat",
		"  the Toy Town gate and its stopwatch stand in it")
	_put(town.car, start, PI / 2.0)
	await _frames(10)
	_check(not town.toy_town.confetti_on, "back in town, no confetti")
	_finished += 1


func _test_walls() -> void:
	print("rails and shores")
	var town: TownScreen = _screen()
	# Steering hard off the side of the bridge, both ways.
	for angle in [0.0, PI]:
		_put(town.car, Vector2(ToyIsland.BRIDGE_X, 9800.0), angle)
		await _frames(3)
		Input.action_press(&"accelerate")
		await _frames(80)
		Input.action_release(&"accelerate")
		var x := town.car.global_position.x
		_check(absf(x - ToyIsland.BRIDGE_X) < ToyIsland.BRIDGE_HALF, "the bridge's rail keeps a car on it (%.0f from the middle)" % (x - ToyIsland.BRIDGE_X))
	# Driving off the island's east shore.
	_put(town.car, ToyIsland.CENTRE + Vector2(ToyIsland.RADII.x - 400.0, 0), 0.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	await _frames(200)
	Input.action_release(&"accelerate")
	_check(ToyIsland.contains(town.car.global_position), "the shore keeps it on the island (at %s)" % town.car.global_position.round())
	_finished += 1


func _test_train() -> void:
	print("the train")
	var town: TownScreen = _screen()
	var train: ToyTrain = town.town.train
	var was := train.engine_at()
	await _frames(60)
	_check(train.engine_at().distance_to(was) > 100.0, "the toy train goes round its track (%.0f px in a second)" % train.engine_at().distance_to(was))
	# Wait beside the track, ahead of the engine, until it comes by.
	var ahead := train._point(fposmod(train.travelled + 900.0, train._total))
	var beside := ahead + (ahead - ToyIsland.CENTRE).normalized() * 230.0
	_put(town.car, beside, 0.0)
	var heard := false
	for i in 400:
		await _frames(1)
		if town.toy_town.by_train:
			heard = true
			break
	_check(heard, "pulling up beside it says CHOO CHOO!")
	# Standing on the track, ahead of the engine.
	ahead = train._point(fposmod(train.travelled + 700.0, train._total))
	_put(town.car, ahead, 0.0)
	await _frames(500)
	_check(town.car.global_position.distance_to(ahead) > 40.0, "it nudges a car on its track out of the way (%.0f px)" % town.car.global_position.distance_to(ahead))
	_put(town.car, Vector2(ToyIsland.BRIDGE_X + 70.0, ToyIsland.ROAD_FROM + 100.0), PI / 2.0)
	await _frames(5)
	_finished += 1


func _test_boat() -> void:
	print("boats")
	var town: TownScreen = _screen()
	town._swap_now(&"boat")
	await _frames(5)
	var boat: Car = town.player
	_put(boat, Vector2(ToyIsland.BRIDGE_X - 500.0, 9800.0), 0.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	var passed := false
	for i in 300:
		await _frames(1)
		if boat.global_position.x > ToyIsland.BRIDGE_X + 300.0:
			passed = true
			break
	Input.action_release(&"accelerate")
	_check(passed, "a boat sails under the bridge (at %s)" % boat.global_position.round())
	var limit_y := Island.world().end.y + Island.SEA
	_put(boat, Vector2(ToyIsland.BRIDGE_X, limit_y - 400.0), PI / 2.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	await _frames(240)
	Input.action_release(&"accelerate")
	_check(boat.global_position.y < limit_y + 20.0, "and cannot get out past the outer limit there (y %.0f, limit %.0f)" % [boat.global_position.y, limit_y])
	_finished += 1

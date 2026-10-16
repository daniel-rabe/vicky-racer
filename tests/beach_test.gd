extends Node
## Headless checks for Sunny Beach (docs/DESIGN.md §37):
##   - driving west from the ring road's north-west corner goes over the bridge onto Sunny Beach:
##     asphalt on the bridge and the boardwalk, sand beside it, SUNNY BEACH comes up;
##   - the bridge's rails keep a car on it, and the island's shore keeps it on the island;
##   - a wave pushes a car standing in the surf up the beach, and says SPLASH!;
##   - a car knocks a sandcastle flat (OOPS!), and it builds itself up again;
##   - a crab runs off from a car that comes near, hides, and walks home again;
##   - a boat sails under the bridge, and cannot get out to sea through the outer limit there;
##   - the Sunny Beach gate stands on the beach.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/beach_test.tscn
## Exit code 0 = all passed. Uses its own save and settings files, deleted afterwards.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://beach_test.cfg"
const SETTINGS := "user://beach_test_settings.cfg"
const TESTS := 6

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
	await _test_surf()
	await _test_castle()
	await _test_crab()
	await _test_boat()
	Input.action_release(&"accelerate")
	Input.action_release(&"steer_left")
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_check(_finished == TESTS, "every test ran to its end (%d / %d)" % [_finished, TESTS])
	if _failures.is_empty():
		print("ALL BEACH TESTS PASSED")
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
	var start := Vector2(BeachIsland.ROAD_FROM - 100.0, BeachIsland.BRIDGE_Y - 70.0)
	_put(town.car, start, PI)
	await _frames(3)
	var on_bridge := town.town.surface_at(Vector2(-1700.0, BeachIsland.BRIDGE_Y))
	Input.action_press(&"accelerate")
	var reached := false
	for i in 900:
		await _frames(1)
		if BeachIsland.contains(town.car.global_position) and town.car.global_position.x < BeachIsland.shore_x() - 300.0:
			reached = true
			break
	Input.action_release(&"accelerate")
	_check(on_bridge == &"asphalt", "the bridge is a road (%s)" % on_bridge)
	_check(reached, "driving west from the ring road's corner reaches Sunny Beach (at %s)" % town.car.global_position.round())
	_check(town.town.surface_at(town.car.global_position) == &"asphalt", "  on a road that runs on to the boardwalk")
	await _frames(5)
	_check(town.sunny_beach.arrived, "  and SUNNY BEACH comes up")
	var walk := BeachIsland.CENTRE + Vector2(0, BeachIsland.WALK_HALF_SIZE.y)
	_check(town.town.surface_at(walk) == &"asphalt" and town.town.surface_at(walk + Vector2(0, 350)) == &"beach",
		"  the boardwalk is firm, with sand beside it")
	var gate: Array = town.gates.filter(func(g: RaceGate) -> bool: return g.config.track_id == BeachIsland.SUNNY_BEACH)
	_check(gate.size() == 1 and BeachIsland.contains(gate[0].slot) and town.town.surface_at(gate[0].stopwatch) == &"beach",
		"  the Sunny Beach gate and its stopwatch stand on it")
	_check(town.town.castles.size() == BeachIsland.CASTLES and town.town.crabs.size() == BeachIsland.CRABS,
		"  with its sandcastles and crabs (%d, %d)" % [town.town.castles.size(), town.town.crabs.size()])
	_finished += 1


func _test_walls() -> void:
	print("rails and shores")
	var town: TownScreen = _screen()
	# Steering hard off the side of the bridge, both ways.
	for angle in [-PI / 2.0, PI / 2.0]:
		_put(town.car, Vector2(-1700.0, BeachIsland.BRIDGE_Y), angle)
		await _frames(3)
		Input.action_press(&"accelerate")
		await _frames(80)
		Input.action_release(&"accelerate")
		var y := town.car.global_position.y
		_check(absf(y - BeachIsland.BRIDGE_Y) < BeachIsland.BRIDGE_HALF, "the bridge's rail keeps a car on it (%.0f from the middle)" % (y - BeachIsland.BRIDGE_Y))
	# Driving off the island's north shore, and out into the surf.
	for start: Array in [[BeachIsland.CENTRE + Vector2(0, -BeachIsland.RADII.y + 400.0), -PI / 2.0],
			[BeachIsland.CENTRE + Vector2(-BeachIsland.RADII.x + 700.0, 0), PI]]:
		_put(town.car, start[0], start[1])
		await _frames(3)
		Input.action_press(&"accelerate")
		await _frames(200)
		Input.action_release(&"accelerate")
		_check(BeachIsland.contains(town.car.global_position), "the shore keeps it on the island (at %s)" % town.car.global_position.round())
	_finished += 1


func _test_surf() -> void:
	print("the surf")
	var town: TownScreen = _screen()
	var surf: BeachSurf = town.town.surf
	# Wait for the sea to go out, stand in the surf, and wait for the next wave.
	for i in 600:
		if not surf.rising and surf.front < 1.0:
			break
		await _frames(1)
	var spot := BeachIsland.shore_point(PI, -150.0)
	_put(town.car, spot, -PI / 2.0)
	await _frames(2)
	var before := BeachIsland.up_the_beach(town.car.global_position)
	for i in 400:
		await _frames(1)
		if surf.rising and surf.front > BeachIsland.SURF_DEPTH * 0.9:
			break
	await _frames(30)
	var after := BeachIsland.up_the_beach(town.car.global_position)
	_check(after > before + 40.0, "a wave pushes a car up the beach (%.0f px up, from %.0f)" % [after - before, before])
	_check(town.sunny_beach.splashed, "  and says SPLASH!")
	_finished += 1


func _test_castle() -> void:
	print("sandcastles")
	var town: TownScreen = _screen()
	var castle: SandCastle = town.town.castles[0]
	_check(not castle.flat, "a sandcastle stands")
	_put(town.car, castle.global_position + Vector2(-420.0, 0.0), 0.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	for i in 180:
		await _frames(1)
		if castle.flat:
			break
	Input.action_release(&"accelerate")
	_check(castle.flat, "driving into it knocks it flat")
	_check(town.sunny_beach.smashed, "  and says OOPS!")
	_put(town.car, castle.global_position + Vector2(-900.0, 0.0), 0.0)
	castle._since = SandCastle.REBUILD_AFTER - 0.5
	await _frames(60)
	_check(not castle.flat, "it builds itself up again once nobody is near")
	_finished += 1


func _test_crab() -> void:
	print("crabs")
	var town: TownScreen = _screen()
	var crab: BeachCrab = town.town.crabs[0]
	_put(town.car, crab.home + (crab.home - BeachIsland.CENTRE).normalized() * -900.0, 0.0)
	for i in 600:
		if crab.state == BeachCrab.State.WALK:
			break
		await _frames(1)
	var from := crab.global_position
	_put(town.car, from + Vector2(0, -BeachCrab.NOTICE + 80.0), PI / 2.0)
	await _frames(40)
	_check(crab.scared > 0, "a crab runs off from a car that comes near")
	_check(crab.global_position.distance_to(town.car.global_position) > BeachCrab.NOTICE - 60.0, "  away from it (%.0f px)" % crab.global_position.distance_to(town.car.global_position))
	await _frames(30)
	_check(crab.state == BeachCrab.State.HIDDEN, "  and digs in")
	_put(town.car, crab.home + (crab.home - BeachIsland.CENTRE).normalized() * -900.0, 0.0)
	var home := false
	for i in int((BeachCrab.HIDE_FOR + 8.0) * 60.0):
		await _frames(1)
		if crab.state == BeachCrab.State.WALK:
			home = true
			break
	_check(home, "  then walks home again")
	_finished += 1


func _test_boat() -> void:
	print("boats")
	var town: TownScreen = _screen()
	town._swap_now(&"boat")
	await _frames(5)
	var boat: Car = town.player
	_put(boat, Vector2(-1700.0, BeachIsland.BRIDGE_Y - 500.0), PI / 2.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	var passed := false
	for i in 300:
		await _frames(1)
		if boat.global_position.y > BeachIsland.BRIDGE_Y + 300.0:
			passed = true
			break
	Input.action_release(&"accelerate")
	_check(passed, "a boat sails under the bridge (at %s)" % boat.global_position.round())
	var limit_x := Island.world().position.x - Island.SEA
	_put(boat, Vector2(limit_x + 400.0, BeachIsland.BRIDGE_Y), PI)
	await _frames(3)
	Input.action_press(&"accelerate")
	await _frames(240)
	Input.action_release(&"accelerate")
	_check(boat.global_position.x > limit_x - 20.0, "and cannot get out past the outer limit there (x %.0f, limit %.0f)" % [boat.global_position.x, limit_x])
	_finished += 1

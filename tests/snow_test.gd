extends Node
## Headless checks for the snowy hill (docs/DESIGN.md §33):
##   - driving east from the ring road goes over the bridge onto the snow: asphalt on the
##     bridge, snow on the island, and snow falls out there;
##   - the bridge's rails keep a car on it, and the island's shore keeps it on the snow;
##   - a boat sails under the bridge, and cannot get out to sea through the outer limit there;
##   - the hill: a car left halfway up rolls down it, driving up is slower than down;
##   - the lake and the sledging run are ice; the Snowy Peak gate stands on the snow.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/snow_test.tscn
## Exit code 0 = all passed. Uses its own save and settings files, deleted afterwards.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://snow_test.cfg"
const SETTINGS := "user://snow_test_settings.cfg"
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
	await _test_hill()
	await _test_boat()
	Input.action_release(&"accelerate")
	Input.action_release(&"steer_left")
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_check(_finished == TESTS, "every test ran to its end (%d / %d)" % [_finished, TESTS])
	if _failures.is_empty():
		print("ALL SNOW TESTS PASSED")
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
	var start := Vector2(SnowIsland.ROAD_FROM + 100.0, SnowIsland.BRIDGE_Y + 70.0)
	_put(town.car, start, 0.0)
	await _frames(3)
	var on_bridge := town.town.surface_at(Vector2(11500, SnowIsland.BRIDGE_Y))
	Input.action_press(&"accelerate")
	var reached := false
	for i in 900:
		await _frames(1)
		if SnowIsland.contains(town.car.global_position) and town.car.global_position.x > SnowIsland.shore_x() + 300.0:
			reached = true
			break
	Input.action_release(&"accelerate")
	_check(on_bridge == &"asphalt", "the bridge is a road (%s)" % on_bridge)
	_check(reached, "driving east from the ring road reaches the snowy hill (at %s)" % town.car.global_position.round())
	_check(town.town.surface_at(town.car.global_position) == &"snow", "  and it is snow there")
	await _frames(10)
	_check(town.snow_hill.snowing, "  where snow falls")
	_check(town.town.surface_at(SnowIsland.LAKE) == &"ice" and town.town.surface_at(SnowIsland.SLED_FROM.lerp(SnowIsland.SLED_TO, 0.5)) == &"ice",
		"  the lake and the sledging run are ice")
	var snowy: Array = town.gates.filter(func(g: RaceGate) -> bool: return g.config.track_id == SnowIsland.SNOWY_PEAK)
	_check(snowy.size() == 1 and SnowIsland.contains(snowy[0].slot), "  the Snowy Peak gate stands on it")
	_put(town.car, start, 0.0)
	await _frames(10)
	_check(not town.snow_hill.snowing, "back in town, no snow")
	_finished += 1


func _test_walls() -> void:
	print("rails and shores")
	var town: TownScreen = _screen()
	# Steering hard off the side of the bridge.
	_put(town.car, Vector2(11800, SnowIsland.BRIDGE_Y), -PI / 2.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	await _frames(80)
	Input.action_release(&"accelerate")
	var y := town.car.global_position.y
	_check(absf(y - SnowIsland.BRIDGE_Y) < SnowIsland.BRIDGE_HALF, "the bridge's rail keeps a car on it (%.0f from the middle)" % (y - SnowIsland.BRIDGE_Y))
	# Driving off the island's east shore.
	_put(town.car, SnowIsland.CENTRE + Vector2(SnowIsland.RADII.x - 400.0, 0), 0.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	await _frames(200)
	Input.action_release(&"accelerate")
	_check(SnowIsland.contains(town.car.global_position), "the shore keeps it on the snow (at %s)" % town.car.global_position.round())
	_finished += 1


func _test_hill() -> void:
	print("the hill")
	var town: TownScreen = _screen()
	var half := SnowIsland.HILL + Vector2(0, SnowIsland.HILL_RADIUS * 0.5)
	_put(town.car, half, 0.0)
	await _frames(90)
	var rolled := town.car.global_position.distance_to(SnowIsland.HILL) - SnowIsland.HILL_RADIUS * 0.5
	_check(rolled > 40.0, "a car left halfway up rolls down (%.0f px)" % rolled)
	var foot := SnowIsland.HILL + Vector2(0, SnowIsland.HILL_RADIUS - 80.0)
	_put(town.car, foot, -PI / 2.0)
	Input.action_press(&"accelerate")
	await _frames(60)
	var up := town.car.global_position.distance_to(foot)
	_put(town.car, SnowIsland.HILL + Vector2(0, 160), PI / 2.0)
	await _frames(1)
	var top := town.car.global_position
	await _frames(60)
	var down := town.car.global_position.distance_to(top)
	Input.action_release(&"accelerate")
	_check(down > up * 1.1, "rolling down goes further than driving up (%.0f against %.0f px a second)" % [down, up])
	_put(town.car, Vector2(SnowIsland.ROAD_FROM + 100.0, SnowIsland.BRIDGE_Y + 70.0), 0.0)
	await _frames(5)
	_finished += 1


func _test_boat() -> void:
	print("boats")
	var town: TownScreen = _screen()
	town._swap_now(&"boat")
	await _frames(5)
	var boat: Car = town.player
	_put(boat, Vector2(11700, SnowIsland.BRIDGE_Y - 500.0), PI / 2.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	var passed := false
	for i in 300:
		await _frames(1)
		if boat.global_position.y > SnowIsland.BRIDGE_Y + 300.0:
			passed = true
			break
	Input.action_release(&"accelerate")
	_check(passed, "a boat sails under the bridge (at %s)" % boat.global_position.round())
	var limit_x := Island.world().end.x + Island.SEA
	_put(boat, Vector2(limit_x - 400.0, SnowIsland.BRIDGE_Y), 0.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	await _frames(240)
	Input.action_release(&"accelerate")
	_check(boat.global_position.x < limit_x + 20.0, "and cannot get out past the outer limit there (x %.0f, limit %.0f)" % [boat.global_position.x, limit_x])
	_finished += 1

extends Node
## Headless checks for the jungle (docs/DESIGN.md §35):
##   - driving north from the ring road's north-east corner goes over the bridge into the jungle:
##     asphalt on the bridge and the trail, jungle floor beside it, sand by the sea, mud in the
##     pools, and leaves fall out there;
##   - the bridge's rails keep a car on it, and the island's shore keeps it on the island;
##   - a mud pool makes a car muddy, and the car wash makes it clean;
##   - a boat sails under the bridge, and cannot get out to sea through the outer limit there;
##   - the Jungle Run gate stands in the jungle, and the temple's pyramid is solid.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/jungle_test.tscn
## Exit code 0 = all passed. Uses its own save and settings files, deleted afterwards.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://jungle_test.cfg"
const SETTINGS := "user://jungle_test_settings.cfg"
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
	await _test_mud()
	await _test_boat()
	Input.action_release(&"accelerate")
	Input.action_release(&"steer_left")
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_check(_finished == TESTS, "every test ran to its end (%d / %d)" % [_finished, TESTS])
	if _failures.is_empty():
		print("ALL JUNGLE TESTS PASSED")
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
	var start := Vector2(JungleIsland.BRIDGE_X + 70.0, JungleIsland.ROAD_FROM - 100.0)
	_put(town.car, start, -PI / 2.0)
	await _frames(3)
	var on_bridge := town.town.surface_at(Vector2(JungleIsland.BRIDGE_X, -1500.0))
	Input.action_press(&"accelerate")
	var reached := false
	for i in 900:
		await _frames(1)
		if JungleIsland.contains(town.car.global_position) and town.car.global_position.y < JungleIsland.shore_y() - 300.0:
			reached = true
			break
	Input.action_release(&"accelerate")
	_check(on_bridge == &"asphalt", "the bridge is a road (%s)" % on_bridge)
	_check(reached, "driving north from the ring road's corner reaches the jungle (at %s)" % town.car.global_position.round())
	_check(town.town.surface_at(town.car.global_position) == &"asphalt", "  on a road that runs on to the trail")
	await _frames(10)
	_check(town.jungle.leafy, "  where leaves fall")
	var trail := JungleIsland.trail_at(0.0)
	_check(town.town.surface_at(trail) == &"asphalt" and town.town.surface_at(trail + Vector2(-350, 0)) == &"jungle",
		"  the trail is a road, with jungle beside it")
	_check(town.town.surface_at(JungleIsland.trail_at(JungleIsland.MUD_ANGLES[1])) == &"mud", "  with mud pools on it")
	_check(town.town.surface_at(JungleIsland.outline(-50.0)[80]) == &"beach", "  and sand by the sea")
	var gate: Array = town.gates.filter(func(g: RaceGate) -> bool: return g.config.track_id == JungleIsland.JUNGLE_RUN)
	_check(gate.size() == 1 and JungleIsland.contains(gate[0].slot) and town.town.surface_at(gate[0].stopwatch) == &"jungle",
		"  the Jungle Run gate and its stopwatch stand in it")
	_put(town.car, start, -PI / 2.0)
	await _frames(10)
	_check(not town.jungle.leafy, "back in town, no leaves")
	_finished += 1


func _test_walls() -> void:
	print("rails, shores and the pyramid")
	var town: TownScreen = _screen()
	# Steering hard off the side of the bridge, both ways.
	for angle in [0.0, PI]:
		_put(town.car, Vector2(JungleIsland.BRIDGE_X, -1500.0), angle)
		await _frames(3)
		Input.action_press(&"accelerate")
		await _frames(80)
		Input.action_release(&"accelerate")
		var x := town.car.global_position.x
		_check(absf(x - JungleIsland.BRIDGE_X) < JungleIsland.BRIDGE_HALF, "the bridge's rail keeps a car on it (%.0f from the middle)" % (x - JungleIsland.BRIDGE_X))
	# Driving off the island's west shore.
	_put(town.car, JungleIsland.CENTRE + Vector2(-JungleIsland.RADII.x + 400.0, 0), PI)
	await _frames(3)
	Input.action_press(&"accelerate")
	await _frames(200)
	Input.action_release(&"accelerate")
	_check(JungleIsland.contains(town.car.global_position), "the shore keeps it on the island (at %s)" % town.car.global_position.round())
	# Driving north out of the temple's courtyard into the pyramid.
	var pyramid := JungleIsland.pyramid()
	_put(town.car, JungleIsland.courtyard().get_center(), -PI / 2.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	await _frames(150)
	Input.action_release(&"accelerate")
	_check(town.car.global_position.y > pyramid.end.y - 20.0, "the pyramid is solid (at %s)" % town.car.global_position.round())
	_finished += 1


func _test_mud() -> void:
	print("mud")
	var town: TownScreen = _screen()
	var a: float = JungleIsland.MUD_ANGLES[0]
	var along := JungleIsland.trail_along(a)
	_put(town.car, JungleIsland.trail_at(a) - along * 450.0, along.angle())
	await _frames(3)
	_check(not CarMud.is_muddy(town.car), "a clean car to start with")
	Input.action_press(&"accelerate")
	var muddy := false
	for i in 300:
		await _frames(1)
		if CarMud.is_muddy(town.car):
			muddy = true
			break
	Input.action_release(&"accelerate")
	_check(muddy, "driving through a mud pool makes the car muddy")
	EventSystem.CAR_washed.emit(town.car)
	await _frames(3)
	_check(not CarMud.is_muddy(town.car), "the car wash makes it clean again")
	_put(town.car, Vector2(JungleIsland.BRIDGE_X + 70.0, JungleIsland.ROAD_FROM - 100.0), -PI / 2.0)
	await _frames(5)
	_finished += 1


func _test_boat() -> void:
	print("boats")
	var town: TownScreen = _screen()
	town._swap_now(&"boat")
	await _frames(5)
	var boat: Car = town.player
	_put(boat, Vector2(JungleIsland.BRIDGE_X - 500.0, -1500.0), 0.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	var passed := false
	for i in 300:
		await _frames(1)
		if boat.global_position.x > JungleIsland.BRIDGE_X + 300.0:
			passed = true
			break
	Input.action_release(&"accelerate")
	_check(passed, "a boat sails under the bridge (at %s)" % boat.global_position.round())
	var limit_y := Island.world().position.y - Island.SEA
	_put(boat, Vector2(JungleIsland.BRIDGE_X, limit_y + 400.0), -PI / 2.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	await _frames(240)
	Input.action_release(&"accelerate")
	_check(boat.global_position.y > limit_y - 20.0, "and cannot get out past the outer limit there (y %.0f, limit %.0f)" % [boat.global_position.y, limit_y])
	_finished += 1

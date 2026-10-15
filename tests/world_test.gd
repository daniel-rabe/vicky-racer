extends Node
## Headless checks for the open world (docs/DESIGN.md §28):
##   - PLAY on the title drives straight into the town, which becomes home;
##   - a race gate for every track: car gates paved, on the grass and off the roads; boat gates
##     at sea; three racers waiting on each; only the first of each kind open on a new save;
##   - pulling up on a gate's place shows its card; R / Y starts the race on that track, and
##     DRIVE ON comes back to the gate, with the next gate open;
##   - a locked gate's button points the way to the gate that opens it;
##   - the garage, the trophy house and the rocket pad open the garage, the shelf and the
##     Hangar, and BACK comes out on the pad, which waits until the car has left it;
##   - the spot is saved: leaving and pressing PLAY again carries on there, at sea too;
##   - the pause menu's MAP shows every place, and choosing one points the way there.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/world_test.tscn
## Exit code 0 = all passed. Uses its own save and settings files, deleted afterwards.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://world_test.cfg"
const SETTINGS := "user://world_test_settings.cfg"

var _failures: PackedStringArray = []
var _main: Node
var _manager: GarageManager
## Tests that ran to their end: a script error stops one half-way, and must not pass.
var _finished := 0
const TESTS := 7


func _ready() -> void:
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_main = MAIN.instantiate()
	_main.get_node("GarageManager").save_path = SAVE
	_main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(_main)
	_manager = _main.get_node("GarageManager")
	await _frames(5)
	await _test_play()
	_test_gates()
	await _test_gate_race()
	await _test_locked_gate()
	await _test_doors()
	await _test_saved_spot()
	await _test_map()
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_check(_finished == TESTS, "every test ran to its end (%d / %d)" % [_finished, TESTS])
	if _failures.is_empty():
		print("ALL WORLD TESTS PASSED")
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


## Wait (up to `seconds`) for the screen called `screen_name`.
func _wait_for(screen_name: String, seconds := 3.0) -> Node:
	var frames := int(seconds * 60.0)
	for i in frames:
		var screen := _screen()
		if screen and screen.name == screen_name:
			await _frames(3)
			return screen
		await _frames(1)
	return _screen()


func _put(town: TownScreen, at: Vector2, angle := 0.0) -> void:
	town.player.global_position = at
	town.player.rotation = angle
	town.player.velocity = Vector2.ZERO
	town.player.reset_physics_interpolation()


func _test_play() -> void:
	print("PLAY")
	var title := _screen()
	_check(title.name == "TitleScreen" and not title.get_node("%Town").visible, "the title has PLAY, and no TOWN any more")
	title.get_node("%Play").pressed.emit()
	var town := await _wait_for("Town")
	_check(town is TownScreen, "PLAY opens the town (%s)" % town.name)
	_check(_manager.home == &"town", "the town is home now")
	var lane: PackedVector2Array = town.town.lane_points(TownScreen.START_ROAD[0], TownScreen.START_ROAD[1])
	_check(town.car.global_position.distance_to(lane[int(TownScreen.START_AT * (lane.size() - 1))]) < 60.0,
		"a new save starts by the candy shop")
	_finished += 1


func _test_gates() -> void:
	print("race gates")
	var town: TownScreen = _screen()
	var gates := town.gates
	var cars := gates.filter(func(g: RaceGate) -> bool: return g.kind == &"car")
	var boats := gates.filter(func(g: RaceGate) -> bool: return g.kind == &"boat")
	_check(cars.size() == GarageManager.TRACK_ORDER.size() and boats.size() == GarageManager.BOAT_TRACK_ORDER.size(),
		"a gate for every car track and boat course (%d, %d)" % [cars.size(), boats.size()])
	_check(gates.all(func(g: RaceGate) -> bool: return g.racers.size() == 3), "three racers wait at every gate")
	var streets := town.town.streets_rect()
	for gate: RaceGate in cars:
		var surface := town.town.surface_at(gate.slot)
		_check(surface == &"asphalt" and not streets.has_point(gate.slot), "%s: its place is paved, outside the streets (%s)" % [gate.name, surface])
		for racer in gate.racers:
			_check(town.town.surface_at(racer.global_position) == &"asphalt", "%s: %s waits on the paving" % [gate.name, racer.name])
	for gate: RaceGate in boats:
		var surface := town.town.surface_at(gate.slot)
		_check(surface in [&"deep_water", &"lagoon_water"], "%s: its place is at sea (%s)" % [gate.name, surface])
		for racer in gate.racers:
			_check(town.town.surface_at(racer.global_position) in [&"deep_water", &"lagoon_water"], "%s: %s floats" % [gate.name, racer.name])
	_check(cars[0].unlocked and not cars[1].unlocked and boats[0].unlocked and not boats[1].unlocked,
		"on a new save only the first gate of each kind is open")
	_finished += 1


func _test_gate_race() -> void:
	print("racing from a gate")
	var town: TownScreen = _screen()
	var gate: RaceGate = town.gates[0]
	var slot := gate.slot
	_put(town, gate.slot, gate.slot_angle())
	await _frames(4)
	_check(town.hud.gate_shown == gate, "pulling up on the place shows the card")
	_put(town, gate.slot + Vector2(0, 600))
	await _frames(4)
	_check(town.hud.gate_shown == null, "driving off hides it")
	_put(town, gate.slot, gate.slot_angle())
	await _frames(4)
	await _press(&"race_start")
	var race := await _wait_for("Race", 4.0)
	_check(race.name == "Race" and race.config.track_id == &"track_01", "R / Y starts the race on the gate's track")
	var spot: Dictionary = _manager.profile.world
	_check(Vector2(spot.get("x", 0.0), spot.get("y", 0.0)).distance_to(slot) < 1.0, "the gate's place is saved")
	var pause: Node = race.get_node("PauseMenu")
	_check(pause.get_node("%Garage").text == "TOWN", "the race's pause menu leaves to the town")
	# The race, finished in second place.
	var results := [{"name": "BLUE", "body": "res://art/cars/car_blue.png", "is_player": false, "position": 1, "time": 100.0, "best_lap": 33.0},
		{"name": "YOU", "body": "res://art/cars/car_red.png", "is_player": true, "position": 2, "time": 101.0, "best_lap": 33.5}]
	EventSystem.RAC_race_finished.emit(results, &"track_01")
	EventSystem.UI_screen_requested.emit(&"results")
	var screen := await _wait_for("ResultsScreen")
	var drive_on: Button = screen.get_node("%Garage")
	_check(drive_on.text == "DRIVE ON", "the results offer DRIVE ON (%s)" % drive_on.text)
	drive_on.pressed.emit()
	town = await _wait_for("Town")
	_check(town is TownScreen and town.player.global_position.distance_to(town.gates[0].slot) < 2.0, "DRIVE ON comes back to the gate")
	await _frames(4)
	_check(town.gates[1].unlocked, "finishing the race opens the next gate")
	_check(town.hud.gate_shown == town.gates[0], "back on the place, its card is there to race again")
	_finished += 1


func _test_locked_gate() -> void:
	print("a locked gate")
	var town: TownScreen = _screen()
	var locked: RaceGate = town.gates[2]
	_check(not locked.unlocked, "the third gate is still locked")
	_put(town, locked.slot, locked.slot_angle())
	await _frames(4)
	await _press(&"race_start")
	await _frames(4)
	_check(_screen() == town, "its button does not start a race")
	_check(not town._pin.is_empty() and (town._pin["at"] as Vector2).distance_to(town.gates[1].slot) < 1.0,
		"it shows the way to the gate that opens it")
	_put(town, town.gates[1].slot)
	await _frames(3)
	_check(town._pin.is_empty(), "getting there, the arrow goes")
	_finished += 1


func _test_doors() -> void:
	print("doors")
	var town: TownScreen = _screen()
	for spec in [[&"garage", "GarageScreen", &"car"], [&"shelf", "ShelfScreen", &"car"]]:
		var door: Dictionary = town.town.doors.filter(func(d: Dictionary) -> bool: return d["screen"] == spec[0])[0]
		_put(town, door["pad"].get_center())
		var screen := await _wait_for(spec[1])
		_check(screen.name == spec[1], "the %s's pad opens %s (%s)" % [spec[0], spec[1], screen.name])
		_check(_manager.vehicle_kind == spec[2], "  in the right colours (%s)" % _manager.vehicle_kind)
		await _press(&"ui_cancel")
		town = await _wait_for("Town")
		_check(town is TownScreen and door["pad"].has_point(town.player.global_position), "  BACK comes out on its pad")
		await _frames(60)
		_check(_screen() == town, "  the pad waits until the car has left it")
		_put(town, door["pad"].get_center() + Vector2(0, 500))
		await _frames(3)
	_put(town, town.town.rocket_pad.get_center())
	var hangar := await _wait_for("GarageScreen")
	_check(hangar.name == "GarageScreen" and _manager.vehicle_kind == &"ship", "the rocket pad opens the Hangar")
	await _press(&"ui_cancel")
	town = await _wait_for("Town")
	_check(town is TownScreen and _manager.vehicle_kind == &"car", "and BACK comes out by the rocket, in the car")
	_put(town, town.town.rocket_pad.get_center() + Vector2(600, 0))
	await _frames(3)
	_finished += 1


func _test_saved_spot() -> void:
	print("the world remembers")
	var town: TownScreen = _screen()
	var spot := Vector2(5200, 2560 + 80)
	_put(town, spot, PI)
	await _frames(3)
	EventSystem.UI_screen_requested.emit(&"title")
	var title := await _wait_for("TitleScreen")
	_check(_manager.home == &"title", "the title is home again")
	title.get_node("%Play").pressed.emit()
	town = await _wait_for("Town")
	_check(town.player == town.car and town.car.global_position.distance_to(spot) < 2.0,
		"PLAY again carries on where the car was left")
	town._swap_now(&"boat")
	var sea := Vector2(3000, 9300)
	_put(town, sea, 0.0)
	await _frames(3)
	EventSystem.UI_screen_requested.emit(&"title")
	title = await _wait_for("TitleScreen")
	title.get_node("%Play").pressed.emit()
	town = await _wait_for("Town")
	_check(town.sailing and town.player.global_position.distance_to(sea) < 2.0, "and at sea, in the boat")
	_check(_manager.vehicle_kind == &"boat", "  with the Boat Dock behind the pause menu's GARAGE")
	town._swap_now(&"car")
	await _frames(3)
	_finished += 1


func _test_map() -> void:
	print("the map")
	var town: TownScreen = _screen()
	var pause: Node = town.get_node("PauseMenu")
	pause.pause()
	await _frames(2)
	var map_button: Button = pause.get_node("%Menu").find_child("Map", true, false)
	_check(map_button != null, "the pause menu has MAP")
	map_button.pressed.emit()
	await get_tree().process_frame
	var map: WorldMap = town._map
	_check(map.visible and map.places.size() == town.gates.size() + 6, "the map shows every gate, the four buildings, the rocket and the harbour (%d)" % map.places.size())
	var before := map.selected
	await _press(&"ui_right")
	_check(map.selected != before, "the arrows move from place to place")
	var chosen: Dictionary = map.places[map.selected]
	await _press(&"ui_accept")
	await _frames(2)
	_check(not get_tree().paused and not map.visible, "choosing closes the map and the game goes on")
	_check(not town._pin.is_empty() and town._pin["at"] == chosen["at"], "and the way to %s is shown" % chosen["name"])
	_finished += 1

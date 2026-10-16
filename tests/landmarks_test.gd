extends Node
## Headless checks for the open world's landmarks (docs/DESIGN.md §31):
##   - the stadium's pad opens the track select (races, cups, time trials), and BACK comes out
##     in the town, on the pad;
##   - the workshop's pad opens the track editor, and BACK comes out in the town;
##   - the rocket pad: the car rolls in and the rocket lifts off, then the Hangar opens;
##   - a car gate's stopwatch shows the track's card with TIME TRIAL, and R / Y starts a time
##     trial on that track.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/landmarks_test.tscn
## Exit code 0 = all passed. Uses its own save and settings files, deleted afterwards.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://landmarks_test.cfg"
const SETTINGS := "user://landmarks_test_settings.cfg"
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
	await _wait_for("Town")
	await _frames(10)
	await _test_door("stadium", "TrackSelect")
	await _test_door("workshop", "TrackEditor")
	await _test_rocket()
	await _test_stopwatch()
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_check(_finished == TESTS, "every test ran to its end (%d / %d)" % [_finished, TESTS])
	if _failures.is_empty():
		print("ALL LANDMARK TESTS PASSED")
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


func _test_door(id: String, screen_name: String) -> void:
	print("the %s" % id)
	var town: TownScreen = _screen()
	var door: Dictionary = town.town.doors.filter(func(d: Dictionary) -> bool: return d["id"] == id)[0]
	_put(town.player, door["pad"].get_center() + Vector2(0, 500))
	await _frames(3)
	_put(town.player, door["pad"].get_center())
	var inside := await _wait_for(screen_name)
	_check(inside.name == screen_name, "its pad opens %s (%s)" % [screen_name, inside.name])
	await _press(&"ui_cancel")
	town = await _wait_for("Town")
	_check(town is TownScreen and door["pad"].has_point(town.player.global_position), "  BACK comes out in the town, on its pad")
	_put(town.player, door["pad"].get_center() + Vector2(0, 500))
	await _frames(3)
	_finished += 1


func _test_rocket() -> void:
	print("the rocket")
	var town: TownScreen = _screen()
	var rocket: Sprite2D = town.town.rocket
	var was := rocket.global_position
	_put(town.player, town.town.rocket_pad.get_center() + Vector2(500, 0))
	await _frames(3)
	_put(town.player, town.town.rocket_pad.get_center())
	var risen := 0.0
	var hangar: Node = null
	for i in 300:
		await _frames(1)
		if is_instance_valid(rocket):
			risen = maxf(risen, was.y - rocket.global_position.y)
		if _screen().name == "GarageScreen":
			hangar = _screen()
			break
	_check(risen > 600.0, "the rocket lifts off (%.0f px up)" % risen)
	_check(hangar != null and _manager.vehicle_kind == &"ship", "  then the Hangar opens")
	await _frames(3)
	await _press(&"ui_cancel")
	town = await _wait_for("Town")
	_put(town.player, town.town.rocket_pad.get_center() + Vector2(600, 0))
	await _frames(3)
	_finished += 1


func _test_stopwatch() -> void:
	print("the stopwatch")
	var town: TownScreen = _screen()
	var gate: RaceGate = town.gates.filter(func(g: RaceGate) -> bool: return g.kind == &"car" and g.unlocked)[0]
	var cars := town.gates.filter(func(g: RaceGate) -> bool: return g.kind == &"car")
	var dry := 0
	for g: RaceGate in cars:
		if town.town.surface_at(g.stopwatch) in [&"grass", &"beach", &"snow", &"candy", &"jungle"] and not town.town.streets_rect().grow(-200.0).has_point(g.stopwatch):
			dry += 1
	_check(dry == cars.size(), "every car gate has a stopwatch on dry land (%d of %d)" % [dry, cars.size()])
	_put(town.player, gate.stopwatch, gate.slot_angle())
	await _frames(3)
	_check(town.hud.gate_shown == gate and town.hud.gate_mode == &"time_trial", "pulling up on it shows the card with TIME TRIAL")
	await _press(&"race_start")
	var race := await _wait_for("Race", 4.0)
	_check(race.name == "Race" and _manager.race_mode == &"time_trial", "R / Y starts a time trial (%s, %s)" % [race.name, _manager.race_mode])
	_finished += 1

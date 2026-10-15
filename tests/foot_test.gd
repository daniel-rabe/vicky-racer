extends Node
## Headless checks for getting out of the car (docs/DESIGN.md §29):
##   - stopped, E / Y gets Vicky out: the car stays parked, its seat empty; not while moving;
##   - on foot he walks with the arrows, and runs faster with the drift button held;
##   - walking up to the car and pressing E / Y gets back in;
##   - the driveway cars are free to borrow: getting in one makes it the car, and his own waits
##     parked to come back to;
##   - the whistle brings the car to the kerb nearby;
##   - traffic stops for him in the road; a dog he walks up to is petted and follows him;
##   - a shop's treat goes in his hands on foot, and back on the roof in the car;
##   - on foot, the saved spot is the car's; the garage's pad opens the garage on foot too.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/foot_test.tscn
## Exit code 0 = all passed. Uses its own save and settings files, deleted afterwards.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://foot_test.cfg"
const SETTINGS := "user://foot_test_settings.cfg"
const TESTS := 8

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
	await _test_out_and_in(town)
	await _test_walking(town)
	await _test_borrow(town)
	await _test_whistle(town)
	await _test_traffic(town)
	await _test_petting(town)
	await _test_treat(town)
	await _test_spot_and_door(town)
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_check(_finished == TESTS, "every test ran to its end (%d / %d)" % [_finished, TESTS])
	if _failures.is_empty():
		print("ALL FOOT TESTS PASSED")
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


## Hold `action` for `frames` physics frames; how far the player went.
func _hold(town: TownScreen, action: StringName, frames: int, also: StringName = &"") -> float:
	var from := town.player.global_position
	Input.action_press(action)
	if also != &"":
		Input.action_press(also)
	await _frames(frames)
	Input.action_release(action)
	if also != &"":
		Input.action_release(also)
	await _frames(20)
	return town.player.global_position.distance_to(from)


func _test_out_and_in(town: TownScreen) -> void:
	print("out of the car and back in")
	var own := town.car
	own.velocity = Vector2(400, 0)
	_check(not town.can_get_out(), "not while the car is moving")
	own.velocity = Vector2.ZERO
	await _frames(2)
	_check(town.can_get_out(), "stopped, he may get out")
	await _press(&"get_in_out")
	_check(town.riding == &"foot" and town.player is Kid and town.kid.visible, "E / Y: Vicky is out, on foot")
	_check(own.frozen and own.is_in_group(&"parked") and own.driver_id == &"", "  the car stays parked, its seat empty")
	_check(town.kid.global_position.distance_to(own.global_position) < 130.0, "  and he stands beside it")
	await _frames(70)
	_check(town._prompt.visible, "  a bubble over the car shows E / Y gets back in")
	await _press(&"get_in_out")
	_check(town.riding == &"car" and town.player == own and not own.frozen, "E / Y by the car: back in")
	_check(own.driver_id == DriverLook.VICKY and not town.kid.visible, "  in the seat again")
	_finished += 1


func _test_walking(town: TownScreen) -> void:
	print("walking")
	await _press(&"get_in_out")
	var walked := await _hold(town, &"steer_right", 60)
	_check(walked > 150.0, "the arrows walk him (%.0f px in a second)" % walked)
	var ran := await _hold(town, &"steer_left", 60, &"handbrake")
	_check(ran > walked * 1.3, "the drift button held: he runs (%.0f px)" % ran)
	_check(absf(angle_difference(town.kid.rotation, PI)) < 0.3, "  facing the way he goes")
	_finished += 1


func _test_borrow(town: TownScreen) -> void:
	print("borrowing a driveway car")
	var own := town.car
	var driveway := town.hop_ins.filter(func(c: Car) -> bool: return c != own)
	_check(driveway.size() >= 4, "cars wait in the driveways (%d)" % driveway.size())
	var lent: Car = driveway[0]
	_check(lent.has_meta(&"sign") and lent.driver_id == &"", "  with a key sign, nobody in them")
	_put(town.kid, lent.global_position + Vector2(0, 90))
	await _frames(3)
	await _press(&"get_in_out")
	_check(town.player == lent and town.car == lent and town.riding == &"car", "getting in one: it is the car now")
	_check(not lent.has_meta(&"sign") and not lent.frozen, "  the sign comes down and off it goes")
	_check(own in town.hop_ins and own.frozen, "  his own car waits parked")
	# Back to his own: out, over to it, in.
	await _press(&"get_in_out")
	_put(town.kid, own.global_position + Vector2(0, 90))
	await _frames(3)
	await _press(&"get_in_out")
	_check(town.car == own and lent in town.hop_ins, "and back into his own; the borrowed one stays where it was left")
	_finished += 1


func _test_whistle(town: TownScreen) -> void:
	print("the whistle")
	await _press(&"get_in_out")
	var far := Vector2(5200, 4300)
	_put(town.kid, far)
	await _frames(3)
	EventSystem.CAR_horn.emit(town.kid)
	await _frames(3)
	var gap := town.car.global_position.distance_to(town.kid.global_position)
	_check(gap < 500.0, "H / Y on foot: the car comes (%.0f px away)" % gap)
	_check(town.town.surface_at(town.car.global_position) == &"asphalt", "  parked by the kerb")
	_finished += 1


func _test_traffic(town: TownScreen) -> void:
	print("traffic and walkers")
	var other: Car = null
	for c in town.traffic:
		if c.velocity.length() > 200.0 and town.town.surface_at(c.global_position + Vector2.RIGHT.rotated(c.rotation) * 400.0) == &"asphalt":
			other = c
			break
	_check(other != null, "a car is driving")
	if other == null:
		return
	_put(town.kid, other.global_position + Vector2.RIGHT.rotated(other.rotation) * 330.0)
	var closest := INF
	for i in 70:
		await _frames(1)
		closest = minf(closest, other.global_position.distance_to(town.kid.global_position))
	_check(closest > 60.0 and other.velocity.length() < 60.0, "it stops for him in the road (closest %.0f px)" % closest)
	_finished += 1


func _test_petting(town: TownScreen) -> void:
	print("petting")
	var dog: Walker = null
	for w: Walker in town.get_node("World/Walkers").get_children():
		if w.loop:
			dog = w
			break
	var petted := [false]
	dog.petted.connect(func(_w: Walker) -> void: petted[0] = true)
	_put(town.kid, dog.global_position + Vector2(40, 0))
	await _frames(4)
	_check(petted[0] and dog.friend == town.kid, "walking up to a dog pets it, and it follows him")
	var start := town.kid.global_position
	await _hold(town, &"steer_right", 50)
	_check(dog.global_position.distance_to(town.kid.global_position) < 200.0
		and dog.global_position.distance_to(start) > 100.0, "  trotting after him")
	_finished += 1


func _test_treat(town: TownScreen) -> void:
	print("a treat on foot")
	var shop: Dictionary = town.town.places.filter(func(p: Dictionary) -> bool: return p["id"] == "ice_cream_shop")[0]
	_put(town.kid, shop["door"] + Vector2(0, 600))
	await _frames(3)
	_put(town.kid, shop["door"] + Vector2(0, 30))
	await _frames(6)
	var held: Node = town.kid.get_node_or_null(^"Body/RoofLoad")
	_check(held != null, "the ice cream parlour's treat goes in his hands")
	_put(town.car, town.kid.global_position + Vector2(0, 90), 0.0)
	await _frames(2)
	await _press(&"get_in_out")
	_check(town.riding == &"car" and town.car.get_node_or_null(^"Body/RoofLoad") != null, "  and onto the roof in the car")
	_finished += 1


func _test_spot_and_door(town: TownScreen) -> void:
	print("the saved spot and the doors")
	_put(town.car, Vector2(5200, 2640), PI)
	await _frames(3)
	await _press(&"get_in_out")
	_put(town.kid, Vector2(5200, 3200))
	town.save_spot()
	var spot: Dictionary = _manager.profile.world
	_check(Vector2(spot["x"], spot["y"]).distance_to(town.car.global_position) < 2.0 and spot["riding"] == &"car",
		"on foot, the saved spot is the car's")
	var door: Dictionary = town.town.doors.filter(func(d: Dictionary) -> bool: return d["screen"] == &"garage")[0]
	_put(town.kid, door["pad"].get_center() + Vector2(0, 300))
	await _frames(3)
	_put(town.kid, door["pad"].get_center())
	var garage := await _wait_for("GarageScreen")
	_check(garage.name == "GarageScreen", "walking onto the garage's pad opens the garage")
	_finished += 1

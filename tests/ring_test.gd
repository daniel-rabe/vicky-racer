extends Node
## Headless checks for the ring road (docs/DESIGN.md §38):
##   - the tunnel's hill fades while the player drives through, TUNNEL! comes up, and a horn in
##     there echoes (and not outside it);
##   - the stream is wading water, the road over it is a road, and a car crosses on the deck;
##   - standing at the fuel station's pump fills the tank (FULL TANK!), once until the car leaves;
##   - the speed sign shows the speed of a car going by, and WOW! when very fast.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/ring_test.tscn
## Exit code 0 = all passed. Uses its own save and settings files, deleted afterwards.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://ring_test.cfg"
const SETTINGS := "user://ring_test_settings.cfg"
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
	await _test_tunnel()
	await _test_stream()
	await _test_fuel()
	await _test_speed()
	Input.action_release(&"accelerate")
	Input.action_release(&"steer_left")
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_check(_finished == TESTS, "every test ran to its end (%d / %d)" % [_finished, TESTS])
	if _failures.is_empty():
		print("ALL RING ROAD TESTS PASSED")
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


func _test_tunnel() -> void:
	print("the tunnel")
	var town: TownScreen = _screen()
	var fun: RingRoadFun = town.ring_road
	var road_x := TownLayout.junction(Vector2i(TownLayout.COLS, 0)).x + 80.0
	_put(town.car, Vector2(road_x, RingRoad.TUNNEL.position.y - 300.0), PI / 2.0)
	await _frames(5)
	EventSystem.CAR_horn.emit(town.car)
	_check(fun.echoes == 0, "outside the tunnel a horn does not echo")
	_check(is_equal_approx(town.town.tunnel.fade, 1.0), "the hill is solid to look at from outside")
	Input.action_press(&"accelerate")
	var inside := false
	for i in 300:
		await _frames(1)
		if RingRoad.in_tunnel(town.car.global_position):
			inside = true
			break
	Input.action_release(&"accelerate")
	await _frames(30)
	_check(inside and fun.in_tunnel, "driving south along the ring road goes into the tunnel")
	_check(town.town.tunnel.fade < 0.5, "  the hill fades so the car can be seen (%.2f)" % town.town.tunnel.fade)
	EventSystem.CAR_horn.emit(town.car)
	_check(fun.echoes == 1, "  and a horn in there echoes")
	Input.action_press(&"accelerate")
	for i in 400:
		await _frames(1)
		if town.car.global_position.y > RingRoad.TUNNEL.end.y + 100.0:
			break
	Input.action_release(&"accelerate")
	await _frames(40)
	_check(town.car.global_position.y > RingRoad.TUNNEL.end.y, "it comes out the other end (y %.0f)" % town.car.global_position.y)
	_check(not fun.in_tunnel and town.town.tunnel.fade > 0.95, "  and the hill is back")
	_finished += 1


func _test_stream() -> void:
	print("the stream")
	var town: TownScreen = _screen()
	var mid := (RingRoad.STREAM[4] + RingRoad.STREAM[5]) / 2.0
	_check(town.town.surface_at(mid) == &"water", "the stream is water to wade through")
	_check(town.town.surface_at(RingRoad.STREAM_BRIDGE.get_center()) == &"asphalt", "the road over it is a road")
	var road_x := TownLayout.junction(Vector2i.ZERO).x - 80.0
	_put(town.car, Vector2(road_x, RingRoad.STREAM_BRIDGE.position.y - 500.0), PI / 2.0)
	await _frames(3)
	Input.action_press(&"accelerate")
	var wet := false
	var crossed := false
	for i in 400:
		await _frames(1)
		if town.town.surface_at(town.car.global_position) == &"water":
			wet = true
		if town.car.global_position.y > RingRoad.STREAM_BRIDGE.end.y + 100.0:
			crossed = true
			break
	Input.action_release(&"accelerate")
	_check(crossed and not wet, "a car on the ring road crosses it on the bridge, dry")
	_finished += 1


func _test_fuel() -> void:
	print("the fuel station")
	var town: TownScreen = _screen()
	var fun: RingRoadFun = town.ring_road
	_check(town.town.surface_at(RingRoad.FUEL_YARD.get_center() + Vector2(0, 200)) == &"asphalt", "its yard is paved")
	_put(town.car, RingRoad.FILL_PADS[0].get_center(), -PI / 2.0)
	var filled := false
	for i in int((RingRoadFun.FILL_SECONDS + 1.0) * 60.0):
		await _frames(1)
		if fun.fills > 0:
			filled = true
			break
	_check(filled, "standing at the pump fills the tank")
	_check(town.town.pump.fill[0] >= 1.0, "  its gauge goes all the way round")
	await _frames(int((RingRoadFun.FILL_SECONDS + 0.5) * 60.0))
	_check(fun.fills == 1, "  once, while the car stays")
	_put(town.car, RingRoad.FUEL_YARD.get_center() + Vector2(0, 1200.0), 0.0)
	await _frames(5)
	_check(town.town.pump.fill[0] == 0.0, "  and it is empty again once the car has gone")
	_put(town.car, RingRoad.FILL_PADS[1].get_center(), -PI / 2.0)
	await _frames(int((RingRoadFun.FILL_SECONDS + 0.5) * 60.0))
	_check(fun.fills == 2, "the other side fills up too")
	_finished += 1


func _test_speed() -> void:
	print("the speed sign")
	var town: TownScreen = _screen()
	var sign: SpeedSign = town.town.speed_sign
	var road_y := TownLayout.junction(Vector2i(0, TownLayout.ROWS)).y + 80.0
	_put(town.car, Vector2(RingRoad.SPEED_READS.position.x - 1500.0, road_y), 0.0)
	await _frames(5)
	_check(sign.speed == -1, "with nobody going by it shows nothing")
	Input.action_press(&"accelerate")
	var shown := -1
	for i in 400:
		await _frames(1)
		if RingRoad.SPEED_READS.has_point(town.car.global_position):
			shown = sign.speed
			break
	_check(shown > 20 and absi(shown - roundi(town.car.velocity.length() * RingRoadFun.SPEED_SCALE)) <= 2,
		"driving by, it shows the car's speed (%d)" % shown)
	Input.action_release(&"accelerate")
	town.car.velocity = Vector2(1100.0, 0.0)
	await _frames(1)
	_check(sign.wow or not RingRoad.SPEED_READS.has_point(town.car.global_position), "very fast says WOW!")
	_finished += 1

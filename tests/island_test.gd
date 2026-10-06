extends Node
## Headless test of Free Drive's island (docs/DESIGN.md §21):
##   - surfaces: the grass, the beach, the shallows by the shore, deep water out at sea, the quay;
##   - a car driven at the sea stops on the beach, a boat driven at the land stops in the water;
##   - driving onto the land pad swaps the car for the equipped boat, in its paint, at the
##     mooring, with the camera on it; the car waits on the pad;
##   - a coin at sea pays, the ramp throws the boat over its islet, the lighthouse is a place;
##   - sailing back into the mooring swaps back to the car, camera and all.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/island_test.tscn
## Exit code 0 = all passed.

const TOWN_SCENE := preload("res://game/screens/town.tscn")
const BOAT_ID := &"jetski"
const BOAT_PAINT := &"pink"

var screen: Node2D
var _coins_found := 0
var _jumped: Array[Node] = []
var _places: Array[String] = []
var _failures: PackedStringArray = []


func _enter_tree() -> void:
	EventSystem.UI_settings_requested.connect(func() -> void:
		EventSystem.UI_settings_changed.emit({"sound_volume": 0.0, "music_volume": 0.0, "fullscreen": false,
			"auto_accelerate": false, "steering_help": false, "difficulty": &"normal"}))
	EventSystem.PRO_state_requested.connect(func() -> void:
		EventSystem.PRO_state_changed.emit({"setups": [load("res://game/configs/setups/starter.tres")],
			"equipped": &"starter", "equipped_boat": BOAT_ID, "coins": 0, "paint": {BOAT_ID: BOAT_PAINT}}))
	EventSystem.PRO_coins_found.connect(func(amount: int) -> void: _coins_found += amount)
	EventSystem.CAR_jumped.connect(func(boat: Node) -> void: _jumped.append(boat))


func _ready() -> void:
	screen = TOWN_SCENE.instantiate()
	add_child(screen)
	screen.town.place_reached.connect(func(id: String, _name: String, _picture: Texture2D) -> void:
		_places.append(id))
	await _frames(5)
	await _run()
	if _failures.is_empty():
		print("ALL ISLAND TESTS PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _run() -> void:
	var town: Town = screen.town
	var west := _coast_point_at(Vector2(-1, 0), 4160.0)  # the waterline on the west coast

	# Surfaces, out from the town to the sea.
	_check(town.surface_at(Vector2(TownLayout.world_size().x / 2.0, 450.0)) == &"grass", "the grass beyond the ring road is grass")
	_check(town.surface_at(west + Vector2(150, 0)) == &"beach", "the beach is sand (%s)" % town.surface_at(west + Vector2(150, 0)))
	_check(town.surface_at(west - Vector2(150, 0)) == &"lagoon_water", "the water by the shore is shallows")
	_check(town.surface_at(west - Vector2(1500, 0)) == &"deep_water", "out at sea is deep water")
	_check(town.surface_at(Island.LAND_PAD.get_center()) == &"asphalt", "the quay is paved")
	_check(town.surface_at(Island.LIGHTHOUSE) == &"sandbank", "an islet is sand")

	# A car driven at the sea stops on the beach.
	var car: Car = screen.car
	_put(car, west + Vector2(260, 0), PI)
	await _drive(2.5)
	var on_land := Geometry2D.is_point_in_polygon(car.global_position, Island.outline(0.0))
	_check(on_land and car.global_position.x > west.x, "a car driven at the sea stops at the waterline (at %s, waterline x %.0f)"
		% [car.global_position.round(), west.x])

	# Onto the land pad: the equipped boat, in its paint, at the mooring.
	_put(car, Vector2(Island.LAND_PAD.end.x + 200.0, Island.LAND_PAD.get_center().y), PI)
	await _frames(3)
	_put(car, Island.LAND_PAD.get_center(), PI)
	await _seconds(1.0)
	var boat: Boat = screen.boat
	_check(screen.sailing and boat != null and screen.player == boat, "driving onto the land pad swaps to the boat")
	if boat == null:
		return
	_check(boat.setup.id == BOAT_ID and boat.body_texture == Paint.body(boat.setup, BOAT_PAINT),
		"it is the equipped boat in its paint (%s)" % boat.setup.id)
	_check(Island.MOORING.grow(80.0).has_point(boat.global_position), "the boat starts at the mooring")
	_check(boat.has_node(^"PlayerInput") and not car.has_node(^"PlayerInput") and car.frozen,
		"the player steers the boat; the car waits on the pad")
	_check(get_viewport().get_camera_2d() == boat.get_node(^"ChaseCamera/Camera"), "the camera follows the boat")

	# A boat driven at the land stops in the water.
	_put(boat, west - Vector2(400, 0), 0.0)
	await _drive(2.5)
	var in_water := not Geometry2D.is_point_in_polygon(boat.global_position, Island.outline(0.0))
	_check(in_water and boat.global_position.x < west.x, "a boat driven at the land stops at the waterline (at %s)"
		% boat.global_position.round())

	# A coin at sea.
	var before := _coins_found
	_put(boat, Island.sea_coins()[0], 0.0)
	await _frames(6)
	_check(_coins_found - before == screen.COIN_VALUE, "a coin at sea pays %d (paid %d)" % [screen.COIN_VALUE, _coins_found - before])

	# The ramp throws the boat over its islet.
	var islet: Vector2 = Island.RAMP_ISLETS[0][0]
	var throw: Vector2 = Island.RAMP_ISLETS[0][1]
	_put(boat, Island.ramp_at(0) - throw * 700.0, throw.angle())
	await _drive(2.2)
	var past := (boat.global_position - islet).dot(throw)
	_check(boat in _jumped, "the ramp throws the boat in the air")
	_check(past > Island.RAMP_ISLET_RADIUS, "and it lands beyond the islet (%.0f px past its middle)" % past)

	# The lighthouse is a place.
	_put(boat, Island.LIGHTHOUSE + Vector2(-650, 300), 0.0)
	await _frames(6)
	_check("lighthouse" in _places, "sailing up to the lighthouse counts as a place (%s)" % [_places])

	# Back into the mooring: the car again, on the land pad, facing up the harbour road.
	_put(boat, Island.MOORING.get_center() + Vector2(0, 160), -PI / 2.0)
	await _frames(3)
	_put(boat, Island.MOORING.get_center(), -PI / 2.0)
	await _seconds(1.0)
	_check(not screen.sailing and screen.player == car and car.has_node(^"PlayerInput") and not car.frozen,
		"sailing into the mooring swaps back to the car")
	_check(Island.LAND_PAD.has_point(car.global_position) and boat.frozen and Island.MOORING.grow(80.0).has_point(boat.global_position),
		"the car is on the land pad; the boat is tied up at the mooring")
	_check(get_viewport().get_camera_2d() == car.get_node(^"ChaseCamera/Camera"), "the camera follows the car")
	await _seconds(1.0)
	_check(not screen.sailing, "standing on the pad does not swap straight back")


## The waterline's point furthest out in `direction` near the line through `across`.
func _coast_point_at(direction: Vector2, across: float) -> Vector2:
	var best := Vector2.ZERO
	var best_d := INF
	for p in Island.outline(0.0):
		var off := absf(p.y - across) if direction.x != 0.0 else absf(p.x - across)
		if off < best_d and p.dot(direction) > 0.0:
			best_d = off
			best = p
	return best


func _put(vehicle: Car, at: Vector2, angle: float) -> void:
	vehicle.global_position = at
	vehicle.rotation = angle
	vehicle.velocity = Vector2.ZERO
	vehicle.reset_physics_interpolation()


## Full throttle for `seconds`.
func _drive(seconds: float) -> void:
	Input.action_press(&"accelerate")
	await _seconds(seconds)
	Input.action_release(&"accelerate")
	await _frames(2)


func _seconds(seconds: float) -> void:
	await _frames(int(seconds * 60.0))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _check(ok: bool, message: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + message)
	if not ok:
		_failures.append(message)

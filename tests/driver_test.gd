extends Node
## Headless test: every vehicle has a seat and every racer a driver (docs/DESIGN.md §22).
## The vehicles with an open seat or glass have a seat in every paint, and the closed-roof ones
## none; every driver has a picture for both kinds; a car seats its driver and reseats them when
## repainted; a race gives Vicky, the friend and the three opponents their driver ids.
##   Godot_console.exe --path . --headless res://tests/driver_test.tscn
## Exit code 0 = all passed.

const CAR_SCENE := preload("res://actors/car/car.tscn")
const BOAT_SCENE := preload("res://actors/boat/boat.tscn")
## Those that show a driver; the rest keep theirs hidden under the roof (docs/DESIGN.md §22.2).
const SEATED: Array[String] = ["kart", "bubble", "formula", "speedboat", "jetski", "duck", "swan", "tugboat",
	"pirate", "banana_boat"]
const TOWN_VEHICLES: Array[String] = ["bus", "fire_engine", "garbage_truck"]

var _failures: PackedStringArray = []


func _ready() -> void:
	var setups: Array[DriftSetup] = []
	for dir in ["res://game/configs/setups/", "res://game/configs/boats/"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".tres"):
				setups.append(load(dir + file))
	var wrong: PackedStringArray = []
	for setup in setups:
		for colour in Paint.COLOURS:
			var body := Paint.body(setup, colour)
			if DriverSeats.seat_for(body).is_empty() == (String(setup.id) in SEATED):
				wrong.append(body.resource_path)
	_check(setups.size() == 21, "21 vehicles found (%d)" % setups.size())
	_check(wrong.is_empty(), "open and glass vehicles have a seat in every paint, closed roofs none %s" % [wrong])
	_check(DriverSeats.seat_for(load("res://art/town/vehicles/delivery_van.png")).is_empty(),
		"the delivery van shows nobody (its windscreen is its face)")
	for name in TOWN_VEHICLES:
		var body: Texture2D = load("res://art/town/vehicles/%s.png" % name)
		_check(not DriverSeats.seat_for(body).is_empty(), "the %s has a seat" % name)
		var grown_up := DriverLook.for_traffic(body)
		_check(DriverLook.texture(grown_up, &"car") != null, "the %s has a driver (%s)" % [name, grown_up])
	for kid in DriverLook.KIDS:
		_check(DriverLook.texture(kid, &"car") != null and DriverLook.texture(kid, &"boat") != null,
			"%s has a helmet for cars and a cap for boats" % kid)

	var bubble: DriftSetup = load("res://game/configs/setups/bubble.tres")
	var car: Car = CAR_SCENE.instantiate()
	car.setup = bubble
	car.driver_id = DriverLook.VICKY
	add_child(car)
	var rider := car.get_node_or_null(^"Body/Driver") as DriverRider
	_check(rider != null and rider.mode == DriverSeats.GLASS, "Vicky sits under the bubble car's dome")
	car.body_texture = Paint.body(bubble, &"pink")
	await get_tree().process_frame
	_check(car.get_node(^"Body").get_children().filter(func(n: Node) -> bool: return n is DriverRider).size() == 1,
		"a repaint reseats the driver, once")
	car.driver_id = &""
	await get_tree().process_frame
	_check(car.get_node_or_null(^"Body/Driver") == null, "no driver id, nobody at the wheel")
	car.queue_free()

	var boat: Car = BOAT_SCENE.instantiate()
	boat.setup = load("res://game/configs/boats/jetski.tres")
	boat.driver_id = &"green"
	add_child(boat)
	var on_boat := boat.get_node_or_null(^"Body/Driver") as DriverRider
	_check(on_boat != null and on_boat.mode == DriverSeats.OPEN, "a jet ski's rider sits on top")
	_check(on_boat != null and on_boat.get_node(^"Figure").texture == DriverLook.texture(&"green", &"boat"),
		"on a boat the driver wears the cap and life vest")
	boat.queue_free()

	await _check_race()
	if _failures.is_empty():
		print("ALL DRIVER TESTS PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _check_race() -> void:
	var config: TrackConfig = load("res://game/configs/tracks/track_01.tres")
	var track: Track = config.track_scene.instantiate()
	add_child(track)
	var kart: DriftSetup = load("res://game/configs/setups/kart.tres")
	var spawner := RacerSpawner.new()
	var seen: Array[StringName] = []
	for racer in spawner.spawn(track, config, [{"setup": kart}] as Array[Dictionary], track, true):
		var racer_car: Car = racer["car"]
		if racer["is_player"]:
			_check(racer_car.get_node_or_null(^"Body/Driver") != null, "Vicky shows in the kart")
		seen.append(racer_car.driver_id)
		racer_car.queue_free()
	_check(seen.count(DriverLook.VICKY) == 1, "Vicky drives the player's car %s" % [seen])
	for kid in DriverLook.OPPONENTS:
		_check(kid in seen, "the %s kid drives an opponent" % kid)
	var two: Array[Dictionary] = [{"setup": kart}, {"setup": kart, "action_prefix": "p2_"}]
	var pair := spawner.spawn(track, config, two, track, true, null, false)
	_check(pair.map(func(r: Dictionary) -> StringName: return r["car"].driver_id) == [DriverLook.VICKY, DriverLook.PLAYER_2],
		"in a two-player race the friend drives player 2's car")
	await get_tree().process_frame
	track.queue_free()


func _check(ok: bool, message: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + message)
	if not ok:
		_failures.append(message)

extends Node
## Headless checks for the boats (docs/DESIGN.md §20).
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/boat_test.tscn
## Exit code 0 = all passed. Uses its own save file, never the player's.
##
## Checks: a boat is a Car, made by the spawner from a boat course's config; it glides
## further than a car once the throttle is let go; the channel is deep water at full speed,
## the shallows and banks slow a boat but not a hovercraft; a current carries a boat along;
## a ramp throws a boat in the air and it splashes down; the alternative paths' progress is
## the stretch of lap they bypass; the garage keeps cars and boats apart (roster, equipped,
## courses, one wallet); a version 3 save comes in with the Speedboat; boat paint jobs load.
## A full race on every course: tests/race_test.tscn -- --autopilot --track=boat_0N --setup=<boat>.

const SAVE := "user://boat_test.cfg"
const ECONOMY := preload("res://game/configs/economy.tres")
const CAR_SCENE := preload("res://actors/car/car.tscn")
const BOAT_SCENE := preload("res://actors/boat/boat.tscn")
const COURSES: Array[StringName] = [&"boat_01", &"boat_02", &"boat_03", &"boat_04"]

var _failures: PackedStringArray = []
var _landed := 0
var _jumped := 0


func _ready() -> void:
	EventSystem.CAR_jumped.connect(func(_b: Node) -> void: _jumped += 1)
	EventSystem.CAR_landed.connect(func(_b: Node) -> void: _landed += 1)
	_wipe()
	await _test_spawned_boats_are_cars()
	await _test_glide()
	await _test_surfaces()
	await _test_current()
	await _test_ramp()
	await _test_branch_progress()
	_test_garage_kinds()
	_test_version_3_save_gets_a_boat()
	_test_boat_paint_and_courses_load()
	_wipe()
	if _failures.is_empty():
		print("ALL BOAT TESTS PASSED")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures.append(message)


func _wipe() -> void:
	for path in [SAVE, SAVE + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _course(id: StringName) -> Track:
	var config: TrackConfig = load("res://game/configs/tracks/%s.tres" % id)
	var track: Track = config.track_scene.instantiate()
	add_child(track)
	return track


func _boat(setup_id: StringName, at: Vector2, heading: float) -> Boat:
	var boat: Boat = BOAT_SCENE.instantiate()
	boat.setup = load("res://game/configs/boats/%s.tres" % setup_id)
	boat.global_position = at
	boat.rotation = heading
	add_child(boat)
	return boat


func _test_spawned_boats_are_cars() -> void:
	var config: TrackConfig = load("res://game/configs/tracks/boat_01.tres")
	var track: Track = config.track_scene.instantiate()
	add_child(track)
	var racers := Node2D.new()
	add_child(racers)
	var spawner := RacerSpawner.new()
	add_child(spawner)
	var humans: Array[Dictionary] = [{"setup": load("res://game/configs/boats/speedboat.tres")}]
	var spawned := spawner.spawn(track, config, humans, racers, true)
	await _frames(2)
	_check(spawned.size() == 4, "a boat course spawns four racers (%d)" % spawned.size())
	_check(spawned.all(func(r: Dictionary) -> bool: return r["car"] is Boat and r["car"] is Car),
		"every racer on a boat course is a Boat, and a Boat is a Car")
	_check(track.surface_at(spawned[0]["car"].global_position) == &"deep_water",
		"the grid is in the channel, on deep water")
	for node: Node in [track, racers, spawner]:
		node.queue_free()
	await _frames(1)


## Up to the same speed, then the throttle let go: the boat coasts further.
func _test_glide() -> void:
	var distances := {}
	for scene: PackedScene in [CAR_SCENE, BOAT_SCENE]:
		var vehicle: Car = scene.instantiate()
		vehicle.global_position = Vector2.ZERO
		add_child(vehicle)
		await _frames(1)
		vehicle.velocity = Vector2(700, 0)
		vehicle.throttle_input = 0.0
		await _frames(120)
		distances[scene] = vehicle.global_position.x
		vehicle.queue_free()
	_check(distances[BOAT_SCENE] > distances[CAR_SCENE] * 1.15,
		"a boat glides further than a car with the throttle off (%.0f vs %.0f px in 2 s)" % [distances[BOAT_SCENE], distances[CAR_SCENE]])


func _test_surfaces() -> void:
	var track := _course(&"boat_01")
	await _frames(2)
	var channel := track.line_point(track.lap_length() * 0.25)
	var shallows := track.line_point(track.lap_length() * 0.25, track.road_half_width + 260.0)
	var bank := Vector2(42, 31) * 128.0  # the middle of the duck house's sandbank island
	_check(track.surface_at(channel) == &"deep_water", "the channel is deep water")
	_check(track.surface_at(shallows) == &"pond_water", "off the channel is the pond's shallows (%s)" % track.surface_at(shallows))
	_check(track.surface_at(bank) == &"sandbank", "the island is a sandbank (%s)" % track.surface_at(bank))
	var boat := _boat(&"speedboat", bank, 0.0)
	var hover := _boat(&"hovercraft", bank + Vector2(300, 0), 0.0)
	await _frames(3)
	_check(boat.surface_speed() < 0.5, "a sandbank holds a speedboat back (x%.2f)" % boat.surface_speed())
	_check(is_equal_approx(hover.surface_speed(), 1.0), "a hovercraft skims the sandbank at full speed")
	for node: Node in [track, boat, hover]:
		node.queue_free()
	await _frames(1)


## Jungle River's first current: a boat sitting still in it, throttle off, is carried along.
func _test_current() -> void:
	var track := _course(&"boat_02")
	await _frames(2)
	var span: Vector3 = track.current_spans[0]
	var at := track.lap_length() * (span.x + span.y * 0.3)
	var tangent := track.line_tangent(at)
	var boat := _boat(&"speedboat", track.line_point(at), tangent.angle() + PI / 2.0)  # broadside, not driving
	await _frames(60)
	var carried := boat.velocity.dot(tangent)
	_check(boat.current.length() > 100.0, "inside a current span the track sets the boat's current (%.0f px/s)" % boat.current.length())
	_check(carried > 120.0, "the current carries an idle boat along (%.0f px/s after 1 s)" % carried)
	track.queue_free()
	boat.queue_free()
	await _frames(1)


## Duck Pond's ramp: a boat driven across it flies, sails over the others, and comes down.
func _test_ramp() -> void:
	var track := _course(&"boat_01")
	await _frames(2)
	var ramp: Area2D = track.get_node("Ramps").get_child(0)
	var back := Vector2.RIGHT.rotated(ramp.rotation)
	var boat := _boat(&"speedboat", ramp.global_position - back * 400.0, ramp.rotation)
	await _frames(1)
	boat.velocity = back * 800.0
	boat.throttle_input = 1.0
	var flew := false
	var over_others := false
	for i in 90:
		await get_tree().physics_frame
		if boat.is_airborne():
			flew = true
			over_others = boat.collision_layer == Car.LAYER_AIRBORNE and boat.collision_mask == Car.LAYER_WORLD
	_check(flew and _jumped > 0, "crossing a ramp throws the boat in the air")
	_check(over_others, "in the air it only touches the walls")
	_check(not boat.is_airborne() and _landed > 0, "and it comes back down (CAR_landed)")
	_check(boat.collision_layer == Car.LAYER_CARS_GROUND, "back on the water it is an ordinary racer again")
	track.queue_free()
	boat.queue_free()
	await _frames(1)


## Every course's branches: halfway along one, progress is halfway through what it bypasses.
func _test_branch_progress() -> void:
	for id in COURSES:
		var track := _course(id)
		await _frames(2)
		_check(track.branch_lines.size() == 2, "%s has two alternative paths" % id)
		for b in track.branch_lines.size():
			var line := track.branch_lines[b]
			var middle := line[line.size() / 2]
			var boat := _boat(&"speedboat", middle, 0.0)
			await _frames(2)
			var lap := track.lap_length()
			var entry := track.branch_entry(b)
			var bypassed := fposmod(track.branch_exit(b) - entry, lap)
			var into := fposmod(track.progress_of(boat) - entry, lap)
			_check(track.branch_of(boat) == b and into > bypassed * 0.25 and into < bypassed * 0.75,
				"%s path %d: halfway along it is half way through the stretch it skips (%.0f of %.0f px)" % [id, b, into, bypassed])
			boat.queue_free()
			await _frames(1)
		track.queue_free()
		await _frames(1)


func _test_garage_kinds() -> void:
	var m := GarageManager.new()
	m.economy = ECONOMY
	m.save_path = SAVE
	add_child(m)
	var state := {}  # filled in place: a lambda cannot reassign the variable it captured
	var listen := func(s: Dictionary) -> void:
		state.clear()
		state.merge(s)
	EventSystem.PRO_state_changed.connect(listen)
	EventSystem.PRO_vehicle_kind_requested.emit(&"boat")
	_check(state.get("vehicle_kind") == &"boat", "BOATS switches the garage to the boats")
	_check(state["setups"].size() == 9 and state["setups"].all(func(s: DriftSetup) -> bool: return s.kind == &"boat"),
		"the Boat Dock shows the nine boats")
	_check(state["equipped"] == &"speedboat" and &"speedboat" in state["owned"], "a new player owns and sails the Speedboat")
	_check(state["tracks"].size() == 4 and state["tracks"][0]["unlocked"] and not state["tracks"][1]["unlocked"],
		"four boat courses, the first one open")
	_check(state["equipped_car"] == &"starter", "and still drives the Starter car")
	m.profile.coins = 1000
	m.buy(&"jetski")
	_check(m.profile.equipped_boat == &"jetski" and m.profile.equipped_setup == &"starter",
		"buying a boat equips it as the boat, the car stays")
	_check(m.profile.coins == 900, "boats are paid from the one wallet")
	EventSystem.PRO_vehicle_kind_requested.emit(&"car")
	_check(state["setups"].all(func(s: DriftSetup) -> bool: return s.kind == &"car") and state["equipped"] == &"starter",
		"CARS switches back to the cars")
	EventSystem.PRO_state_changed.disconnect(listen)
	m.queue_free()
	var again := SaveGame.load_from(SAVE)
	_check(again.equipped_boat == &"jetski" and &"jetski" in again.owned_setups, "the boat survives a save and load")


func _test_version_3_save_gets_a_boat() -> void:
	var file := ConfigFile.new()
	file.set_value("profile", "schema_version", 3)
	file.set_value("profile", "coins", 120)
	file.set_value("profile", "owned_setups", PackedStringArray(["starter", "grippy"]))
	file.set_value("profile", "equipped_setup", "grippy")
	file.save(SAVE)
	var profile := SaveGame.load_from(SAVE)
	_check(profile.coins == 120 and profile.equipped_setup == &"grippy", "a version 3 save keeps its cars and coins")
	_check(&"speedboat" in profile.owned_setups and profile.equipped_boat == &"speedboat"
		and profile.selected_course == &"boat_01", "and comes in with the Speedboat on Duck Pond")


func _test_boat_paint_and_courses_load() -> void:
	var missing: PackedStringArray = []
	for id in GarageManager.BOAT_SETUP_ORDER:
		var setup: DriftSetup = load("res://game/configs/boats/%s.tres" % id)
		for colour in Paint.COLOURS:
			if Paint.body(setup, colour) == null or Paint.card(setup, colour) == null:
				missing.append("%s %s" % [id, colour])
			elif colour != Paint.ORIGINAL and Paint.body(setup, colour) == setup.body and setup.id not in [&"jetski", &"duck", &"banana_boat"]:
				missing.append("%s %s (falls back)" % [id, colour])
	_check(missing.is_empty(), "every boat loads in every paint %s" % [missing])
	var cup: CupConfig = load("res://game/configs/cups/splash.tres")
	_check(cup.vehicle_kind == &"boat" and cup.tracks.size() == 4, "the Splash Cup is the four boat courses")

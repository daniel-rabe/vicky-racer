extends Node
## Headless checks for the spaceships and space courses (docs/DESIGN.md §23).
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/space_test.tscn
## Exit code 0 = all passed. Uses its own save file, never the player's.
##
## Checks: a ship is a Ship, a Boat and a Car, made by the spawner from a space course's
## config; it floats further than a boat once the throttle is let go; the lane is full speed,
## the dust and the clouds slow it; a drifting asteroid bounces it off without stopping it; a
## comet warns, flies, nudges a ship sideways once and never spins it, and comes again on its
## rhythm; the alternative paths' progress is the stretch of lap they bypass; the garage keeps
## cars, boats and ships apart (roster, equipped, courses, one wallet); a version 4 save comes
## in with the Star Fighter; ship paint jobs load; the Comet Cup and the new stickers.
## A full race on every course: tests/race_test.tscn -- --autopilot --track=space_0N --setup=<ship>.

const SAVE := "user://space_test.cfg"
const ECONOMY := preload("res://game/configs/economy.tres")
const BOAT_SCENE := preload("res://actors/boat/boat.tscn")
const SHIP_SCENE := preload("res://actors/ship/ship.tscn")
const COMET_SCRIPT := preload("res://actors/space/comet.gd")
const COURSES: Array[StringName] = [&"space_01", &"space_02", &"space_03", &"space_04"]

var _failures: PackedStringArray = []
var _warned := 0
var _passing := 0
var _nudged := 0
var _bumps := 0


func _ready() -> void:
	EventSystem.SPC_comet_warned.connect(func(_c: Node) -> void: _warned += 1)
	EventSystem.SPC_comet_passing.connect(func(_c: Node) -> void: _passing += 1)
	EventSystem.CAR_comet_nudged.connect(func(_s: Node) -> void: _nudged += 1)
	EventSystem.CAR_wall_hit.connect(func(_s: Node, _i: float) -> void: _bumps += 1)
	_wipe()
	await _test_spawned_ships_are_cars()
	await _test_float()
	await _test_surfaces()
	await _test_asteroid_bump()
	await _test_comet()
	await _test_branch_progress()
	_test_garage_kinds()
	_test_version_4_save_gets_a_ship()
	_test_ship_paint_and_cup_load()
	await _test_stickers()
	_wipe()
	if _failures.is_empty():
		print("ALL SPACE TESTS PASSED")
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


func _ship(setup_id: StringName, at: Vector2, heading: float) -> Ship:
	var ship: Ship = SHIP_SCENE.instantiate()
	ship.setup = load("res://game/configs/ships/%s.tres" % setup_id)
	ship.global_position = at
	ship.rotation = heading
	add_child(ship)
	return ship


func _test_spawned_ships_are_cars() -> void:
	var config: TrackConfig = load("res://game/configs/tracks/space_01.tres")
	var track: Track = config.track_scene.instantiate()
	add_child(track)
	var racers := Node2D.new()
	add_child(racers)
	var spawner := RacerSpawner.new()
	add_child(spawner)
	var humans: Array[Dictionary] = [{"setup": load("res://game/configs/ships/fighter.tres")}]
	var spawned := spawner.spawn(track, config, humans, racers, true)
	await _frames(2)
	_check(spawned.size() == 4, "a space course spawns four racers (%d)" % spawned.size())
	_check(spawned.all(func(r: Dictionary) -> bool: return r["car"] is Ship and r["car"] is Boat and r["car"] is Car),
		"every racer on a space course is a Ship, a Ship is a Boat, a Boat is a Car")
	_check(track.surface_at(spawned[0]["car"].global_position) == &"star_lane", "the grid is on the star lane")
	_check(spawned.all(func(r: Dictionary) -> bool: return r["car"].get_node("Body").get_node_or_null(^"Driver") == null),
		"no driver is drawn over a ship: its pilot is in the picture")
	for node: Node in [track, racers, spawner]:
		node.queue_free()
	await _frames(1)


## Up to the same speed, then the throttle let go: the ship floats further than a boat.
func _test_float() -> void:
	var distances := {}
	for scene: PackedScene in [BOAT_SCENE, SHIP_SCENE]:
		var vehicle: Car = scene.instantiate()
		vehicle.global_position = Vector2.ZERO
		add_child(vehicle)
		await _frames(1)
		vehicle.velocity = Vector2(700, 0)
		vehicle.throttle_input = 0.0
		await _frames(120)
		distances[scene] = vehicle.global_position.x
		vehicle.queue_free()
	_check(distances[SHIP_SCENE] > distances[BOAT_SCENE] * 1.05,
		"a ship floats further than a boat with the throttle off (%.0f vs %.0f px in 2 s)" % [distances[SHIP_SCENE], distances[BOAT_SCENE]])


func _test_surfaces() -> void:
	var track := _course(&"space_01")
	await _frames(2)
	var lane := track.line_point(track.lap_length() * 0.25)
	# Open dust between the moon and the Crater Cut: clear of the lane, the paths and the rocks.
	var dust := Vector2(58, 26) * 128.0
	var moon := Vector2(40, 31) * 128.0  # the middle of the moon, inside the loop
	_check(track.surface_at(lane) == &"star_lane", "the lane is the star lane")
	_check(track.surface_at(dust) == &"space_navy", "off the lane is starry dust (%s)" % track.surface_at(dust))
	_check(track.surface_at(moon) == &"moon_surface", "the moon is a slow cloud (%s)" % track.surface_at(moon))
	var on_moon := _ship(&"fighter", moon + Vector2(0, 300), 0.0)
	var in_dust := _ship(&"fighter", dust, 0.0)
	await _frames(3)
	_check(on_moon.surface_speed() < 0.5, "the moon holds a ship back (x%.2f)" % on_moon.surface_speed())
	_check(in_dust.surface_speed() < 0.8 and in_dust.surface_speed() > on_moon.surface_speed(),
		"the dust holds it back less (x%.2f)" % in_dust.surface_speed())
	for node: Node in [track, on_moon, in_dust]:
		node.queue_free()
	await _frames(1)


## Flown straight at a drifting asteroid: a soft bump and a push back, never a stop.
func _test_asteroid_bump() -> void:
	var track := _course(&"space_01")
	await _frames(2)
	var rock: Node2D = track.get_node("Asteroids").get_child(0)
	rock.set_physics_process(false)  # hold it still for a clean hit
	var ship := _ship(&"fighter", rock.global_position + Vector2(-420, 0), 0.0)
	await _frames(1)
	var bumps_before := _bumps
	var fastest_after := 0.0
	ship.velocity = Vector2(700, 0)
	ship.throttle_input = 1.0
	for i in 60:
		await get_tree().physics_frame
		if _bumps > bumps_before:
			fastest_after = maxf(fastest_after, ship.velocity.length())
	_check(_bumps > bumps_before, "flying into a drifting asteroid is a bump (CAR_wall_hit)")
	_check(fastest_after > 150.0, "and the ship keeps moving after it (%.0f px/s)" % fastest_after)
	track.queue_free()
	ship.queue_free()
	await _frames(1)


## A comet across a ship sitting still: the streak warns, the comet flies, the ship is nudged
## once along the comet's way and not turned; then it comes again on its rhythm.
func _test_comet() -> void:
	var ship := _ship(&"fighter", Vector2(2000, 2000), 0.5)
	var comet := Node2D.new()
	comet.set_script(COMET_SCRIPT)
	comet.set("from", Vector2(1400, 2000))
	comet.set("to", Vector2(2600, 2000))
	comet.set("period", 3.0)
	add_child(comet)
	await _frames(1)
	var heading := ship.rotation
	var warned := _warned
	var nudged := _nudged
	await _frames(int(3.0 * 60) + 5)
	_check(_warned == warned + 1 and _passing >= 1, "the comet warns, then flies (%d warning, %d passing)" % [_warned - warned, _passing])
	_check(_nudged == nudged + 1, "a ship in its path is nudged exactly once (%d)" % (_nudged - nudged))
	_check(ship.velocity.x > 150.0, "pushed along the comet's way (%.0f px/s)" % ship.velocity.x)
	_check(absf(angle_difference(ship.rotation, heading)) < 0.01, "and never turned round")
	await _frames(int(3.0 * 60))
	_check(_warned == warned + 2, "it comes again one period later (%d warnings)" % (_warned - warned))
	comet.queue_free()
	ship.queue_free()
	await _frames(1)


## Every course's branches: halfway along one, progress is halfway through what it bypasses.
func _test_branch_progress() -> void:
	for id in COURSES:
		var track := _course(id)
		await _frames(2)
		_check(track.branch_lines.size() == 2, "%s has two alternative paths" % id)
		for b in track.branch_lines.size():
			var line := track.branch_lines[b]
			var ship := _ship(&"fighter", line[line.size() / 2], 0.0)
			await _frames(2)
			var lap := track.lap_length()
			var entry := track.branch_entry(b)
			var bypassed := fposmod(track.branch_exit(b) - entry, lap)
			var into := fposmod(track.progress_of(ship) - entry, lap)
			_check(track.branch_of(ship) == b and into > bypassed * 0.25 and into < bypassed * 0.75,
				"%s path %d: halfway along it is half way through the stretch it skips (%.0f of %.0f px)" % [id, b, into, bypassed])
			ship.queue_free()
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
	EventSystem.PRO_vehicle_kind_requested.emit(&"ship")
	_check(state.get("vehicle_kind") == &"ship", "SPACE switches the garage to the ships")
	_check(state["setups"].size() == 9 and state["setups"].all(func(s: DriftSetup) -> bool: return s.kind == &"ship"),
		"the Hangar shows the nine ships")
	_check(state["equipped"] == &"fighter" and &"fighter" in state["owned"], "a new player owns and flies the Star Fighter")
	_check(state["tracks"].size() == 4 and state["tracks"][0]["unlocked"] and not state["tracks"][1]["unlocked"],
		"four space courses, the first one open")
	_check(state["equipped_car"] == &"starter" and state["equipped_boat"] == &"speedboat",
		"and still drives the Starter car and sails the Speedboat")
	m.profile.coins = 1000
	m.buy(&"pod")
	_check(m.profile.equipped_ship == &"pod" and m.profile.equipped_setup == &"starter"
		and m.profile.equipped_boat == &"speedboat", "buying a ship equips it as the ship, the car and boat stay")
	_check(m.profile.coins == 900, "ships are paid from the one wallet")
	m.select_track(&"space_02")
	_check(m.profile.selected_space == &"space_01", "a locked space course cannot be picked")
	m.profile.completed_tracks.append(&"space_01")
	m.select_track(&"space_02")
	_check(m.profile.selected_space == &"space_02" and m.profile.selected_track == &"track_01",
		"finishing Asteroid Alley opens Ring Road, and picking it leaves the car track alone")
	EventSystem.PRO_vehicle_kind_requested.emit(&"car")
	_check(state["setups"].all(func(s: DriftSetup) -> bool: return s.kind == &"car") and state["equipped"] == &"starter",
		"CARS switches back to the cars")
	EventSystem.PRO_state_changed.disconnect(listen)
	m.queue_free()
	var again := SaveGame.load_from(SAVE)
	_check(again.equipped_ship == &"pod" and &"pod" in again.owned_setups and again.selected_space == &"space_02",
		"the ship and the space course survive a save and load")


func _test_version_4_save_gets_a_ship() -> void:
	var file := ConfigFile.new()
	file.set_value("profile", "schema_version", 4)
	file.set_value("profile", "coins", 300)
	file.set_value("profile", "owned_setups", PackedStringArray(["starter", "speedboat", "jetski"]))
	file.set_value("profile", "equipped_boat", "jetski")
	file.save(SAVE)
	var profile := SaveGame.load_from(SAVE)
	_check(profile.coins == 300 and profile.equipped_boat == &"jetski", "a version 4 save keeps its boats and coins")
	_check(&"fighter" in profile.owned_setups and profile.equipped_ship == &"fighter"
		and profile.selected_space == &"space_01", "and comes in with the Star Fighter on Asteroid Alley")


func _test_ship_paint_and_cup_load() -> void:
	var missing: PackedStringArray = []
	for id in GarageManager.SHIP_SETUP_ORDER:
		var setup: DriftSetup = load("res://game/configs/ships/%s.tres" % id)
		for colour in Paint.COLOURS:
			if Paint.body(setup, colour) == null or Paint.card(setup, colour) == null:
				missing.append("%s %s" % [id, colour])
			elif colour != Paint.ORIGINAL and Paint.body(setup, colour) == setup.body \
					and not (colour == &"yellow" and setup.id in [&"pod", &"space_taxi"]):
				missing.append("%s %s (falls back)" % [id, colour])
	_check(missing.is_empty(), "every ship loads in every paint %s" % [missing])
	var cup: CupConfig = load("res://game/configs/cups/comet.tres")
	_check(cup.vehicle_kind == &"ship" and cup.tracks.size() == 4, "the Comet Cup is the four space courses")


## Finishing a race in a ship earns First Flight; winning the Comet Cup outright, its sticker.
func _test_stickers() -> void:
	var stickers := StickerManager.new()
	stickers.economy = ECONOMY
	add_child(stickers)
	var ship := _ship(&"fighter", Vector2.ZERO, 0.0)
	var marker := Node2D.new()
	marker.name = "PlayerMarker"
	ship.add_child(marker)
	await _frames(1)
	EventSystem.RAC_race_started.emit()
	EventSystem.RAC_race_finished.emit([{"is_player": true, "position": 3}], &"space_01")
	_check(stickers.has(&"first_flight") and not stickers.has(&"first_splash"), "a race finished in a ship earns First Flight")
	EventSystem.CUP_finished.emit(&"comet", [], &"silver")
	_check(not stickers.has(&"comet_cup"), "second in the Comet Cup does not earn its sticker")
	EventSystem.CUP_finished.emit(&"comet", [], &"gold")
	_check(stickers.has(&"comet_cup"), "winning the Comet Cup earns its sticker")
	stickers.queue_free()
	ship.queue_free()
	await _frames(1)

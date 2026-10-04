extends Node
## The assists' promise (docs/DESIGN.md §3.1): with AUTO GO and STEER HELP on, a child who
## presses nothing at all still gets round the track. Runs a real race on Track 01 with no
## input, answering the race's settings request like SettingsManager would, and compares
## with both assists off.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/assist_test.tscn
## Exit code 0 = all passed.

const RACE_SCENE := preload("res://game/screens/race.tscn")
const DRIVE_SECONDS := 75.0

var _failures: PackedStringArray = []
var _assists := false


func _enter_tree() -> void:
	EventSystem.PRO_state_requested.connect(func() -> void:
		EventSystem.PRO_state_changed.emit({"setups": [load("res://game/configs/setups/starter.tres")],
			"equipped": &"starter"}))
	EventSystem.UI_settings_requested.connect(func() -> void:
		EventSystem.UI_settings_changed.emit({"sound_volume": 0.0, "music_volume": 0.0, "fullscreen": false,
			"auto_accelerate": _assists, "steering_help": _assists, "difficulty": &"normal"}))


func _ready() -> void:
	print("both assists on, no input")
	_assists = true
	var helped := await _drive()
	_check(helped["laps"] >= 1, "completes laps on its own (%d in %ds)" % [helped["laps"], DRIVE_SECONDS])
	_check(helped["on_road"] > 0.9, "stays on the road %d%% of the time" % (helped["on_road"] * 100))
	_check(helped["wall_hits"] == 0, "never hits a wall (%d)" % helped["wall_hits"])
	_check(helped["position"] > 1, "but does not win with no input: assists help, they do not race (P%d)" % helped["position"])
	print("assists off, no input")
	_assists = false
	var unhelped := await _drive()
	_check(unhelped["distance"] < 100.0, "the car does not move by itself (%d px)" % unhelped["distance"])
	if _failures.is_empty():
		print("ALL ASSIST TESTS PASSED")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures.append(message)


func _drive() -> Dictionary:
	var race: Node2D = RACE_SCENE.instantiate()
	add_child(race)
	var player: Dictionary = race.racers.filter(func(r: Dictionary) -> bool: return r["is_player"])[0]
	var car: Car = player["car"]
	var hits := [0]
	var count_hit := func(hit: Node, _impact: float) -> void:
		if hit == car:
			hits[0] += 1
	EventSystem.CAR_wall_hit.connect(count_hit)
	var start := car.global_position
	var frames := 0
	var on_road := 0
	var t := 0.0
	while t < DRIVE_SECONDS:
		await get_tree().physics_frame
		t += 1.0 / 60.0
		if race.get_node("RaceManager").running:
			frames += 1
			if race.track.surface_at(car.global_position) == &"asphalt":
				on_road += 1
	var result := {"position": race.get_node("RaceManager").position_of(player), "laps": player["laps"], "on_road": float(on_road) / maxi(frames, 1),
		"wall_hits": hits[0], "distance": car.global_position.distance_to(start)}
	EventSystem.CAR_wall_hit.disconnect(count_hit)
	race.queue_free()
	await get_tree().physics_frame
	return result

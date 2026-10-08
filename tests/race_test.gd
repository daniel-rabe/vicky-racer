extends Node
## Headless race smoke test (plan verification step 4): a full race on Track 01 with the
## player's car on autopilot, checking the countdown, laps, positions and the finish.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/race_test.tscn -- --autopilot
## Exit code 0 = all passed. Prints every lap time, which doubles as an AI pace report.
## `--setup=<id>` races the player with that drift setup (default starter) and
## `--difficulty=<easy|normal|fast>` sets the opponents and `--track=<id>` the track
## (default track_01), for the balance pass:
## tools/dev/balance_report.py runs every setup at several paces.

const RACE_SCENE := preload("res://game/screens/race.tscn")
const TIMEOUT_SECONDS := 180.0

var _final_laps := 0
var _failures: PackedStringArray = []
var _ticks: Array[int] = []
var _started := false
var _laps := {}            # racer name -> lap times
var _bad_orders := 0
var _results: Array = []
var race: Node2D
var _last_progress := {}   # racer name -> progress last frame
var _jumps: PackedStringArray = []


func _enter_tree() -> void:
	EventSystem.RAC_countdown_tick.connect(func(n: int) -> void: _ticks.append(n))
	EventSystem.RAC_race_started.connect(func() -> void: _started = true)
	EventSystem.RAC_final_lap_started.connect(func() -> void: _final_laps += 1)
	EventSystem.RAC_lap_completed.connect(_on_lap)
	EventSystem.RAC_positions_updated.connect(_on_positions)
	EventSystem.RAC_race_finished.connect(func(results: Array, _id: StringName) -> void: _results = results)
	# The race asks the garage for the equipped setup; answer like GarageManager would.
	var setup_id := "starter"
	var difficulty := "normal"
	var track_id := "track_01"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--setup="):
			setup_id = arg.get_slice("=", 1)
		elif arg.begins_with("--difficulty="):
			difficulty = arg.get_slice("=", 1)
		elif arg.begins_with("--track="):
			track_id = arg.get_slice("=", 1)
	# Likewise the settings, like SettingsManager would; sound off, no assists.
	EventSystem.UI_settings_requested.connect(func() -> void:
		EventSystem.UI_settings_changed.emit({"sound_volume": 0.0, "music_volume": 0.0, "fullscreen": false,
			"auto_accelerate": false, "steering_help": false, "difficulty": StringName(difficulty)}))
	EventSystem.PRO_state_requested.connect(func() -> void:
		# A boat (docs/DESIGN.md §20) lives in configs/boats/ and a ship (§24) in configs/ships/;
		# race them on a boat or space course.
		var path := "res://game/configs/setups/%s.tres" % setup_id
		for dir in ["boats", "ships"]:
			if not ResourceLoader.exists(path):
				path = "res://game/configs/%s/%s.tres" % [dir, setup_id]
		EventSystem.PRO_state_changed.emit({"setups": [load(path)],
			"equipped": StringName(setup_id), "selected_track": StringName(track_id),
			"tracks": [{"config": load("res://game/configs/tracks/%s.tres" % track_id)}]}))


func _ready() -> void:
	if not Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--autopilot")):
		printerr("run with -- --autopilot, or the player's car never moves")
		get_tree().quit(2)
		return
	race = RACE_SCENE.instantiate()
	add_child(race)
	var start_progress := {}
	await get_tree().create_timer(5.0).timeout  # countdown + a moment of racing
	for r in race.racers:
		start_progress[r["name"]] = r["progress"]
	var waited := 5.0
	while _results.is_empty() and waited < TIMEOUT_SECONDS:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
	_report(start_progress)


## Progress must change smoothly: a jump means the ranking flickers (a lap counted while the
## car's centre is still short of the line reads as a whole lap ahead for a moment).
func _physics_process(_delta: float) -> void:
	if not race or not race.manager.running:
		return
	for r in race.racers:
		var last: float = _last_progress.get(r["name"], r["progress"])
		if absf(r["progress"] - last) > 200.0 and not r["finished"]:
			_jumps.append("%s %d -> %d" % [r["name"], last, r["progress"]])
		_last_progress[r["name"]] = r["progress"]


func _on_lap(car: Node, lap: int, lap_time: float) -> void:
	_laps.get_or_add(car.name, []).append(lap_time)
	print("  lap %d  %-7s %.2fs" % [lap, car.name, lap_time])


func _on_positions(order: Array) -> void:
	var positions := order.map(func(e: Dictionary) -> int: return e["position"])
	positions.sort()
	if positions != [1, 2, 3, 4]:
		_bad_orders += 1


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures.append(message)


func _report(start_progress: Dictionary) -> void:
	print("results")
	_check(_ticks == [3, 2, 1, 0] and _started, "countdown ran 3-2-1-GO, then the race started (%s)" % [_ticks])
	_check(not _results.is_empty(), "the race finished within %ds" % TIMEOUT_SECONDS)
	for r in race.racers:
		var moved: float = r["progress"] - start_progress.get(r["name"], 0.0)
		_check(moved > 5000.0, "%s made progress (%d px after the start)" % [r["name"], moved])
		var name: String = r["car"].name
		var laps: Array = _laps.get(name, [])
		if r["is_player"]:
			print("  player rescues %d" % r["driver"].rescues)
		else:
			# All but the last lap at least: the race ends with the player, before the slowest
			# finishes (a two-lap boat course leaves it one).
			var needed: int = maxi(1, mini(2, race.config.laps - 1))
			_check(laps.size() >= needed, "%s completed validated laps (%d)" % [name, laps.size()])
			# Sensible = an average speed between 250 and 2000 px/s, whatever the track's length.
			var length: float = race.track.lap_length()
			var ok_times := laps.all(func(t: float) -> bool: return t > length / 2000.0 and t < length / 250.0)
			_check(ok_times, "%s lap times are sensible (%s)" % [name, laps.map(func(t: float) -> String: return "%.1f" % t)])
			_check(r["driver"].rescues == 0, "%s never needed rescuing (%d)" % [name, r["driver"].rescues])
	_check(_final_laps == 1, "the player's last lap was announced once (%d)" % _final_laps)
	_check(_jumps.is_empty(), "progress never jumped (%s)" % [_jumps])
	_check(_bad_orders == 0, "positions were always a clean 1-4 (%d bad updates)" % _bad_orders)
	if not _results.is_empty():
		var positions := _results.map(func(e: Dictionary) -> int: return e["position"])
		var times := _results.map(func(e: Dictionary) -> float: return e["time"])
		var sorted_times := times.duplicate()
		sorted_times.sort()
		_check(positions == [1, 2, 3, 4] and times == sorted_times, "results are in finishing order (%s)" % [
			_results.map(func(e: Dictionary) -> String: return "%s %.1fs" % [e["name"], e["time"]])])
	if _failures.is_empty():
		print("ALL RACE TESTS PASSED")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)

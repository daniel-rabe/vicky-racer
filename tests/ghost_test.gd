extends Node
## Headless checks for time trials and ghosts (docs/DESIGN.md §16).
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/ghost_test.tscn -- --autopilot
## Part 1: GhostLap on its own — samples, the file round trip, broken files, replay timing.
## Part 2: a real time trial on Track 01 with the player's car on autopilot. The test records
## where the car really was on every tick of its best lap itself, and checks the ghost then
## drives exactly that lap, to within a pixel, tick by tick. Then the results, the record and
## the ghost file, and that both survive closing the game. Part 3: PICK A RACE's switch.
## Exit code 0 = all passed. With a window and `--screenshots=<dir>`, also saves the
## time-trial results and PICK A RACE in time-trial mode. (A ghost race is shot through the
## game itself: main.tscn -- --race-mode=time_trial --screen=race --autopilot=0.8 --screenshot=...)

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://ghost_test.cfg"
const SETTINGS := "user://ghost_test_settings.cfg"
const GHOST_DIR := "user://ghost_test_ghosts"

var _failures: PackedStringArray = []
var _shots_dir := ""
var _main: Node
## The test's own trace of the player's car: lap number -> PackedVector2Array, one per tick.
var _trace := {}
var _tracing_lap := 0
var _car: Car
var _ghost_errors: Array[float] = []
var _ghost_ticks := 0
var _race: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			_shots_dir = arg.get_slice("=", 1)
	process_physics_priority = 200  # after the cars, the recorder and the ghosts
	_wipe()
	_test_ghost_lap()
	await _start_game()
	await _test_time_trial()
	await _test_record_survives()
	await _test_pick_a_race()
	_main.queue_free()
	await get_tree().create_timer(0.5).timeout
	_wipe()
	if _failures.is_empty():
		print("ALL GHOST TESTS PASSED")
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
	for path in [SAVE, SAVE + ".bak", SETTINGS]:
		DirAccess.remove_absolute(path)
	for track in GarageManager.TRACK_ORDER:
		DirAccess.remove_absolute(GHOST_DIR.path_join("%s.ghost" % track))
	DirAccess.remove_absolute(GHOST_DIR)


func _test_ghost_lap() -> void:
	print("a ghost lap on its own")
	var lap := GhostLap.new()
	lap.track_id = &"track_01"
	lap.setup_id = &"starter"
	lap.lap_time = 2.0
	for i in 120:
		lap.add(Transform2D(i * 0.01, Vector2(i * 10.0, 5.0)), 2 if i > 60 else 0)
	_check(lap.frame_count() == 120 and lap.position_at_frame(30) == Vector2(300, 5), "one sample per tick")
	_check(lap.transform_at(31.0 / 60.0).origin.is_equal_approx(Vector2(300, 5)),
		"at its own tick rate, the replay lands on the samples")
	_check(lap.transform_at(31.5 / 60.0).origin.is_equal_approx(Vector2(305, 5)), "between ticks it blends")
	_check(lap.layer_at_frame(10) == 0 and lap.layer_at_frame(100) == 2, "it remembers the bridge layer")
	var path := GHOST_DIR.path_join("unit.ghost")
	_check(lap.save_file(path) == OK, "it saves")
	var back := GhostLap.load_file(path)
	_check(back != null and back.samples == lap.samples and back.layers == lap.layers and back.lap_time == 2.0,
		"and loads back the same")
	DirAccess.remove_absolute(path)
	_check(GhostLap.load_file(path) == null, "a missing file is no ghost")
	var junk := FileAccess.open(path, FileAccess.WRITE)
	junk.store_string("not a ghost")
	junk.close()
	_check(GhostLap.load_file(path) == null, "nor is a broken one")
	DirAccess.remove_absolute(path)
	_check(GhostLap.from_dict({"version": 1, "samples": PackedFloat32Array([1, 2])}) == null,
		"samples that are not whole ticks are refused")


func _start_game() -> void:
	var save := ConfigFile.new()
	save.set_value("profile", "schema_version", SaveGame.SCHEMA_VERSION)
	save.set_value("profile", "coins", 50)
	save.save(SAVE)
	_main = MAIN.instantiate()
	_main.get_node("GarageManager").save_path = SAVE
	_main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(_main)
	await get_tree().process_frame


func _physics_process(_delta: float) -> void:
	if _car and _tracing_lap > 0:
		_trace[_tracing_lap].append(_car.global_position)
	if _race and _race.own_ghost and _race.own_ghost.running and _race.own_ghost.ghost == _best_traced_ghost:
		var lap: int = _best_traced_lap
		var i: int = _race.own_ghost.tick - 1
		if i >= 0 and i < _trace[lap].size():
			_ghost_errors.append(_race.own_ghost.global_position.distance_to(_trace[lap][i]))
			_ghost_ticks += 1


var _best_traced_ghost: GhostLap
var _best_traced_lap := 0


func _test_time_trial() -> void:
	print("a time trial")
	if not Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--autopilot")):
		_check(false, "run with -- --autopilot, or the car never moves")
		return
	var garage: GarageManager = _main.get_node("GarageManager")
	EventSystem.PRO_track_select_requested.emit(&"track_01")
	EventSystem.PRO_race_mode_requested.emit(&"time_trial")
	EventSystem.UI_screen_requested.emit(&"race")
	await get_tree().process_frame
	_race = _main.get_node("ScreenSlot").get_child(-1)
	_check(_race.time_trial and _race.racers.size() == 1, "the player drives alone (%d cars)" % _race.racers.size())
	_check(not _race.hud.get_node("Root/PositionPanel").visible, "with no place on the HUD")
	_check(_race.developer_ghost != null and _race.developer_ghost.ghost.lap_time > 0.0, "against the gold ghost")
	_check(_race.developer_ghost.modulate.a < 1.0 and _race.developer_ghost.tint != _race.own_ghost.tint,
		"see-through, in gold, apart from the player's own")
	_check(_race.own_ghost.ghost == null, "and no ghost of their own yet")
	_car = _race.racers[0]["car"]
	_race.manager.lap_started.connect(func(_r: Dictionary) -> void:
		_tracing_lap += 1
		_trace[_tracing_lap] = PackedVector2Array())
	_race.recorder.new_best.connect(func(lap: GhostLap) -> void:
		_best_traced_ghost = lap
		_best_traced_lap = _tracing_lap)
	var coins := garage.profile.coins
	var waited := 0.0
	while waited < 200.0 and not (_main.get_node("ScreenSlot").get_child(-1).name == "ResultsScreen"):
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	_check(_ghost_ticks > 600, "the ghost of the best lap was driven again (%d ticks compared)" % _ghost_ticks)
	var worst := 0.0
	for e in _ghost_errors:
		worst = maxf(worst, e)
	_check(_ghost_ticks > 0 and worst < 1.0, "within a pixel of where the car really was, every tick (worst %.4f px)" % worst)
	var results: Node = _main.get_node("ScreenSlot").get_child(-1)
	_check(results.name == "ResultsScreen", "the time trial ends on the results")
	_check(garage.profile.coins == coins, "a time trial pays nothing")
	var race: Dictionary = garage.last_race
	_check(race.get("mode") == &"time_trial" and race["lap_times"].size() == 3, "three laps reported")
	var best: float = race["lap_times"].min()
	_check(race["new_record"] and is_equal_approx(garage.profile.trials[&"track_01"]["best"], best),
		"the first time trial sets the record (%.2f)" % best)
	_check(is_equal_approx(garage.profile.trials[&"track_01"]["cars"][&"starter"], best), "and the car's own best")
	_check(FileAccess.file_exists(GHOST_DIR.path_join("track_01.ghost")), "the record's ghost is saved")
	await get_tree().create_timer(2.5).timeout
	_check(results.get_node("%Headline").text == "NEW RECORD!", "NEW RECORD! (%s)" % results.get_node("%Headline").text)
	_check(results.get_node("%Again").text == "TRY AGAIN", "and TRY AGAIN")
	await _shot("time_trial_results")
	_race = null
	_car = null


func _test_record_survives() -> void:
	print("after closing the game")
	var record: float = _main.get_node("GarageManager").profile.trials[&"track_01"]["best"]
	_main.queue_free()
	await get_tree().process_frame
	await _start_game_keeping_save()
	var garage: GarageManager = _main.get_node("GarageManager")
	_check(is_equal_approx(float(garage.profile.trials.get(&"track_01", {}).get("best", 0.0)), record),
		"the record survives a save and load")
	var saved := GhostLap.load_file(GHOST_DIR.path_join("track_01.ghost"))
	_check(saved != null and saved.samples == _best_traced_ghost.samples, "and so does its ghost, sample for sample")
	EventSystem.PRO_track_select_requested.emit(&"track_01")
	EventSystem.PRO_race_mode_requested.emit(&"time_trial")
	EventSystem.UI_screen_requested.emit(&"race")
	await get_tree().process_frame
	var race: Node = _main.get_node("ScreenSlot").get_child(-1)
	_check(race.own_ghost.ghost != null and is_equal_approx(race.own_ghost.ghost.lap_time, record),
		"the next time trial races against it")
	EventSystem.UI_screen_requested.emit(&"tracks")
	await get_tree().process_frame


func _start_game_keeping_save() -> void:
	_main = MAIN.instantiate()
	_main.get_node("GarageManager").save_path = SAVE
	_main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(_main)
	await get_tree().process_frame


func _test_pick_a_race() -> void:
	print("pick a race")
	EventSystem.PRO_race_mode_requested.emit(&"race")
	EventSystem.UI_screen_requested.emit(&"tracks")
	await get_tree().create_timer(0.3).timeout
	var screen: Node = _main.get_node("ScreenSlot").get_child(-1)
	_check(screen.has_node("Modes/Race") and screen.has_node("Modes/TimeTrial"), "RACE and TIME TRIAL above the cards")
	_check(screen.get_node("%Cups").visible, "in RACE the cups are there")
	screen.get_node("Modes/TimeTrial").pressed.emit()
	await get_tree().process_frame
	_check(not screen.get_node("%Cups").visible, "in TIME TRIAL they make way")
	var card: TrackCard = screen.get_node("%Cards").get_child(0)
	_check(card.get_child(-1).text.begins_with("RECORD"), "and the cards show the record (%s)" % card.get_child(-1).text)
	await _shot("pick_a_race_time_trial")
	card.pressed.emit()
	await get_tree().process_frame
	var race: Node = _main.get_node("ScreenSlot").get_child(-1)
	_check(race.name == "Race" and race.time_trial, "choosing a track starts a time trial")
	EventSystem.UI_screen_requested.emit(&"tracks")
	await get_tree().process_frame
	EventSystem.CUP_start_requested.emit(&"sunshine")  # as a cup card does after asking for &"race"
	await get_tree().process_frame
	race = _main.get_node("ScreenSlot").get_child(-1)
	_check(race.name == "Race" and not race.time_trial, "a cup is always a race")
	EventSystem.UI_screen_requested.emit(&"title")
	await get_tree().process_frame


func _shot(shot_name: String) -> void:
	if _shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(shot_name + ".png"))

extends Node
## Headless checks for cups (docs/DESIGN.md §12).
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/cup_test.tscn -- --autopilot
## Part 1 drives CupManager with made-up race results: points, standings and ties, saving
## and resuming mid-cup, trophies and their coins, and the next cup opening only on a win.
## Part 2 plays a whole cup through the real screens, the player's car on autopilot.
## Exit code 0 = all passed. Uses its own save and settings files. With a window and
## `-- --autopilot --screenshots=<dir>`, also saves the pick-a-race, standings and podium.

const MAIN := preload("res://game/main.tscn")
const ECONOMY := preload("res://game/configs/economy.tres")
const SAVE := "user://cup_test.cfg"
const SETTINGS := "user://cup_test_settings.cfg"

var _failures: PackedStringArray = []
var _garage: GarageManager
var _cups: CupManager
var _shots_dir := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			_shots_dir = arg.get_slice("=", 1)
	_wipe()
	_test_points_and_resume()
	_test_trophies_and_unlocking()
	_test_ties_and_single_races()
	_drop()
	_wipe()
	await _test_whole_cup_on_screen()
	_wipe()
	if _failures.is_empty():
		print("ALL CUP TESTS PASSED")
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


## A fresh GarageManager and CupManager on the test save, as the game shell has them.
func _managers() -> void:
	_drop()
	_garage = GarageManager.new()
	_garage.economy = ECONOMY
	_garage.save_path = SAVE
	add_child(_garage)
	_cups = CupManager.new()
	add_child(_cups)


func _drop() -> void:
	for node in [_cups, _garage]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()


## A race result in this finishing order (names), as RaceManager reports it.
func _finish(order: Array, track_id := &"track_01") -> void:
	var results := []
	for i in order.size():
		results.append({"name": order[i], "body": "res://art/cars/car_red.png", "is_player": order[i] == "YOU",
			"position": i + 1, "time": 60.0 + i, "best_lap": 20.0})
	EventSystem.RAC_race_finished.emit(results, track_id)


func _points(name: String) -> int:
	return _cups.points.get(name, -1)


func _test_points_and_resume() -> void:
	print("points, standings and resuming")
	_managers()
	_check(_cups.is_unlocked(&"sunshine") and not _cups.is_unlocked(&"snowflake"),
		"a new save has the Sunshine Cup open and the Snowflake Cup locked")
	_cups.start(&"sunshine")
	_check(_cups.phase == &"racing" and _cups.current_track().track_id == &"track_01", "a cup starts on its first track")
	_finish(["BLUE", "YOU", "YELLOW", "GREEN"])
	_check(_points("BLUE") == 10 and _points("YOU") == 7 and _points("YELLOW") == 5 and _points("GREEN") == 3,
		"points are 10 / 7 / 5 / 3 — everyone scores")
	_check(_cups.phase == &"results" and _cups.race_index == 1, "after race 1 of 3 the standings are next")
	_check(_garage.profile.cup_progress.get("race") == 1, "progress is saved after the race")
	_managers()  # as if the game was closed and opened again
	_check(_cups.phase == &"ready" and _cups.cup.id == &"sunshine" and _cups.race_index == 1 and _points("YOU") == 7,
		"a cup survives closing the game, with its points (race %d, %d pts)" % [_cups.race_index, _points("YOU")])
	_cups.continue_cup()
	_check(_cups.phase == &"racing" and _cups.current_track().track_id == &"track_02", "continuing goes to the next track")
	_finish(["GREEN", "YELLOW", "BLUE", "YOU"])
	_cups.continue_cup()
	var coins := _garage.profile.coins
	_finish(["YOU", "BLUE", "GREEN", "YELLOW"])
	var table := _cups.standings()
	var names := table.map(func(r: Dictionary) -> String: return r["name"])
	_check(names == ["BLUE", "YOU", "GREEN", "YELLOW"], "final standings by points (%s)" % [names])
	_check(_cups.phase == &"done" and _cups.trophy == &"silver", "2nd overall wins the silver trophy")
	_check(_garage.profile.trophies.get(&"sunshine") == &"silver", "the trophy is saved")
	_check(_garage.profile.coins == coins + 100 + int(ECONOMY.cup_bonus[&"silver"]),
		"the last race pays as usual, plus the silver bonus (%d)" % (_garage.profile.coins - coins))
	_check(_garage.profile.cup_progress.is_empty(), "a finished cup leaves nothing to resume")
	_check(not _cups.is_unlocked(&"snowflake"), "silver does not open the next cup — only a win does")


func _test_trophies_and_unlocking() -> void:
	print("winning opens the next cup")
	_managers()
	_cups.start(&"sunshine")
	for i in 3:
		_finish(["YOU", "BLUE", "YELLOW", "GREEN"])
		_cups.continue_cup()
	_check(_cups.trophy == &"gold" and _garage.profile.trophies.get(&"sunshine") == &"gold", "winning every race: gold")
	_check(_cups.is_unlocked(&"snowflake"), "winning the Sunshine Cup opens the Snowflake Cup")
	EventSystem.UI_screen_requested.emit(&"garage")
	_check(_cups.phase == &"none", "leaving the podium ends the cup")
	_cups.start(&"sunshine")
	for i in 3:
		_finish(["BLUE", "YELLOW", "GREEN", "YOU"])
		_cups.continue_cup()
	_check(_cups.trophy == &"ribbon", "last overall still gets a prize: the ribbon")
	_check(_garage.profile.trophies.get(&"sunshine") == &"gold" and _cups.is_unlocked(&"snowflake"),
		"a worse result never takes away the gold, or the open cup")
	_managers()
	_check(_cups.is_unlocked(&"snowflake"), "the open cup survives a save and load")
	_check(not _cups.is_unlocked(&"starlight"), "the Starlight Cup waits for a Snowflake win")
	_cups.start(&"snowflake")
	for i in 3:
		_finish(["YOU", "BLUE", "YELLOW", "GREEN"], _cups.current_track().track_id)
		_cups.continue_cup()
	_check(_cups.is_unlocked(&"starlight"), "winning the Snowflake Cup opens the Starlight Cup")
	EventSystem.UI_screen_requested.emit(&"garage")


func _test_ties_and_single_races() -> void:
	print("ties and single races")
	_managers()
	_cups.start(&"sunshine")
	_cups.points = {"YOU": 12, "BLUE": 12, "YELLOW": 5, "GREEN": 3}
	_cups.last_positions = {"YOU": 1, "BLUE": 2, "YELLOW": 3, "GREEN": 4}
	_check(_cups.standings()[0]["name"] == "YOU", "a tie goes to whoever did better in the last race")
	_cups.points.clear()
	EventSystem.UI_screen_requested.emit(&"garage")  # left the race: the cup waits
	_finish(["YOU", "BLUE", "YELLOW", "GREEN"])
	_check(_cups.points.is_empty() and _cups.race_index == 0, "a single race does not count for a waiting cup")


## The real thing: start a cup, race, results -> standings -> next race ... -> podium.
func _test_whole_cup_on_screen() -> void:
	print("a whole cup on screen")
	_drop()
	var main := MAIN.instantiate()
	main.get_node("GarageManager").save_path = SAVE
	main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(main)
	await get_tree().process_frame
	EventSystem.CUP_start_requested.emit(&"sunshine")
	var tracks := []
	for race in 3:
		var screen := await _wait_for_screen(main, "Race", 10.0)
		if screen == null:
			_check(false, "race %d starts" % (race + 1))
			break
		tracks.append(String(screen.config.track_id))
		var results := await _wait_for_screen(main, "ResultsScreen", 200.0)
		_check(results != null, "race %d finishes (%s)" % [race + 1, tracks[-1]])
		if results == null:
			break
		await get_tree().create_timer(3.0).timeout  # the payout count-up
		_check(results.get_node("%Again").text == "STANDINGS", "the results lead to the standings")
		results.get_node("%Again").pressed.emit()
		var standings := await _wait_for_screen(main, "Standings", 5.0)
		_check(standings != null and standings.get_node("%Rows").get_child_count() == 4, "the standings show four racers")
		if race == 1:
			await get_tree().create_timer(1.5).timeout
			await _shot("cup_standings")
		var next: Button = standings.get_node("%Next")
		_check(next.text == ("PODIUM!" if race == 2 else "NEXT RACE"), "and lead on (%s)" % next.text)
		next.pressed.emit()
	_check(tracks == ["track_01", "track_02", "track_04"], "the cup runs its three tracks in order (%s)" % [tracks])
	var podium := await _wait_for_screen(main, "Podium", 5.0)
	_check(podium != null, "the cup ends on the podium")
	if podium:
		await get_tree().create_timer(4.0).timeout
		await _shot("cup_podium")
		_check(not podium.get_node("%Garage").disabled, "the podium leads back to the garage")
	var garage: GarageManager = main.get_node("GarageManager")
	_check(garage.profile.trophies.has(&"sunshine"), "a trophy was won (%s)" % garage.profile.trophies.get(&"sunshine"))
	EventSystem.UI_screen_requested.emit(&"tracks")
	await get_tree().create_timer(0.5).timeout
	await _shot("pick_a_race")
	main.queue_free()
	await get_tree().create_timer(0.5).timeout  # let audio mix once before quitting (see main.gd)


func _shot(shot_name: String) -> void:
	if _shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(shot_name + ".png"))


func _wait_for_screen(main: Node, screen_name: String, seconds: float) -> Node:
	var waited := 0.0
	while waited < seconds:
		for child in main.get_node("ScreenSlot").get_children():
			if child.name == screen_name and not child.is_queued_for_deletion():
				return child
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	return null

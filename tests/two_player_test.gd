extends Node
## Headless checks for two players on one screen (docs/DESIGN.md §15).
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/two_player_test.tscn -- --autopilot
## Part 1: joining — devices, per-player actions bound to one device each, nobody joining
## twice, the title ending the game. Part 2: the join screen driven by key and gamepad
## events. Part 3: a whole split-screen race with both players on autopilot — two views, a
## HUD each with its own player's position, one minimap, both players in the results and
## both paid into the one garage; and a race with no opponents. Exit code 0 = all passed.
## With a window and `--screenshots=<dir>`, also saves the join screen and the split race,
## and prints the frame rate of the race.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://two_player_test.cfg"
const SETTINGS := "user://two_player_test_settings.cfg"
const ECONOMY := preload("res://game/configs/economy.tres")

var _failures: PackedStringArray = []
var _shots_dir := ""
var _main: Node
var _party := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			_shots_dir = arg.get_slice("=", 1)
	EventSystem.PLY_state_changed.connect(func(state: Dictionary) -> void: _party = state)
	_wipe()
	var save := ConfigFile.new()  # two cars owned, so the players can pick different ones
	save.set_value("profile", "schema_version", SaveGame.SCHEMA_VERSION)
	save.set_value("profile", "owned_setups", PackedStringArray(["starter", "grippy", "kart"]))
	save.set_value("profile", "equipped_setup", "starter")
	save.save(SAVE)
	_main = MAIN.instantiate()
	_main.get_node("GarageManager").save_path = SAVE
	_main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(_main)
	await get_tree().process_frame
	await _test_joining()
	await _test_join_screen()
	await _test_split_race()
	await _test_no_opponents()
	_main.queue_free()
	await get_tree().create_timer(0.5).timeout
	_wipe()
	if _failures.is_empty():
		print("ALL TWO PLAYER TESTS PASSED")
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


func _key(code: Key, pressed := true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)


func _pad_button(pad: int, button: JoyButton, pressed := true) -> void:
	var event := InputEventJoypadButton.new()
	event.device = pad
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)


func _tap_key(code: Key) -> void:
	_key(code)
	await get_tree().process_frame
	_key(code, false)
	await get_tree().process_frame


func _tap_pad(pad: int, button: JoyButton) -> void:
	_pad_button(pad, button)
	await get_tree().process_frame
	_pad_button(pad, button, false)
	await get_tree().process_frame


func _test_joining() -> void:
	print("joining")
	var players: PlayersManager = _main.get_node("PlayersManager")
	EventSystem.PLY_join_requested.emit({"kind": &"keys_left"}, &"starter")
	_check(players.players.is_empty(), "nobody joins outside a two-player game")
	EventSystem.PLY_two_player_requested.emit()
	EventSystem.PLY_join_requested.emit({"kind": &"keys_left"}, &"starter")
	EventSystem.PLY_join_requested.emit({"kind": &"keys_left"}, &"grippy")
	_check(players.players.size() == 1, "a device joins once")
	EventSystem.PLY_join_requested.emit({"kind": &"pad", "pad": 1}, &"grippy")
	EventSystem.PLY_join_requested.emit({"kind": &"keys_right"}, &"kart")
	_check(players.players.size() == 2, "two players, and a third is turned away")
	_check(_party["two_player"] and _party["players"][1]["setup"] == &"grippy", "the state reaches screens")
	_key(KEY_W)
	await get_tree().process_frame  # parsed events reach the actions on the next frame
	_check(Input.is_action_pressed(&"p1_accelerate") and not Input.is_action_pressed(&"p2_accelerate"),
		"W drives player 1 only")
	_key(KEY_W, false)
	_pad_button(1, JOY_BUTTON_A)
	await get_tree().process_frame
	_check(Input.is_action_pressed(&"p2_accelerate") and not Input.is_action_pressed(&"p1_accelerate"),
		"gamepad 2's A drives player 2 only")
	_pad_button(1, JOY_BUTTON_A, false)
	_pad_button(0, JOY_BUTTON_A)
	await get_tree().process_frame
	_check(not Input.is_action_pressed(&"p2_accelerate"), "gamepad 1 does not drive player 2")
	_pad_button(0, JOY_BUTTON_A, false)
	await get_tree().process_frame
	EventSystem.UI_screen_requested.emit(&"title")
	_check(not players.two_player and players.players.is_empty() and not InputMap.has_action(&"p1_accelerate"),
		"the title ends the two-player game and its actions")


func _test_join_screen() -> void:
	print("the join screen")
	await get_tree().create_timer(0.3).timeout
	var title := _screen()
	title.get_node("%TwoPlayers").pressed.emit()
	await get_tree().create_timer(0.3).timeout
	var join := _screen()
	_check(join.name == "JoinScreen", "2 PLAYERS opens the join screen")
	await _tap_key(KEY_SPACE)
	_check(_party["players"].size() == 1 and _party["players"][0]["device"]["kind"] == &"keys_left",
		"SPACE joins player 1 on W A S D")
	_check(_party["players"][0]["setup"] == &"starter", "in the equipped car")
	await _tap_pad(0, JOY_BUTTON_A)
	_check(_party["players"].size() == 2 and _party["players"][1]["device"].get("pad") == 0,
		"A on a gamepad joins player 2")
	_check(_party["players"][1]["setup"] != _party["players"][0]["setup"], "in a different car (%s)" % _party["players"][1]["setup"])
	var before: StringName = _party["players"][0]["setup"]
	await _tap_key(KEY_D)
	_check(_party["players"][0]["setup"] != before, "D picks player 1's next car (%s)" % _party["players"][0]["setup"])
	await _tap_key(KEY_A)
	_check(_party["players"][0]["setup"] == before, "A picks it back")
	await _tap_pad(0, JOY_BUTTON_Y)
	_check(not _party["opponents"], "Y switches the opponents off")
	await _tap_key(KEY_O)
	_check(_party["opponents"], "O switches them back on")
	await _shot("join")
	await _tap_pad(0, JOY_BUTTON_A)
	await get_tree().create_timer(0.3).timeout
	var tracks := _screen()
	_check(tracks.name == "TrackSelect" or tracks.name.begins_with("Track"), "a joined player's button goes on to pick a race (%s)" % tracks.name)
	_check(not tracks.get_node("%Cups").visible, "no cups for two players")


func _test_split_race() -> void:
	print("a split-screen race")
	if not Array(OS.get_cmdline_user_args()).has("--autopilot"):
		_check(false, "run with -- --autopilot, or the cars never move")
		return
	var garage: GarageManager = _main.get_node("GarageManager")
	var coins := garage.profile.coins
	EventSystem.PRO_track_select_requested.emit(&"track_01")
	EventSystem.UI_screen_requested.emit(&"race")
	await get_tree().create_timer(0.5).timeout
	var race := _screen()
	_check(race.views.size() == 2, "the screen is split in two views")
	var humans: Array = race.racers.filter(func(r: Dictionary) -> bool: return r["is_player"])
	_check(race.racers.size() == 4 and humans.size() == 2, "two players and two opponents (%d cars)" % race.racers.size())
	_check(humans.map(func(r: Dictionary) -> String: return r["name"]) == ["P1", "P2"] \
			or humans.map(func(r: Dictionary) -> String: return r["name"]) == ["P2", "P1"], "named P1 and P2")
	var p2: Dictionary = humans.filter(func(r: Dictionary) -> bool: return r["player"] == 2)[0]
	var p1: Dictionary = humans.filter(func(r: Dictionary) -> bool: return r["player"] == 1)[0]
	_check(p1["car"].setup.id != p2["car"].setup.id, "each in their own car")
	_check(p2["car"].get_node("ChaseCamera/Camera").custom_viewport == race.views[1], "player 2's camera draws the right half")
	_check(race.views[1].world_2d == race.views[0].world_2d, "both halves show the same world")
	var hud1: CanvasLayer = race.views[0].get_node("RaceHUD")
	var hud2: CanvasLayer = race.views[1].get_node("RaceHUD2")
	_check(hud1 != null and hud2 != null, "a HUD in each half")
	_check(race.has_node("SharedMinimap"), "one minimap between them")
	var frames := 0
	var seconds := 0.0
	var shot_taken := false
	var results: Node = null
	var checked_positions := false
	while seconds < 240.0:
		await get_tree().process_frame
		var dt := get_process_delta_time()
		seconds += dt
		frames += 1
		if not checked_positions and seconds > 20.0 and race.manager.running:
			checked_positions = true
			var want1: int = race.manager.position_of(p1)
			var want2: int = race.manager.position_of(p2)
			_check(hud1.get_node("%Position").text == str(want1) and hud2.get_node("%Position").text == str(want2),
				"each HUD shows its own player's place (P1 %s/%d, P2 %s/%d)" % [hud1.get_node("%Position").text, want1,
				hud2.get_node("%Position").text, want2])
		if not shot_taken and seconds > 12.0:
			shot_taken = true
			await _shot("split_screen")
		if _screen() and _screen().name == "ResultsScreen":
			results = _screen()
			break
	if DisplayServer.get_name() != "headless":
		print("  race frame rate: %.1f fps average over %d frames" % [frames / maxf(seconds, 0.001), frames])
	_check(results != null, "the race finishes when both players have")
	var race_result: Dictionary = garage.last_race
	var players: Array = race_result.get("results", []).filter(func(e: Dictionary) -> bool: return e["is_player"])
	_check(players.size() == 2, "both players are in the results")
	var expected := 0
	for e: Dictionary in players:
		expected += ECONOMY.place_payouts[int(e["position"]) - 1]
	_check(race_result["breakdown"].has("place_p1") and race_result["breakdown"].has("place_p2"),
		"each player's place is paid on its own line")
	_check(garage.profile.coins == coins + expected + ECONOMY.first_finish_bonus,
		"both are paid into the one garage, and the new track's bonus once (+%d)" % (garage.profile.coins - coins))
	await get_tree().create_timer(3.0).timeout
	var headline: String = results.get_node("%Headline").text
	_check(headline.begins_with("P1") or headline.begins_with("P2"), "the headline names the better player (%s)" % headline)


func _test_no_opponents() -> void:
	print("no opponents")
	EventSystem.PLY_opponents_requested.emit(false)
	EventSystem.UI_screen_requested.emit(&"race")
	await get_tree().create_timer(0.5).timeout
	var race := _screen()
	_check(race.racers.size() == 2 and race.racers.all(func(r: Dictionary) -> bool: return r["is_player"]),
		"with opponents off only the two players race (%d cars)" % race.racers.size())
	EventSystem.UI_screen_requested.emit(&"title")
	await get_tree().create_timer(0.3).timeout
	_check(not _party["two_player"], "back at the title, it is a one-player game again")


func _screen() -> Node:
	for child in _main.get_node("ScreenSlot").get_children():
		if not child.is_queued_for_deletion():
			return child
	return null


func _shot(shot_name: String) -> void:
	if _shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(shot_name + ".png"))

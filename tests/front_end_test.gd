extends Node
## Headless checks for Phase 9 (docs/DESIGN.md §10): the title screen comes first, settings
## apply, save and load defensively, the pause menu freezes and resumes the race and can
## only leave it through "SURE?", auto accelerate drives the car, and the difficulty
## reaches the opponents.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/front_end_test.tscn
## Exit code 0 = all passed. Uses its own save and settings files, deleted afterwards.
## Run with a window and `-- --screenshots=<dir>` to also save each screen as it is tested.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://front_end_test.cfg"
const SETTINGS := "user://front_end_test_settings.cfg"

var _failures: PackedStringArray = []
var _main: Node
var _shots_dir := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			_shots_dir = arg.get_slice("=", 1)
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_test_settings_file()
	_main = MAIN.instantiate()
	_main.get_node("GarageManager").save_path = SAVE
	_main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(_main)
	await _frames(5)
	await _test_title_first()
	await _test_settings_apply()
	await _test_pause()
	await _test_auto_accelerate_and_difficulty()
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	if not _shots_dir.is_empty():
		# With a window, sounds are playing: free the game and let audio mix once before
		# quitting, or the still-playing loops are reported as leaked (see main.gd).
		_main.queue_free()
		await get_tree().create_timer(0.5).timeout
	if _failures.is_empty():
		print("ALL FRONT END TESTS PASSED")
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


func _shot(shot_name: String) -> void:
	if _shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(shot_name + ".png"))


func _screen() -> Node:
	var slot := _main.get_node("ScreenSlot")
	for child in slot.get_children():
		if not child.is_queued_for_deletion():
			return child
	return null


func _press(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	await _frames(2)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	await _frames(2)


func _test_settings_file() -> void:
	print("settings file")
	var fresh := Settings.load_from(SETTINGS)
	_check(fresh.difficulty == &"normal" and not fresh.auto_accelerate, "no file gives the defaults")
	var file := FileAccess.open(SETTINGS, FileAccess.WRITE)
	file.store_string("this is [not a config file")
	file.close()
	_check(Settings.load_from(SETTINGS).sound_volume == Settings.new().sound_volume, "an unreadable file gives the defaults")
	var bad := ConfigFile.new()
	bad.set_value("settings", "sound_volume", 7.5)
	bad.set_value("settings", "difficulty", "impossible")
	bad.set_value("settings", "fullscreen", "yes please")
	bad.set_value("settings", "steering_help", true)
	bad.save(SETTINGS)
	var loaded := Settings.load_from(SETTINGS)
	_check(loaded.sound_volume == 1.0, "volume is clamped to 0-1 (%.2f)" % loaded.sound_volume)
	_check(loaded.difficulty == &"normal" and not loaded.fullscreen, "unknown or mistyped values are ignored")
	_check(loaded.steering_help, "valid values are kept")
	DirAccess.remove_absolute(SETTINGS)


func _test_title_first() -> void:
	print("title screen")
	var title := _screen()
	_check(title != null and title.name == "TitleScreen", "the game opens on the title screen (%s)" % [title.name if title else "nothing"])
	_check(get_viewport().gui_get_focus_owner() == title.get_node("%Play"), "PLAY has focus")
	var cars := get_tree().get_nodes_in_group(&"cars")
	var start: Vector2 = cars[0].global_position if cars.size() > 0 else Vector2.ZERO
	await get_tree().create_timer(2.0).timeout
	_check(cars.size() == 4 and cars[0].global_position.distance_to(start) > 200.0,
		"four cars race behind the menu (%d cars)" % cars.size())
	await _shot("title")


func _test_settings_apply() -> void:
	print("settings apply and save")
	var title := _screen()
	title.get_node("%Settings").pressed.emit()
	await _frames(2)
	var panel: SettingsPanel = title.get_node("%SettingsPanel")
	_check(panel.visible, "SETTINGS opens the panel")
	var sound: SettingsRow = panel.get_node("%Rows").get_child(0)
	_check(get_viewport().gui_get_focus_owner() == sound, "the SOUND row has focus")
	sound.stepped.emit(&"sound_volume", -1)
	sound.stepped.emit(&"sound_volume", -1)
	await _frames(2)
	var manager: SettingsManager = _main.get_node("SettingsManager")
	_check(is_equal_approx(manager.settings.sound_volume, 0.6), "two steps left: volume 0.8 -> 0.6 (%.2f)" % manager.settings.sound_volume)
	var bus_db := AudioServer.get_bus_volume_db(AudioServer.get_bus_index(&"SFX"))
	_check(is_equal_approx(bus_db, linear_to_db(0.6)), "the SFX bus follows (%.1f dB)" % bus_db)
	var choice: SettingsRow = panel.get_node("%Rows").get_child(4)
	choice.stepped.emit(&"difficulty", -1)
	await _frames(2)
	_check(manager.settings.difficulty == &"easy", "OPPONENTS steps NORMAL -> EASY")
	choice.stepped.emit(&"difficulty", -1)
	await _frames(2)
	_check(manager.settings.difficulty == &"fast", "and wraps round to FAST")
	choice.stepped.emit(&"difficulty", 1)
	await _frames(2)
	await _shot("settings")
	_check(Settings.load_from(SETTINGS).difficulty == &"easy" and is_equal_approx(Settings.load_from(SETTINGS).sound_volume, 0.6),
		"every change is saved straight away")
	await _press(&"ui_cancel")
	_check(not panel.visible and title.get_node("%Menu").visible, "B / Escape closes the panel")


func _test_pause() -> void:
	print("pause menu")
	EventSystem.UI_screen_requested.emit(&"race")
	await _frames(5)
	var race := _screen()
	var pause_menu: CanvasLayer = race.get_node("PauseMenu")
	await get_tree().create_timer(3.5).timeout  # through the countdown
	var manager: RaceManager = race.get_node("RaceManager")
	await _press(&"pause")
	_check(get_tree().paused and pause_menu.visible, "pause freezes the race and shows the menu")
	_check(get_viewport().gui_get_focus_owner() == pause_menu.get_node("%Resume"), "RESUME has focus")
	await _shot("pause")
	var time := manager.race_time
	var positions: Array = race.racers.map(func(r: Dictionary) -> Vector2: return r["car"].global_position)
	await _frames(30)
	var still: Array = race.racers.map(func(r: Dictionary) -> Vector2: return r["car"].global_position)
	_check(manager.race_time == time and positions == still, "while paused, cars and the clock stand still")
	await _press(&"pause")
	_check(not get_tree().paused and not pause_menu.visible, "pressing pause again resumes")
	await _frames(30)
	_check(manager.race_time > time, "the clock runs again")
	await _press(&"pause")
	pause_menu.get_node("%Garage").pressed.emit()
	await _frames(2)
	_check(pause_menu.get_node("%Confirm").visible and get_viewport().gui_get_focus_owner() == pause_menu.get_node("%No"),
		"GARAGE asks SURE? with NO focused")
	await _shot("pause_confirm")
	await _press(&"ui_cancel")
	_check(not pause_menu.get_node("%Confirm").visible and _screen() == race, "B backs out of SURE? and stays in the race")
	pause_menu.get_node("%Garage").pressed.emit()
	await _frames(2)
	pause_menu.get_node("%Yes").pressed.emit()
	await _frames(5)
	_check(_screen().name == "GarageScreen" and not get_tree().paused, "YES goes to the garage, unpaused")


func _test_auto_accelerate_and_difficulty() -> void:
	print("auto accelerate and difficulty")
	EventSystem.UI_setting_change_requested.emit(&"auto_accelerate", true)
	EventSystem.UI_screen_requested.emit(&"race")
	await _frames(5)
	var race := _screen()
	var player: Dictionary = race.racers.filter(func(r: Dictionary) -> bool: return r["is_player"])[0]
	var blue: Dictionary = race.racers.filter(func(r: Dictionary) -> bool: return r["name"] == "BLUE")[0]
	var easy := DifficultyConfig.named(&"easy")
	_check(is_equal_approx(blue["driver"].skill, 0.85 + easy.skill_offset), "EASY lowers the opponents' skill (Blue %.2f)" % blue["driver"].skill)
	_check(race.get_node("RaceManager").difficulty.id == &"easy", "and the race uses EASY's rubber band")
	await get_tree().create_timer(5.0).timeout
	var speed: float = player["car"].velocity.length()
	_check(speed > 500.0, "with AUTO GO the player's car drives with no keys pressed (%d px/s)" % speed)
	EventSystem.UI_setting_change_requested.emit(&"auto_accelerate", false)
	await get_tree().create_timer(3.0).timeout
	_check(player["car"].velocity.length() < speed * 0.5, "switched off mid-race, it coasts to a stop")

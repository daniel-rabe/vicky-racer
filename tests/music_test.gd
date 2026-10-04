extends Node
## Headless checks for the music (docs/DESIGN.md §13).
##   Godot_console.exe --path . --headless res://tests/music_test.tscn
## Every piece is built and loops past its lead-in; every track theme has race music; each
## screen picks its piece and a shared piece is not restarted; the countdown ducks, the last
## lap speeds up, the finish fades out; MUSIC sets the Music bus. Headless (dummy driver)
## nothing may play; run it with a window and the playing music is checked as well.
## Exit code 0 = all passed. Uses its own save and settings files.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://music_test.cfg"
const SETTINGS := "user://music_test_settings.cfg"
const THEMES := ["meadow", "beach", "snow", "town"]

var _failures: PackedStringArray = []


func _ready() -> void:
	_wipe()
	_test_pieces()
	await _test_screens()
	_wipe()
	if _failures.is_empty():
		print("ALL MUSIC TESTS PASSED")
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


func _test_pieces() -> void:
	print("the pieces")
	for path in DirAccess.get_files_at("res://game/configs/music"):
		if not path.ends_with(".tres"):
			continue
		var piece: MusicPiece = load("res://game/configs/music/" + path)
		var length := piece.stream.get_length() if piece.stream else 0.0
		_check(piece.stream is AudioStreamOggVorbis and length > 1.0, "%s: an Ogg stream (%.1fs)" % [piece.id, length])
		if piece.loops:
			var loop_seconds := length - piece.loop_offset
			var bars := loop_seconds * piece.bpm / 240.0
			_check(piece.loop_offset >= 0.0 and loop_seconds > 10.0, "%s: loops from %.2fs, a %.1fs loop" % [piece.id, piece.loop_offset, loop_seconds])
			_check(absf(bars - roundf(bars)) < 0.02, "%s: the loop is whole bars (%.2f)" % [piece.id, bars])
	for id in THEMES:
		var theme: TrackTheme = load("res://game/configs/themes/%s.tres" % id)
		_check(theme.music != null and theme.music.loops, "%s has race music (%s)" % [id, theme.music.id if theme.music else "none"])
	var ids := {}
	for id in THEMES:
		ids[load("res://game/configs/themes/%s.tres" % id).music] = true
	_check(ids.size() == THEMES.size(), "every theme has its own race music")


func _test_screens() -> void:
	print("screens, countdown, last lap, finish")
	var main := MAIN.instantiate()
	main.get_node("GarageManager").save_path = SAVE
	main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(main)
	await get_tree().process_frame
	var music: MusicManager = main.get_node("MusicManager")
	_check(music.current == MusicManager.MENU, "the title plays the menu theme")
	var player := music._player
	for screen in [&"garage", &"tracks"]:
		EventSystem.UI_screen_requested.emit(screen)
		await get_tree().process_frame
		_check(music.current == MusicManager.MENU and music._player == player, "%s carries on with the same menu theme" % screen)
	EventSystem.UI_screen_requested.emit(&"race")
	await get_tree().process_frame
	var meadow: TrackTheme = load("res://game/configs/themes/meadow.tres")
	_check(music.current == meadow.music, "the race plays its track's music (%s)" % (music.current.id if music.current else "none"))
	_check(is_equal_approx(music._duck_db, MusicManager.DUCK_DB), "the countdown ducks it (%.1f dB)" % music._duck_db)
	await get_tree().create_timer(4.2).timeout
	_check(is_zero_approx(music._duck_db), "and GO brings it back (%.1f dB)" % music._duck_db)
	EventSystem.RAC_final_lap_started.emit()
	_check(music.final_lap, "the last lap is noticed")
	EventSystem.RAC_countdown_tick.emit(3)
	_check(not music.final_lap, "a restarted race's countdown sets it back")
	EventSystem.RAC_countdown_tick.emit(0)
	EventSystem.RAC_race_finished.emit([], &"track_01")
	_check(music.current == null and not music.final_lap, "the finish fades it out for the fanfare")
	for pair in [[&"results", MusicManager.MENU], [&"standings", MusicManager.STANDINGS], [&"podium", MusicManager.PODIUM]]:
		EventSystem.UI_screen_requested.emit(pair[0])
		await get_tree().process_frame
		_check(music.current == pair[1], "%s plays %s" % [pair[0], pair[1].id])
	if SoundManager.audible():
		_check(music._player != null and music._player.playing and music._player.bus == &"Music", "the podium music is playing on the Music bus")
	else:
		_check(music.get_child_count() == 0, "headless: nothing plays (%d players)" % music.get_child_count())
	print("the MUSIC setting")
	var bus := AudioServer.get_bus_index(&"Music")
	EventSystem.UI_setting_change_requested.emit(&"music_volume", 0.5)
	_check(is_equal_approx(AudioServer.get_bus_volume_db(bus), linear_to_db(0.5)) and not AudioServer.is_bus_mute(bus),
		"MUSIC 0.5 sets the Music bus (%.1f dB)" % AudioServer.get_bus_volume_db(bus))
	EventSystem.UI_setting_change_requested.emit(&"music_volume", 0.0)
	_check(AudioServer.is_bus_mute(bus), "MUSIC 0 mutes it")
	_check(is_zero_approx(Settings.load_from(SETTINGS).music_volume), "and is saved")
	_check(not AudioServer.is_bus_mute(AudioServer.get_bus_index(&"SFX")), "the SOUND bus is not touched")
	main.queue_free()
	await get_tree().create_timer(0.5).timeout  # let audio mix once before quitting (see main.gd)

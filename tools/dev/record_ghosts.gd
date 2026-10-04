extends Node
## Records the developer ghosts (docs/DESIGN.md §16): a three-lap time trial on every track by
## the autopilot at full pace in the Starter car, the best lap saved as
## game/configs/ghosts/<track>.res — the gold ghost a child races against.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tools/dev/record_ghosts.tscn -- --autopilot [--only=track_01]

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://record_ghosts.cfg"
const SETTINGS := "user://record_ghosts_settings.cfg"
const OUT := "res://game/configs/ghosts/%s.res"


func _ready() -> void:
	var only := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.get_slice("=", 1)
	if not Array(OS.get_cmdline_user_args()).has("--autopilot"):
		printerr("run with -- --autopilot: the autopilot drives the ghost laps")
		get_tree().quit(1)
		return
	var save := ConfigFile.new()  # every track open, so each can be selected
	save.set_value("profile", "schema_version", SaveGame.SCHEMA_VERSION)
	save.set_value("profile", "completed_tracks", PackedStringArray(GarageManager.TRACK_ORDER))
	save.save(SAVE)
	var main := MAIN.instantiate()
	main.get_node("GarageManager").save_path = SAVE
	main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(main)
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://game/configs/ghosts"))
	for track_id: StringName in GarageManager.TRACK_ORDER:
		if not only.is_empty() and String(track_id) != only:
			continue
		EventSystem.PRO_track_select_requested.emit(track_id)
		EventSystem.PRO_race_mode_requested.emit(&"time_trial")
		EventSystem.UI_screen_requested.emit(&"race")
		await get_tree().process_frame
		var race: Node = main.get_node("ScreenSlot").get_child(-1)
		await race.manager.race_over
		var ghost: GhostLap = race.recorder.best
		var error := ResourceSaver.save(ghost, OUT % track_id)
		print("%s: %.2f s, %d ticks -> %s (%s)" % [track_id, ghost.lap_time, ghost.frame_count(), OUT % track_id,
			error_string(error)])
		await get_tree().process_frame
	main.queue_free()
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	await get_tree().create_timer(0.5).timeout
	get_tree().quit(0)

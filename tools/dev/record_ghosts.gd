extends Node
## Records the developer ghosts (docs/DESIGN.md §16): a time trial on every track by the
## autopilot at full pace in the starter of its kind (the Starter car, the Speedboat, the Star
## Fighter), the best lap saved as game/configs/ghosts/<track>.res — the gold ghost a child
## races against.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tools/dev/record_ghosts.tscn -- --autopilot [--only=track_01,space_01]

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://record_ghosts.cfg"
const SETTINGS := "user://record_ghosts_settings.cfg"
const OUT := "res://game/configs/ghosts/%s.res"


func _ready() -> void:
	var only := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--only="):
			only = arg.get_slice("=", 1).split(",")
	if not Array(OS.get_cmdline_user_args()).has("--autopilot"):
		printerr("run with -- --autopilot: the autopilot drives the ghost laps")
		get_tree().quit(1)
		return
	var save := ConfigFile.new()  # every track open, so each can be selected
	save.set_value("profile", "schema_version", SaveGame.SCHEMA_VERSION)
	var every := GarageManager.TRACK_ORDER + GarageManager.BOAT_TRACK_ORDER + GarageManager.SHIP_TRACK_ORDER
	save.set_value("profile", "completed_tracks", PackedStringArray(every))
	save.save(SAVE)
	var main := MAIN.instantiate()
	main.get_node("GarageManager").save_path = SAVE
	main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(main)
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://game/configs/ghosts"))
	for track_id: StringName in every:
		if not only.is_empty() and String(track_id) not in only:
			continue
		var kind := &"boat" if track_id in GarageManager.BOAT_TRACK_ORDER \
			else (&"ship" if track_id in GarageManager.SHIP_TRACK_ORDER else &"car")
		EventSystem.PRO_vehicle_kind_requested.emit(kind)
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

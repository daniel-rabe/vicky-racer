extends Node
## The persistent shell: loaded once and never unloaded. Holds GarageManager, CupManager,
## StickerManager, PlayersManager, SettingsManager, SoundManager and MusicManager, which must survive screen
## changes, and the StickerPopup over every screen; swaps screens in and out of ScreenSlot
## when anything emits EventSystem.UI_screen_requested.
##
## Dev flags, after `--` on the command line:
##   --save=<path>           use another save file (keeps screenshots off the real profile)
##   --settings=<path>       use another settings file, likewise
##   --tracks-dir=<path>     keep the child's own tracks (MyTracks) in another folder, likewise
##   --screen=<name>         open this screen first
##   --dev-coins=<n>         set the coin balance after loading
##   --fake-race=<position>  pretend a race just finished in that position
##   --race-mode=time_trial  the next race is a time trial (screenshots of ghosts)
##   --vehicle=boat          the garage, PICK A RACE and the race show the boats (§20)
##   --course=<id>           the boat course the next boat race is on
##   --fps                   show the frame rate in the corner (works in the release .exe:
##                           VickyRacer.exe -- --fps, to check a new machine keeps up)
##   --screenshot=<path>     save a screenshot after --wait seconds (default 2.5) and quit
##   --no-interp             turn physics interpolation off (to measure what it fixes)
##   --physics-hz=<n>        run physics at n ticks per second instead of 60

const SCREENS := {
	&"title": preload("res://ui/title/title_screen.tscn"),
	&"garage": preload("res://ui/garage/garage_screen.tscn"),
	&"tracks": preload("res://ui/track_select/track_select.tscn"),
	&"race": preload("res://game/screens/race.tscn"),
	# Free Drive: the open town (docs/DESIGN.md §19).
	&"town": preload("res://game/screens/town.tscn"),
	# Dev: the open field for tuning handling (--screen=test_drive).
	&"test_drive": preload("res://game/screens/test_drive.tscn"),
	&"results": preload("res://ui/results/results_screen.tscn"),
	&"standings": preload("res://ui/cup/standings.tscn"),
	&"podium": preload("res://ui/cup/podium.tscn"),
	&"shelf": preload("res://ui/shelf/shelf_screen.tscn"),
	&"join": preload("res://ui/join/join_screen.tscn"),
	# The child's own tracks (docs/DESIGN.md §26).
	&"editor": preload("res://ui/editor/track_editor.tscn"),
}
const FIRST_SCREEN := &"title"
## The window's title. The project's own name stays "VickyRacer": it names the folder the
## save lives in (app_userdata/VickyRacer), and changing it would lose every save.
const WINDOW_TITLE := "Vicky Racer"

var _args := {}

@onready var screen_slot: Node = $ScreenSlot
@onready var garage_manager: GarageManager = $GarageManager


func _enter_tree() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--"):
			var parts := arg.substr(2).split("=", true, 1)
			_args[parts[0]] = parts[1] if parts.size() > 1 else ""
	# Children are not ready yet, so this lands before GarageManager loads the profile.
	if _args.has("save"):
		$GarageManager.save_path = _args["save"]
	if _args.has("settings"):
		$SettingsManager.settings_path = _args["settings"]
	if _args.has("tracks-dir"):
		MyTracks.folder = _args["tracks-dir"]
	EventSystem.UI_screen_requested.connect(show_screen)
	if _args.has("no-interp"):
		get_tree().physics_interpolation = false
	if _args.has("physics-hz"):
		Engine.physics_ticks_per_second = int(_args["physics-hz"])


func _ready() -> void:
	# Closing the window (or QUIT on the title) goes through _quit_quietly, below.
	get_tree().set_auto_accept_quit(false)
	get_window().title = WINDOW_TITLE
	if _args.has("dev-coins"):
		garage_manager.profile.coins = int(_args["dev-coins"])
	if _args.has("fps"):
		_add_fps_counter()
	if _args.has("vehicle"):
		EventSystem.PRO_vehicle_kind_requested.emit(StringName(_args["vehicle"]))
	if _args.has("course"):
		EventSystem.PRO_track_select_requested.emit(StringName(_args["course"]))
	if _args.has("race-mode"):
		EventSystem.PRO_race_mode_requested.emit(StringName(_args["race-mode"]))
	if _args.has("fake-race"):
		_fake_race_finish(int(_args["fake-race"]))
	EventSystem.UI_screen_requested.emit(StringName(_args.get("screen", FIRST_SCREEN)))  # so the music hears it too
	if _args.has("screenshot"):
		await get_tree().create_timer(float(_args.get("wait", 2.5))).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_args["screenshot"])
		await _quit_quietly()


func show_screen(screen_name: StringName) -> void:
	get_tree().paused = false  # never carry a pause into the next screen
	for child in screen_slot.get_children():
		child.queue_free()
	screen_slot.add_child(SCREENS[screen_name].instantiate())


## Dev (--fps): the frame rate and the slowest frame of the last second, top left, over everything.
func _add_fps_counter() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(layer)
	var label := Label.new()
	label.name = "FpsCounter"
	label.position = Vector2(12, 8)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	layer.add_child(label)
	var worst := [0.0]
	var tick := Timer.new()
	tick.wait_time = 1.0
	tick.autostart = true
	tick.timeout.connect(func() -> void:
		label.text = "%d FPS   slowest %.1f ms" % [Engine.get_frames_per_second(), worst[0] * 1000.0]
		worst[0] = 0.0)
	layer.add_child(tick)
	get_tree().process_frame.connect(func() -> void: worst[0] = maxf(worst[0], get_process_delta_time()))


## Dev only (--fake-race): a finish with made-up times, for screenshots of the results screen.
func _fake_race_finish(player_position: int) -> void:
	var others := [["BLUE", "res://art/cars/car_blue.png"], ["YELLOW", "res://art/cars/car_yellow.png"],
		["GREEN", "res://art/cars/car_green.png"]]
	var results := []
	for position in range(1, 5):
		var is_player := position == player_position
		var entry: Array = ["YOU", "res://art/cars/car_red.png"] if is_player else others.pop_front()
		results.append({"name": entry[0], "body": entry[1], "is_player": is_player, "position": position,
			"time": 115.0 + position * 2.6, "best_lap": 37.5 + position * 0.7})
	EventSystem.RAC_race_finished.emit(results, &"test_drive")


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit_quietly()


## Quit without leak warnings: a sound still playing at quit is only released by the audio
## server's next mix, which comes after Godot's leak check. Free the screen, let audio mix.
func _quit_quietly() -> void:
	$SettingsManager.remember_window()
	for child in screen_slot.get_children():
		child.queue_free()
	$MusicManager.stop(0.2)
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()

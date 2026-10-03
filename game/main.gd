extends Node
## The persistent shell: loaded once and never unloaded. Holds GarageManager, which must
## survive screen changes, and swaps screens in and out of ScreenSlot when anything emits
## EventSystem.UI_screen_requested.
##
## Dev flags, after `--` on the command line:
##   --save=<path>           use another save file (keeps screenshots off the real profile)
##   --screen=<name>         open this screen first
##   --dev-coins=<n>         set the coin balance after loading
##   --fake-race=<position>  pretend a race just finished in that position
##   --screenshot=<path>     save a screenshot after --wait seconds (default 2.5) and quit
##   --no-interp             turn physics interpolation off (to measure what it fixes)
##   --physics-hz=<n>        run physics at n ticks per second instead of 60

const SCREENS := {
	&"garage": preload("res://ui/garage/garage_screen.tscn"),
	&"race": preload("res://game/screens/race.tscn"),
	# Dev: the open field for tuning handling (--screen=test_drive).
	&"test_drive": preload("res://game/screens/test_drive.tscn"),
	&"results": preload("res://ui/results/results_screen.tscn"),
}
const FIRST_SCREEN := &"garage"

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
	EventSystem.UI_screen_requested.connect(show_screen)
	if _args.has("no-interp"):
		get_tree().physics_interpolation = false
	if _args.has("physics-hz"):
		Engine.physics_ticks_per_second = int(_args["physics-hz"])


func _ready() -> void:
	if _args.has("dev-coins"):
		garage_manager.profile.coins = int(_args["dev-coins"])
	if _args.has("fake-race"):
		_fake_race_finish(int(_args["fake-race"]))
	show_screen(StringName(_args.get("screen", FIRST_SCREEN)))
	if _args.has("screenshot"):
		await get_tree().create_timer(float(_args.get("wait", 2.5))).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_args["screenshot"])
		get_tree().quit()


func show_screen(screen_name: StringName) -> void:
	for child in screen_slot.get_children():
		child.queue_free()
	screen_slot.add_child(SCREENS[screen_name].instantiate())


## Dev only, until the real race exists (Phase 7): a finish with made-up times.
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

extends Node2D
## The race screen: loads the track from the TrackConfig, puts four cars on the grid, runs
## the race and hands over to the results screen when it is over. Escape / Start opens the
## pause menu (its own scene, PauseMenu); leaving from there pays no coins.
##
## Dev flags, after `--`:
##   --autopilot[=pace]  the player's car drives itself (headless race tests, demos);
##                       pace < 1 makes it drive slower, to stand in for a struggling child
##   --overview    frame the whole track in one view, for checking the layout

## The track and opponents of this race: the one picked on the track-select screen.
var config: TrackConfig = preload("res://game/configs/tracks/track_01.tres")
var track: Track
var racers: Array[Dictionary] = []
var _player_setup: DriftSetup
var _player_paint: StringName = Paint.ORIGINAL
var _difficulty_id: StringName = &"normal"

@onready var manager: RaceManager = $RaceManager
@onready var spawner: RacerSpawner = $RacerSpawner
@onready var hud: CanvasLayer = $RaceHUD


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_state_changed)
	EventSystem.UI_settings_changed.connect(func(settings: Dictionary) -> void:
		_difficulty_id = settings.get("difficulty", &"normal"))


func _ready() -> void:
	EventSystem.PRO_state_requested.emit()  # answered synchronously: sets config and _player_setup
	track = config.track_scene.instantiate()
	add_child(track)
	move_child(track, 0)
	EventSystem.UI_settings_requested.emit()  # likewise: sets _difficulty_id
	var difficulty := DifficultyConfig.named(_difficulty_id)
	var args := OS.get_cmdline_user_args()
	var autopilot := Array(args).filter(func(a: String) -> bool: return a.begins_with("--autopilot"))
	racers = spawner.spawn(track, config, _player_setup, $Racers, not autopilot.is_empty(), difficulty, _player_paint)
	for r in racers:
		if r["is_player"]:
			r["car"].get_node("ChaseCamera").set_world_bounds(track.world_rect())
			if autopilot.size() > 0 and "=" in autopilot[0]:
				r["driver"].rubber_band = float(autopilot[0].get_slice("=", 1))
	hud.setup(track, racers, config.laps)
	manager.race_over.connect(func() -> void: EventSystem.UI_screen_requested.emit(&"results"))
	manager.start(track, config, racers, difficulty)
	if "--overview" in args:
		_show_overview()


func _on_state_changed(state: Dictionary) -> void:
	for setup: DriftSetup in state["setups"]:
		if setup.id == state["equipped"]:
			_player_setup = setup
	_player_paint = state.get("paint", {}).get(state["equipped"], Paint.ORIGINAL)
	for entry: Dictionary in state.get("tracks", []):
		if entry["config"].track_id == state.get("selected_track"):
			config = entry["config"]


func _show_overview() -> void:
	var rect := track.world_rect()
	var view := Camera2D.new()
	var fit := minf(1920.0 / rect.size.x, 1080.0 / rect.size.y)
	view.zoom = Vector2(fit, fit)
	view.position = rect.get_center()
	add_child(view)
	view.make_current()
	hud.visible = false

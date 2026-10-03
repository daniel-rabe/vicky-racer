extends Node2D
## The race screen: loads the track from the TrackConfig, puts four cars on the grid, runs
## the race and hands over to the results screen when it is over. Escape abandons the race
## and returns to the garage (no coins).
##
## Dev flags, after `--`:
##   --autopilot[=pace]  the player's car drives itself (headless race tests, demos);
##                       pace < 1 makes it drive slower, to stand in for a struggling child
##   --overview    frame the whole track in one view, for checking the layout

const CONFIG := preload("res://game/configs/tracks/track_01.tres")

var track: Track
var racers: Array[Dictionary] = []
var _player_setup: DriftSetup

@onready var manager: RaceManager = $RaceManager
@onready var spawner: RacerSpawner = $RacerSpawner
@onready var hud: CanvasLayer = $RaceHUD


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_state_changed)


func _ready() -> void:
	track = CONFIG.track_scene.instantiate()
	add_child(track)
	move_child(track, 0)
	EventSystem.PRO_state_requested.emit()  # answered synchronously: sets _player_setup
	var args := OS.get_cmdline_user_args()
	var autopilot := Array(args).filter(func(a: String) -> bool: return a.begins_with("--autopilot"))
	racers = spawner.spawn(track, CONFIG, _player_setup, $Racers, not autopilot.is_empty())
	for r in racers:
		if r["is_player"]:
			r["car"].get_node("ChaseCamera").set_world_bounds(track.world_rect())
			if autopilot.size() > 0 and "=" in autopilot[0]:
				r["driver"].rubber_band = float(autopilot[0].get_slice("=", 1))
	hud.setup(track, racers, CONFIG.laps)
	manager.race_over.connect(func() -> void: EventSystem.UI_screen_requested.emit(&"results"))
	manager.start(track, CONFIG, racers)
	if "--overview" in args:
		_show_overview()


func _on_state_changed(state: Dictionary) -> void:
	for setup: DriftSetup in state["setups"]:
		if setup.id == state["equipped"]:
			_player_setup = setup


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		EventSystem.UI_screen_requested.emit(&"garage")


func _show_overview() -> void:
	var rect := track.world_rect()
	var view := Camera2D.new()
	var fit := minf(1920.0 / rect.size.x, 1080.0 / rect.size.y)
	view.zoom = Vector2(fit, fit)
	view.position = rect.get_center()
	add_child(view)
	view.make_current()
	hud.visible = false

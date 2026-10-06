extends Node2D
## The race screen: loads the track from the TrackConfig, puts four cars on the grid, runs
## the race and hands over to the results screen when it is over. Escape / Start opens the
## pause menu (its own scene, PauseMenu); leaving from there pays no coins.
##
## Two players (docs/DESIGN.md §15): the screen splits left and right. The world — track,
## skid marks, cars — moves into the left SubViewport; the right one shares its World2D, so
## there is one world drawn from two cameras. Each half has its player's HUD; one minimap
## sits between them. A player who finishes first is driven on by the AI, out of the way.
##
## Time trial (§16): the player alone, three laps, against ghosts — the developer's gold one
## and the player's own best lap on this track — while a GhostRecorder records every lap.
## The end reports the laps (RAC_time_trial_finished) instead of a result.
##
## Dev flags, after `--`:
##   --autopilot[=pace]  the player's car drives itself (headless race tests, demos);
##                       pace < 1 makes it drive slower, to stand in for a struggling child
##   --overview    frame the whole track in one view, for checking the layout

const HUD_SCENE := preload("res://ui/hud/race_hud.tscn")
const WAVES := preload("res://art/sfx/wave_ambience.wav")
const THEME := preload("res://ui/theme/vicky_theme.tres")
const DEVELOPER_GHOSTS := "res://game/configs/ghosts/%s.res"
const OWN_GHOST_TINT := Color(1, 1, 1, 0.45)
const DEVELOPER_GHOST_TINT := Color(1, 0.84, 0.3, 0.5)
## Two players: the line between the halves, px, and the shared minimap.
const DIVIDER := 8.0
const DIVIDER_COLOUR := Color(0.055, 0.078, 0.11)
const SHARED_MINIMAP := Vector2(300, 220)

## The track and opponents of this race: the one picked on the track-select screen.
var config: TrackConfig = preload("res://game/configs/tracks/track_01.tres")
var track: Track
var racers: Array[Dictionary] = []
var _player_setup: DriftSetup
var _player_paint: StringName = Paint.ORIGINAL
var _cup_track: TrackConfig
var _difficulty_id: StringName = &"normal"
var _party := {}
var _setups := {}  # id -> DriftSetup, from the garage
var _paints := {}  # setup id -> paint colour
## Two players: the halves of the screen, left (player 1) and right.
var views: Array[SubViewport] = []
var time_trial := false
var recorder: GhostRecorder
## Time trial: the player's own best lap (white) and the developer's (gold), or null.
var own_ghost: GhostCar
var developer_ghost: GhostCar
var _race_mode: StringName = &"race"
var _ghost_dir := ""

@onready var manager: RaceManager = $RaceManager
@onready var spawner: RacerSpawner = $RacerSpawner
@onready var hud: CanvasLayer = $RaceHUD


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_state_changed)
	# In a cup, the cup decides the track (CupManager answers synchronously).
	EventSystem.CUP_state_changed.connect(func(state: Dictionary) -> void:
		if state["phase"] == &"racing" and state["track"]:
			_cup_track = state["track"])
	EventSystem.UI_settings_changed.connect(func(settings: Dictionary) -> void:
		_difficulty_id = settings.get("difficulty", &"normal"))
	EventSystem.PLY_state_changed.connect(func(state: Dictionary) -> void: _party = state)


func _ready() -> void:
	EventSystem.PRO_state_requested.emit()  # answered synchronously: sets config and _player_setup
	EventSystem.CUP_state_requested.emit()
	EventSystem.PLY_state_requested.emit()
	if _cup_track:
		config = _cup_track
	time_trial = _race_mode == &"time_trial" and not _cup_track and not _party.get("two_player", false)
	var humans := _humans()
	var world: Node = self
	if humans.size() > 1:
		world = _split_screen()
	track = config.track_scene.instantiate()
	world.add_child(track)
	world.move_child(track, 0)
	if track.theme:
		var takes := track.theme.music_takes
		EventSystem.UI_music_requested.emit(takes.pick_random() if not takes.is_empty() else track.theme.music)
		if track.theme.water:
			_add_waves()
	EventSystem.UI_settings_requested.emit()  # likewise: sets _difficulty_id
	var difficulty := DifficultyConfig.named(_difficulty_id)
	var args := OS.get_cmdline_user_args()
	var autopilot := Array(args).filter(func(a: String) -> bool: return a.begins_with("--autopilot"))
	var with_ai: bool = not time_trial and (humans.size() == 1 or _party.get("opponents", true))
	racers = spawner.spawn(track, config, humans, world.get_node("Racers"), not autopilot.is_empty(), difficulty, with_ai)
	for r in racers:
		if r["is_player"]:
			var rig: Node = r["car"].get_node("ChaseCamera")
			rig.set_world_bounds(track.world_rect())
			if r["player"] == 2:  # draws the right half
				var camera: Camera2D = rig.get_node("Camera")
				camera.custom_viewport = views[1]
				camera.make_current()
				rig.snap_to_car()
			if autopilot.size() > 0 and "=" in autopilot[0]:
				r["driver"].rubber_band = float(autopilot[0].get_slice("=", 1))
	if humans.size() > 1:
		_split_huds()
		manager.player_finished.connect(_drive_on)
	else:
		hud.setup(track, racers, config.laps, 0, false, time_trial)
	if time_trial:
		_set_up_time_trial(world)
	manager.time_trial = time_trial
	manager.race_over.connect(_on_race_over)
	manager.start(track, config, racers, difficulty)
	if "--overview" in args:
		_show_overview()


func _on_state_changed(state: Dictionary) -> void:
	for setup: DriftSetup in state["setups"]:
		_setups[setup.id] = setup
		if setup.id == state["equipped"]:
			_player_setup = setup
	_paints = state.get("paint", {})
	_player_paint = _paints.get(state["equipped"], Paint.ORIGINAL)
	_race_mode = state.get("race_mode", &"race")
	_ghost_dir = state.get("ghost_dir", "")
	for entry: Dictionary in state.get("tracks", []):
		if entry["config"].track_id == state.get("selected_track"):
			config = entry["config"]


## The ghosts on the track and the recorder on the player's car.
func _set_up_time_trial(world: Node) -> void:
	var player: Dictionary = racers[0]
	recorder = GhostRecorder.new()
	recorder.name = "GhostRecorder"
	recorder.car = player["car"]
	recorder.track_id = config.track_id
	recorder.setup_id = _player_setup.id
	recorder.paint = _player_paint
	add_child(recorder)
	var cars: Node = world.get_node("Racers")
	var path := DEVELOPER_GHOSTS % config.track_id
	if ResourceLoader.exists(path):
		developer_ghost = _ghost_car("DeveloperGhost", load(path), DEVELOPER_GHOST_TINT, cars)
	var saved := GhostLap.load_file(_ghost_dir.path_join("%s.ghost" % config.track_id)) if _ghost_dir else null
	own_ghost = _ghost_car("OwnGhost", saved, OWN_GHOST_TINT, cars)
	recorder.new_best.connect(func(lap: GhostLap) -> void:
		# The ghost is always the best ever: today's lap once it beats the saved one.
		if own_ghost.ghost == null or lap.lap_time < own_ghost.ghost.lap_time:
			own_ghost.ghost = lap)
	manager.lap_started.connect(func(_r: Dictionary) -> void:
		recorder.start_lap()
		for ghost: GhostCar in [own_ghost, developer_ghost]:
			if ghost:
				ghost.start())
	EventSystem.RAC_lap_completed.connect(func(car: Node, _lap: int, lap_time: float) -> void:
		if car == recorder.car:
			recorder.finish_lap(lap_time))


func _ghost_car(node_name: String, lap: GhostLap, tint: Color, parent: Node) -> GhostCar:
	var ghost := GhostCar.new()
	ghost.name = node_name
	ghost.tint = tint
	ghost.ghost = lap
	parent.add_child(ghost)
	parent.move_child(ghost, 0)  # drawn before the cars, so they cover it
	return ghost


func _on_race_over() -> void:
	if time_trial:
		var player: Dictionary = racers[0]
		EventSystem.RAC_time_trial_finished.emit(config.track_id, _player_setup.id, player["lap_times"],
			recorder.best)
	EventSystem.UI_screen_requested.emit(&"results")


## A boat course (docs/DESIGN.md §20.6): small waves lapping, quietly, under the race.
func _add_waves() -> void:
	if not SoundManager.audible():
		return
	var player := AudioStreamPlayer.new()
	player.name = "Waves"
	player.stream = WAVES
	player.bus = &"SFX"
	player.volume_db = -16.0
	add_child(player)
	player.finished.connect(player.play)
	player.play()


## Who drives: the player in their equipped car, or both players of a two-player game in
## the cars they chose on the join screen.
func _humans() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var players: Array = _party.get("players", [])
	if not _party.get("two_player", false) or players.size() < 2:
		out.append({"setup": _player_setup, "paint": _player_paint})
		return out
	for i in players.size():
		var setup: DriftSetup = _setups.get(players[i]["setup"], _player_setup)
		out.append({"setup": setup, "paint": _paints.get(setup.id, Paint.ORIGINAL),
			"name": PlayersManager.NAMES[i], "colour": PlayersManager.COLOURS[i], "number": i + 1,
			"action_prefix": PlayersManager.prefix(i + 1)})
	return out


## Two SubViewports side by side sharing one World2D. Returns the left one, which holds the
## world: fresh skid marks and a fresh Racers node go into it (the scene's own are freed —
## moving them would run their _enter_tree connections a second time), the track next.
func _split_screen() -> SubViewport:
	var layer := CanvasLayer.new()
	layer.name = "Split"
	layer.layer = -1  # under the pause menu and the sticker popup
	add_child(layer)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	layer.add_child(row)
	for i in 2:
		if i == 1:
			var line := ColorRect.new()
			line.color = DIVIDER_COLOUR
			line.custom_minimum_size = Vector2(DIVIDER, 0)
			row.add_child(line)
		var box := SubViewportContainer.new()
		box.name = "View%d" % (i + 1)
		box.stretch = true
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(box)
		var view := SubViewport.new()
		view.name = "Viewport"
		view.audio_listener_enable_2d = i == 0  # car sounds are heard from player 1's view
		box.add_child(view)
		views.append(view)
	views[1].world_2d = views[0].world_2d
	for old: Node in [$SkidMarks, $Racers]:
		remove_child(old)
		old.queue_free()
	var skids := SkidMarks.new()
	skids.name = "SkidMarks"
	views[0].add_child(skids)
	var cars := Node2D.new()
	cars.name = "Racers"
	views[0].add_child(cars)
	return views[0]


## A HUD in each half for its player (new ones: the scene's own is freed, as above), and
## one minimap between them.
func _split_huds() -> void:
	remove_child(hud)
	hud.queue_free()
	for i in 2:
		var half: CanvasLayer = HUD_SCENE.instantiate()
		half.name = "RaceHUD" if i == 0 else "RaceHUD2"
		views[i].add_child(half)
		half.setup(track, racers, config.laps, i + 1, true)
		if i == 0:
			hud = half
	var layer := CanvasLayer.new()
	layer.name = "SharedMinimap"
	add_child(layer)
	var panel := PanelContainer.new()
	panel.theme = THEME
	panel.theme_type_variation = &"HudPanel"
	panel.position = Vector2((1920.0 - SHARED_MINIMAP.x) / 2.0, 1080.0 - SHARED_MINIMAP.y - 32.0)
	panel.size = SHARED_MINIMAP
	layer.add_child(panel)
	var minimap := Minimap.new()
	minimap.name = "Minimap"
	panel.add_child(minimap)
	minimap.setup(track, racers)


## A player who has finished is driven on at an easy pace by the AI, so their car never
## blocks the other player, who is still racing.
func _drive_on(racer: Dictionary) -> void:
	var car: Car = racer["car"]
	if car.has_node(^"PlayerInput"):
		car.get_node(^"PlayerInput").queue_free()
	if racer.has("driver"):
		return
	var driver := AIDriver.new()
	driver.name = "AIDriver"
	driver.skill = 0.3
	driver.track = track
	car.add_child(driver)
	racer["driver"] = driver


func _show_overview() -> void:
	var rect := track.world_rect()
	var view := Camera2D.new()
	var fit := minf(1920.0 / rect.size.x, 1080.0 / rect.size.y)
	view.zoom = Vector2(fit, fit)
	view.position = rect.get_center()
	add_child(view)
	view.make_current()
	hud.visible = false

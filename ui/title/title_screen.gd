extends Node2D
## The title screen (docs/mockups/title_layout): the logo and PLAY / SETTINGS / QUIT over a
## live "attract mode" race, a trophy button beside PLAY for the shelf (docs/DESIGN.md §14)
## and 2 PLAYERS for a split-screen game (§15) — the real Track 01 with four AI cars, the camera following
## the red one. No HUD, no race rules, no car sounds: just something lively to look at.

const TRACK := preload("res://game/configs/tracks/track_01.tres")
const CAR_SCENE := preload("res://actors/car/car.tscn")
const CAMERA_SCRIPT := preload("res://actors/car/chase_camera.gd")
const RED := preload("res://game/configs/setups/starter.tres")
const HINTS_KEYBOARD := "ENTER  CHOOSE"
const HINTS_GAMEPAD := "A  CHOOSE"
## Skills and lanes for the four attract-mode cars, red first.
const SKILLS: Array[float] = [0.8, 0.85, 0.7, 0.6]
const LANES: Array[float] = [0.0, -70.0, 70.0, 0.0]
## Shifts the view so the followed car runs left of the menu instead of behind it.
const VIEW_OFFSET := Vector2(520, 40)

var _cup := {}

@onready var _world: Node2D = $World
@onready var _play: Button = %Play
@onready var _settings_button: Button = %Settings
@onready var _quit: Button = %Quit
@onready var _shelf: Button = %Shelf
@onready var _two_players: Button = %TwoPlayers
@onready var _settings: SettingsPanel = %SettingsPanel
@onready var _menu: Control = %Menu
@onready var _logo: Control = %Logo
@onready var _hints: Label = %Hints


func _enter_tree() -> void:
	EventSystem.CUP_state_changed.connect(func(state: Dictionary) -> void: _cup = state)


func _ready() -> void:
	_build_attract_mode()
	_play.pressed.connect(func() -> void: EventSystem.UI_screen_requested.emit(&"garage"))
	_shelf.pressed.connect(func() -> void: EventSystem.UI_screen_requested.emit(&"shelf"))
	_two_players.pressed.connect(func() -> void:
		EventSystem.PLY_two_player_requested.emit()
		EventSystem.UI_screen_requested.emit(&"join"))
	# The shelf button stands beside the menu: right of PLAY goes to it, left comes back.
	_play.focus_neighbor_right = _play.get_path_to(_shelf)
	_shelf.focus_neighbor_left = _shelf.get_path_to(_play)
	_shelf.focus_neighbor_bottom = _shelf.get_path_to(_two_players)
	_settings_button.pressed.connect(func() -> void:
		_menu.visible = false
		_shelf.visible = false
		_settings.open())
	_settings.closed.connect(func() -> void:
		_menu.visible = true
		_shelf.visible = true
		_settings_button.grab_focus())
	# Quit like closing the window does, so main.gd can let the sound stop cleanly first.
	_quit.pressed.connect(func() -> void:
		get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST))
	_play.grab_focus()
	_add_continue_cup()
	_add_version()
	var bob := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	bob.tween_property(_logo, "position:y", _logo.position.y - 6.0, 1.0)
	bob.tween_property(_logo, "position:y", _logo.position.y + 6.0, 1.0)


## The version, small in the corner, so a parent can tell which build is installed.
func _add_version() -> void:
	var label := Label.new()
	label.name = "Version"
	label.text = "v" + str(ProjectSettings.get_setting("application/config/version", ""))
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color(0.055, 0.078, 0.11))
	label.add_theme_constant_override("outline_size", 6)
	label.modulate.a = 0.7
	label.position = Vector2(1760, 1036)
	_menu.get_parent().add_child(label)


## A cup left half-way (even with the game closed) can be picked up from the title.
func _add_continue_cup() -> void:
	EventSystem.CUP_state_requested.emit()
	if _cup.is_empty() or _cup["phase"] not in [&"ready", &"results"]:
		return
	var button := Button.new()
	button.name = "ContinueCup"
	button.text = "CONTINUE CUP"
	button.custom_minimum_size = Vector2(400, 110)
	button.theme_type_variation = &"RaceButton"
	button.add_theme_font_size_override("font_size", 36)
	button.pressed.connect(func() -> void: EventSystem.CUP_continue_requested.emit())
	_menu.add_child(button)
	_menu.move_child(button, 0)
	_menu.offset_top -= 70.0
	button.focus_neighbor_right = button.get_path_to(_shelf)
	button.grab_focus()


func _build_attract_mode() -> void:
	var track: Track = TRACK.track_scene.instantiate()
	_world.add_child(track)
	_world.add_child(SkidMarks.new())
	var grid := track.grid_transforms()
	var setups: Array[DriftSetup] = [RED]
	setups.append_array(TRACK.opponent_setups)
	var paints: Array[StringName] = [Paint.ORIGINAL]
	paints.append_array(TRACK.opponent_paints)
	for i in mini(grid.size(), setups.size()):
		var car: Car = CAR_SCENE.instantiate()
		car.setup = setups[i]
		car.body_texture = Paint.body(setups[i], paints[i])
		car.transform = grid[i]
		var audio := car.get_node("Audio")  # a quiet menu: no engines
		car.remove_child(audio)
		audio.free()  # before the car enters the tree, so its loops never start
		var driver := AIDriver.new()
		driver.skill = SKILLS[i]
		driver.line_offset = LANES[i]
		driver.track = track
		car.add_child(driver)
		if i == 0:
			car.add_child(_camera_rig(track))
		_world.add_child(car)
		car.reset_physics_interpolation()


func _camera_rig(track: Track) -> Node2D:
	var rig := Node2D.new()
	rig.name = "ChaseCamera"
	rig.set_script(CAMERA_SCRIPT)
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.offset = VIEW_OFFSET
	rig.add_child(camera)
	rig.ready.connect(func() -> void: rig.set_world_bounds(track.world_rect()))
	return rig


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_hints.text = HINTS_GAMEPAD
	elif event is InputEventKey:
		_hints.text = HINTS_KEYBOARD

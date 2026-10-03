extends Node2D
## The title screen (docs/mockups/title_layout): the logo and PLAY / SETTINGS / QUIT over a
## live "attract mode" race — the real Track 01 with four AI cars, the camera following
## the red one. No HUD, no race rules, no car sounds: just something lively to look at.

const TRACK := preload("res://game/configs/tracks/track_01.tres")
const CAR_SCENE := preload("res://actors/car/car.tscn")
const CAMERA_SCRIPT := preload("res://actors/car/chase_camera.gd")
const RED := preload("res://art/cars/car_red.png")
const HINTS_KEYBOARD := "ENTER  CHOOSE"
const HINTS_GAMEPAD := "A  CHOOSE"
## Skills and lanes for the four attract-mode cars, red first.
const SKILLS: Array[float] = [0.8, 0.85, 0.7, 0.6]
const LANES: Array[float] = [0.0, -70.0, 70.0, 0.0]
## Shifts the view so the followed car runs left of the menu instead of behind it.
const VIEW_OFFSET := Vector2(520, 40)

@onready var _world: Node2D = $World
@onready var _play: Button = %Play
@onready var _settings_button: Button = %Settings
@onready var _quit: Button = %Quit
@onready var _settings: SettingsPanel = %SettingsPanel
@onready var _menu: Control = %Menu
@onready var _logo: Control = %Logo
@onready var _hints: Label = %Hints


func _ready() -> void:
	_build_attract_mode()
	_play.pressed.connect(func() -> void: EventSystem.UI_screen_requested.emit(&"garage"))
	_settings_button.pressed.connect(func() -> void:
		_menu.visible = false
		_settings.open())
	_settings.closed.connect(func() -> void:
		_menu.visible = true
		_settings_button.grab_focus())
	_quit.pressed.connect(func() -> void: get_tree().quit())
	_play.grab_focus()
	var bob := create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	bob.tween_property(_logo, "position:y", _logo.position.y - 6.0, 1.0)
	bob.tween_property(_logo, "position:y", _logo.position.y + 6.0, 1.0)


func _build_attract_mode() -> void:
	var track: Track = TRACK.track_scene.instantiate()
	_world.add_child(track)
	_world.add_child(SkidMarks.new())
	var grid := track.grid_transforms()
	var bodies: Array[Texture2D] = [RED]
	bodies.append_array(TRACK.opponent_bodies)
	for i in mini(grid.size(), bodies.size()):
		var car: Car = CAR_SCENE.instantiate()
		car.body_texture = bodies[i]
		car.transform = grid[i]
		car.get_node("Audio").queue_free()  # a quiet menu: no engines
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

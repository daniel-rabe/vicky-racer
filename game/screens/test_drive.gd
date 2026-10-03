extends Node2D
## Dev screen for tuning the handling before any track exists: an open grass field with
## a tyre wall round the edge and hay bales to bump into. Keys 1–6 swap the drift setup
## live; Backspace puts the car back in the middle. Escape returns to the garage.
## The car starts with whatever setup is equipped in the garage.
##
## Dev check: `-- --drive-circle` drives a steady, wide circle clear of every edge (so the
## camera never hits its limits), for measuring how smoothly the car moves on screen
## (tools/dev/motion_check.py).
##
## Dev check: `-- --autodrive-screenshot=<path.png>` circles with the handbrake for a few
## seconds, saves a screenshot and quits, so the look can be verified without a person.

const FIELD := Vector2(3072, 2048)
## Grass continues this far past the tyre wall, and the camera stops at its edge.
const MARGIN := 512.0
const WALL_THICKNESS := 64.0
const TYRE_SPACING := 76.0
const SETUP_PATHS: Array[String] = [
	"res://game/configs/setups/starter.tres",
	"res://game/configs/setups/grippy.tres",
	"res://game/configs/setups/slider.tres",
	"res://game/configs/setups/rocket.tres",
	"res://game/configs/setups/kart.tres",
	"res://game/configs/setups/banana.tres",
]
const TYRE_TEXTURE := preload("res://art/props/tyre_stack.png")
const BALE_TEXTURE := preload("res://art/props/hay_bale.png")
const BALE_POSITIONS: Array[Vector2] = [
	Vector2(900, 600), Vector2(2100, 650), Vector2(1536, 1500), Vector2(700, 1450), Vector2(2400, 1400),
]

var _setups: Array[DriftSetup] = []
var _autodrive_path := ""
var _autodrive_time := 0.0
var _autodrive_done := false
var _drive_circle := false

@onready var car: Car = $Car
@onready var readout: Label = %Readout


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_state_changed)


func _on_state_changed(state: Dictionary) -> void:
	for setup: DriftSetup in _setups:
		if setup.id == state["equipped"]:
			car.setup = setup


func _ready() -> void:
	for path in SETUP_PATHS:
		_setups.append(load(path))
	var world := Rect2(-Vector2(MARGIN, MARGIN), FIELD + 2.0 * Vector2(MARGIN, MARGIN))
	$Ground.position = world.position
	$Ground.region_rect = Rect2(Vector2.ZERO, world.size)
	car.get_node("ChaseCamera").set_world_bounds(world)
	_build_walls()
	_build_bales()
	_reset_car()
	EventSystem.PRO_state_requested.emit()
	for arg in OS.get_cmdline_user_args():
		if arg == "--drive-circle":
			_drive_circle = true
			car.get_node("PlayerInput").queue_free()
			# Full lock: a ~340 px circle round the field centre, far from the camera limits.
			car.position = Vector2(FIELD.x / 2.0, FIELD.y / 2.0 - 340.0)
			car.reset_physics_interpolation()
			car.get_node("ChaseCamera").snap_to_car()
		if arg.begins_with("--autodrive-screenshot="):
			_autodrive_path = arg.get_slice("=", 1)
			car.get_node("PlayerInput").queue_free()


func _build_walls() -> void:
	var walls := StaticBody2D.new()
	walls.name = "Walls"
	add_child(walls)
	var t := WALL_THICKNESS
	var rects := [
		Rect2(-t, -t, FIELD.x + 2 * t, t), Rect2(-t, FIELD.y, FIELD.x + 2 * t, t),
		Rect2(-t, 0, t, FIELD.y), Rect2(FIELD.x, 0, t, FIELD.y),
	]
	for rect: Rect2 in rects:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		walls.add_child(shape)
	# The tyre wall is drawn just inside the collision, along every edge.
	var inset := TYRE_TEXTURE.get_width() / 2.0
	var x := inset
	while x < FIELD.x:
		_add_sprite(TYRE_TEXTURE, Vector2(x, inset))
		_add_sprite(TYRE_TEXTURE, Vector2(x, FIELD.y - inset))
		x += TYRE_SPACING
	var y := inset + TYRE_SPACING
	while y < FIELD.y - TYRE_SPACING:
		_add_sprite(TYRE_TEXTURE, Vector2(inset, y))
		_add_sprite(TYRE_TEXTURE, Vector2(FIELD.x - inset, y))
		y += TYRE_SPACING


func _build_bales() -> void:
	for pos in BALE_POSITIONS:
		var body := StaticBody2D.new()
		body.position = pos
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(88, 88)
		shape.shape = box
		body.add_child(shape)
		var sprite := Sprite2D.new()
		sprite.texture = BALE_TEXTURE
		body.add_child(sprite)
		add_child(body)


func _add_sprite(texture: Texture2D, pos: Vector2) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = pos
	add_child(sprite)


func _reset_car() -> void:
	car.position = FIELD / 2.0
	car.rotation = 0.0
	car.velocity = Vector2.ZERO
	# A teleport: without this, physics interpolation would draw the car gliding back.
	car.reset_physics_interpolation()
	car.get_node("ChaseCamera").snap_to_car()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_6:
		car.setup = _setups[key.physical_keycode - KEY_1]
	elif key.physical_keycode == KEY_BACKSPACE:
		_reset_car()
	elif key.physical_keycode == KEY_ESCAPE:
		EventSystem.UI_screen_requested.emit(&"garage")


func _process(_delta: float) -> void:
	if _drive_circle:
		car.throttle_input = 1.0
		car.steer_input = 1.0
	var names := PackedStringArray()
	for i in _setups.size():
		var marker := ">" if _setups[i] == car.setup else " "
		names.append("%s%d %s" % [marker, i + 1, _setups[i].display_name])
	readout.text = "\n".join([
		"SETUP  %s" % car.setup.display_name,
		"SPEED  %4d / %d" % [car.velocity.length(), car.config.max_speed],
		"SLIDE  %4d %s" % [car.lateral_speed, "DRIFT!" if car.is_drifting else ""],
		"",
		"  ".join(names),
		"1-6 setup   SPACE handbrake   BACKSPACE reset   ESC garage",
	])


func _physics_process(delta: float) -> void:
	if _autodrive_path.is_empty() or _autodrive_done:
		return
	_autodrive_time += delta
	car.throttle_input = 1.0
	car.steer_input = 0.0 if _autodrive_time < 1.2 else 1.0
	car.handbrake = _autodrive_time > 1.6
	if _autodrive_time > 3.0:
		_autodrive_done = true
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(_autodrive_path)
		get_tree().quit()


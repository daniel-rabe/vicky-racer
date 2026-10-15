extends Node
## Reads the player's controls for Vicky on foot (Kid) and writes them into him. Named
## PlayerInput in the tree, as the car's controls are, so the town treats him as the player.
##   - the arrows / WASD, the left stick or the d-pad: walk that way;
##   - SPACE / X (the drift button) held: run;
##   - H / Y (the horn): a whistle, and the car comes (TownScreen).
## The driving assists (auto accelerate, steering help) are for driving, and do nothing here.

@onready var kid: Kid = get_parent()


func _ready() -> void:
	process_physics_priority = -1  # before he moves this frame


func _physics_process(_delta: float) -> void:
	var move := Vector2(Input.get_axis(&"steer_left", &"steer_right"), 0.0)
	# Up and down: W / S and the arrows (accelerate and brake on the keyboard), and the stick and
	# the d-pad through the ui actions. Not the triggers or A / B, which drive the car.
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		move.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		move.y += 1.0
	var pad := Input.get_vector(&"ui_left", &"ui_right", &"ui_up", &"ui_down")
	if not Input.is_physical_key_pressed(KEY_LEFT) and not Input.is_physical_key_pressed(KEY_RIGHT) \
			and not Input.is_physical_key_pressed(KEY_UP) and not Input.is_physical_key_pressed(KEY_DOWN):
		move.y += pad.y
		if absf(move.x) < 0.1:
			move.x = pad.x
	kid.move_input = move.limit_length(1.0)
	kid.running = Input.is_action_pressed(&"handbrake")
	if Input.is_action_just_pressed(&"horn"):
		EventSystem.CAR_horn.emit(kid)

extends Node
## Reads the player's controls and writes them into the parent Car. Nothing else.

@onready var car: Car = get_parent()


func _ready() -> void:
	# Run before the car each physics frame, so it uses this frame's input.
	process_physics_priority = -1


func _physics_process(_delta: float) -> void:
	car.steer_input = Input.get_axis("steer_left", "steer_right")
	car.throttle_input = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
	car.handbrake = Input.is_action_pressed("handbrake")

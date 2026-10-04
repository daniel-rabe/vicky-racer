extends Node
## Reads the player's controls and writes them into the parent Car — plus the two driving
## assists from the settings (docs/DESIGN.md §3.1), which follow UI_settings_changed live:
##   - auto accelerate: cruises at AUTO_GO_PACE of top speed unless braking, so a very young
##     child only steers. Holding accelerate still gives full speed: AUTO GO is a floor, and
##     it must not turn into an autopilot that wins with no input at all;
##   - steering help: steers toward the road ahead, fully while the child is not steering
##     and as a gentle nudge while they are. It keeps the child's own lane on the road and
##     only pulls toward the middle when the car is near the edge.

## Fraction of top speed AUTO GO cruises at.
const AUTO_GO_PACE := 0.65
const HELP_LOOKAHEAD := 220.0
## Extra lookahead per px/s of speed, as for the AI: calm at speed.
const HELP_LOOKAHEAD_PER_SPEED := 0.3
## Being this far off the target, in radians, is a full turn of help.
const HELP_FULL_ANGLE := 0.6
## How much of that help is used while the child is not steering, and on top of their
## own steering when they are.
const HELP_ALONE := 0.85
const HELP_WITH := 0.3
## Steering input below this counts as "not steering".
const STEER_DEADZONE := 0.15
## Lanes kept by the help stay this far inside the road edge, px.
const EDGE_MARGIN := 80.0

var auto_accelerate := false
var steering_help := false
## Set by the RacerSpawner; steering help does nothing without a track.
var track: Track

@onready var car: Car = get_parent()


func _enter_tree() -> void:
	EventSystem.UI_settings_changed.connect(_on_settings_changed)


func _ready() -> void:
	# Run before the car each physics frame, so it uses this frame's input.
	process_physics_priority = -1
	EventSystem.UI_settings_requested.emit()


func _on_settings_changed(settings: Dictionary) -> void:
	auto_accelerate = settings.get("auto_accelerate", false)
	steering_help = settings.get("steering_help", false)


func _physics_process(_delta: float) -> void:
	var steer := Input.get_axis("steer_left", "steer_right")
	var accelerate := Input.get_action_strength("accelerate")
	var brake := Input.get_action_strength("brake")
	if auto_accelerate and brake < 0.1 and accelerate < 0.1:
		var cruise := AUTO_GO_PACE * car.config.max_speed * car.surface_speed()
		accelerate = 1.0 if car.forward_speed() < cruise else 0.0
	if steering_help and track and car.forward_speed() > 60.0:
		steer = _helped(steer)
	car.steer_input = steer
	car.throttle_input = accelerate - brake
	car.handbrake = Input.is_action_pressed("handbrake")
	if Input.is_action_just_pressed("horn"):
		EventSystem.CAR_horn.emit(car)


func _helped(steer: float) -> float:
	var pos := car.global_position
	var here := track.progress_of(car)
	var limit := track.road_half_width - EDGE_MARGIN
	var lane := clampf(track.side_of_line(pos, here), -limit, limit)
	var target := track.line_point(here + HELP_LOOKAHEAD + car.velocity.length() * HELP_LOOKAHEAD_PER_SPEED, lane)
	var angle := Vector2.RIGHT.rotated(car.rotation).angle_to(target - pos)
	var help := clampf(angle / HELP_FULL_ANGLE, -1.0, 1.0)
	if absf(steer) < STEER_DEADZONE:
		return help * HELP_ALONE
	return clampf(steer + help * HELP_WITH, -1.0, 1.0)

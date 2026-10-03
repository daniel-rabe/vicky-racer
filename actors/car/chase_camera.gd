extends Node2D
## Camera rig that follows its parent car. The view stays world-up (it never rotates with
## the car, which would disorient a young player) and leads toward where the car is
## heading, so the next corner comes into view in time (docs/DESIGN.md §5).
##
## Built for physics interpolation (project.godot), which keeps motion smooth when the
## monitor refreshes faster than the 60 Hz physics. Interpolation smooths node positions
## between ticks, so the only thing that moves the view is a position:
##   - this node is a child of the car, placed every physics tick so that its *world*
##     offset from the car is the lead;
##   - the Camera2D child has no position smoothing and its zoom never changes while
##     driving. Measured with tools/dev/motion_check.py on a 60 Hz physics / 100 fps
##     render: Camera2D smoothing, a top_level camera, and changing zoom (on either clock)
##     each made the drawn view lag irregularly, ~3 px of wobble per frame, because a
##     camera update recomputes the view from the raw, uninterpolated position.

## Fixed on purpose — see above. 0.92 shows about a second of road ahead at top speed.
@export var zoom_level := 0.92
## How far ahead of the car the view leads at top speed, px.
@export var lead_distance := 260.0
@export var lead_smoothing := 2.5

var _lead := Vector2.ZERO

@onready var car: Car = get_parent()
@onready var camera: Camera2D = $Camera


func _ready() -> void:
	camera.ignore_rotation = true
	camera.zoom = Vector2(zoom_level, zoom_level)
	snap_to_car()


func _physics_process(delta: float) -> void:
	var speed_fraction := clampf(car.velocity.length() / car.config.max_speed, 0.0, 1.0)
	var target_lead := car.velocity.normalized() * lead_distance * speed_fraction
	_lead = _lead.lerp(target_lead, 1.0 - exp(-lead_smoothing * delta))
	# A child of the rotating car: undo the car's rotation so the world offset is _lead.
	position = _lead.rotated(-car.rotation)


## Jump straight to the car, e.g. after it is placed on the grid or reset.
func snap_to_car() -> void:
	_lead = Vector2.ZERO
	position = Vector2.ZERO
	reset_physics_interpolation()
	camera.reset_physics_interpolation()


## Keep the view inside `world_rect`, so the player never sees past the edge of the map.
func set_world_bounds(world_rect: Rect2) -> void:
	camera.limit_left = int(world_rect.position.x)
	camera.limit_top = int(world_rect.position.y)
	camera.limit_right = int(world_rect.end.x)
	camera.limit_bottom = int(world_rect.end.y)

extends Camera2D
## Follows its parent car. Stays world-up (never rotates with the car, which would
## disorient a young player), leads toward where the car is heading, and eases out a
## little at speed so the next corner is visible in time (docs/DESIGN.md §5).

@export var base_zoom := 1.0
@export var top_speed_zoom := 0.85
## How far ahead of the car the view leads at top speed, px.
@export var lead_distance := 260.0
@export var lead_smoothing := 2.5
@export var zoom_smoothing := 1.5

@onready var car: Car = get_parent()


func _ready() -> void:
	ignore_rotation = true
	position_smoothing_enabled = true
	position_smoothing_speed = 6.0
	zoom = Vector2(base_zoom, base_zoom)


func _physics_process(delta: float) -> void:
	var speed_fraction := clampf(car.velocity.length() / car.config.max_speed, 0.0, 1.0)
	var lead := car.velocity.normalized() * lead_distance * speed_fraction
	offset = offset.lerp(lead, 1.0 - exp(-lead_smoothing * delta))
	var target := lerpf(base_zoom, top_speed_zoom, speed_fraction)
	zoom = zoom.lerp(Vector2(target, target), 1.0 - exp(-zoom_smoothing * delta))


## Keep the view inside `world_rect`, so the player never sees past the edge of the map.
func set_world_bounds(world_rect: Rect2) -> void:
	limit_left = int(world_rect.position.x)
	limit_top = int(world_rect.position.y)
	limit_right = int(world_rect.end.x)
	limit_bottom = int(world_rect.end.y)

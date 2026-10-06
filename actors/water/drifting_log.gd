extends AnimatableBody2D
## A log floating to and fro across a river (docs/DESIGN.md §20.2): it drifts from `from`
## to `to` and back, easing at each end, broadside to the way it moves. Solid like the shore,
## so a boat that meets it bounces off; the track builder places it from the layout's `logs`.

@export var from := Vector2.ZERO
@export var to := Vector2.ZERO
## Seconds for one crossing, there or back.
@export var crossing_seconds := 6.0
## Where in its swing it starts, 0-1, so logs on one river do not move in step.
@export var phase := 0.0

var _time := 0.0


func _ready() -> void:
	sync_to_physics = true
	collision_layer = Car.LAYER_WORLD
	collision_mask = 0
	_time = phase * crossing_seconds * 2.0
	position = _at(_time)


func _physics_process(delta: float) -> void:
	_time += delta
	position = _at(_time)


func _at(time: float) -> Vector2:
	var swing := 0.5 - 0.5 * cos(PI * time / crossing_seconds)
	return from.lerp(to, swing)

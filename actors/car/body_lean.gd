class_name BodyLean
extends Node
## The car's body leans out of a drift (docs/CAR_ANIMATION_PLAN.md §5): sliding sideways, the
## body sits a little towards the outside and swings its tail a little further out. Only the
## picture moves; the car itself, its collision and its handling stay where they are.

## At full lean: degrees the body turns, and px it shifts sideways.
const MAX_DEGREES := 5.0
const MAX_SHIFT := 3.0
## Sideways speed, px/s, from which the body starts leaning and at which it leans fully.
const FROM := 120.0
const FULL := 450.0
## How fast the lean follows, 1/s.
const RATE := 8.0

## -1 (leaning out to the left) .. 1 (to the right).
var lean := 0.0

@onready var car: Car = get_parent()
@onready var body: Sprite2D = car.get_node(^"Body")


func _physics_process(delta: float) -> void:
	var target := 0.0
	if not car.frozen:
		var sliding_right := car.velocity.dot(Vector2.DOWN.rotated(car.rotation))
		target = signf(sliding_right) * smoothstep(FROM, FULL, absf(sliding_right))
	lean = lerpf(lean, target, 1.0 - exp(-RATE * delta))
	# Sliding right, the nose points left of where the car goes: turn it further left.
	body.rotation = -lean * deg_to_rad(MAX_DEGREES)
	body.position = Vector2(0.0, lean * MAX_SHIFT)

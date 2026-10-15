class_name Kid
extends Car
## Vicky on foot in the open world (docs/DESIGN.md §29): out of the car, he walks top-down in
## any direction, and runs while the drift button is held. He is a Car to the rest of the town,
## so everything that looks for the player's car finds him too: coins, shop doors, the garage's
## pad, traffic stopping for him (and tooting if he stands in the road), the minimap. He cannot
## drift, boost or jump a ramp, and like a car he stays on the land.
##
## Built in code by `make`. The picture is drawn in code too (KidFigure): legs, arms and his
## racing helmet, swinging as he walks; ComfyUI art can replace it later.
##
## A KidInput child (named PlayerInput, as the car's controls are) writes `move_input` and
## `running` every physics frame.

const WALK_SPEED := 260.0
const RUN_SPEED := 430.0
## How fast he gets going and stops, px/s².
const ACCEL := 2400.0
const TURN_RATE := 14.0
## His body: a box (so balls and cones see him as they see a car), about a child's shoulders.
const SIZE := Vector2(40, 50)

var move_input := Vector2.ZERO
var running := false


## A new Kid, ready to add to the world.
static func make() -> Kid:
	var kid := Kid.new()
	kid.name = "Kid"
	kid.base_config = load("res://game/configs/cars/base_car.tres")
	kid.setup = load("res://game/configs/setups/starter.tres")
	kid.body_texture = null
	var body := Sprite2D.new()
	body.name = "Body"
	kid.add_child(body)
	var figure := KidFigure.new()
	figure.name = "Figure"
	figure.scale = Vector2(1.6, 1.6)
	figure.kid = kid
	body.add_child(figure)
	var collision := CollisionShape2D.new()
	collision.name = "Collision"
	var box := RectangleShape2D.new()
	box.size = SIZE
	collision.shape = box
	kid.add_child(collision)
	var audio := Node2D.new()  # the town quietens a parked vehicle's Audio; he has none
	audio.name = "Audio"
	kid.add_child(audio)
	return kid


func _ready() -> void:
	super()
	add_to_group(&"kid")  # the animals look for him to be petted
	config = config.duplicate()
	config.max_speed = RUN_SPEED  # the camera leads by speed over this


## Nobody sits in him.
func _update_rider() -> void:
	pass


func _physics_process(delta: float) -> void:
	if frozen:
		velocity = Vector2.ZERO
		return
	var wish := move_input.limit_length(1.0)
	var speed := (RUN_SPEED if running else WALK_SPEED) * maxf(surface_speed_mult, 0.75)
	velocity = velocity.move_toward(wish * speed, ACCEL * delta)
	if wish.length() > 0.2:
		rotation = lerp_angle(rotation, wish.angle(), 1.0 - exp(-TURN_RATE * delta))
	move_and_slide()
	is_drifting = false
	lateral_speed = 0.0


## The picture: two feet stepping, two arms swinging, a jacket and Vicky's helmet with its
## visor to the front (+X). Drawn every frame while he moves.
class KidFigure extends Node2D:
	const JACKET := Color(0.9, 0.22, 0.27)
	const JACKET_DARK := Color(0.7, 0.13, 0.18)
	const SKIN := Color(0.98, 0.8, 0.65)
	const SHOE := Color(0.2, 0.22, 0.3)
	const HELMET := Color(0.93, 0.2, 0.24)
	const STRIPE := Color(1, 0.97, 0.9)
	const VISOR := Color(0.16, 0.2, 0.28)
	const OUTLINE := Color(0.055, 0.078, 0.11)

	var kid: Kid
	var _phase := 0.0
	var _swing := 0.0

	func _process(delta: float) -> void:
		var speed := kid.velocity.length() if kid else 0.0
		var moving := speed > 20.0
		_phase += delta * (speed / 26.0 if moving else 0.0)
		_swing = lerpf(_swing, 1.0 if moving else 0.0, 1.0 - exp(-10.0 * delta))
		queue_redraw()

	func _draw() -> void:
		var step := sin(_phase) * 11.0 * _swing
		# Feet, under everything, stepping forward and back.
		for side in [-1.0, 1.0]:
			var at := Vector2(step * side, 9.0 * side)
			draw_circle(at, 7.5, OUTLINE)
			draw_circle(at, 6.0, SHOE)
		# Arms swing the other way from the feet.
		for side in [-1.0, 1.0]:
			var hand := Vector2(-step * side * 0.9 + 2.0, 19.0 * side)
			draw_line(Vector2(0, 13.0 * side), hand, OUTLINE, 9.0, true)
			draw_line(Vector2(0, 13.0 * side), hand, JACKET_DARK, 6.0, true)
			draw_circle(hand, 5.0, OUTLINE)
			draw_circle(hand, 3.8, SKIN)
		# The jacket: shoulders across, seen from above.
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(0.62, 1.0))
		draw_circle(Vector2.ZERO, 17.0, OUTLINE)
		draw_circle(Vector2.ZERO, 15.0, JACKET)
		draw_set_transform(Vector2.ZERO)
		# The helmet, with a stripe front to back and the visor at the front.
		draw_circle(Vector2(1, 0), 13.0, OUTLINE)
		draw_circle(Vector2(1, 0), 11.5, HELMET)
		draw_line(Vector2(-10, 0), Vector2(5, 0), STRIPE, 4.0, true)
		draw_arc(Vector2(1, 0), 8.5, -1.0, 1.0, 12, VISOR, 5.0, true)

class_name ToyTrain
extends Node2D
## Toy town's train (docs/DESIGN.md §36): an engine and three wagons going round and round
## their own track inside the toy road, puffing smoke. Each carriage is solid and moves as a
## body, so it nudges a car that stands on the track out of its way (and the ball, too).

const CARRIAGE := Vector2(150.0, 84.0)
const GAP := 172.0
const WAGON_COLOURS: Array[Color] = [Color(0.25, 0.55, 0.95), Color(0.98, 0.78, 0.2), Color(0.35, 0.78, 0.35)]
const ENGINE_COLOUR := Color(0.9, 0.22, 0.25)

## The track, closed, and how far round it the engine is (px).
var rails := PackedVector2Array()
var speed := ToyIsland.TRAIN_SPEED
var travelled := 0.0
var cars: Array[AnimatableBody2D] = []
var _lengths := PackedFloat32Array()
var _total := 0.0
var _smoke: CPUParticles2D


func _ready() -> void:
	_total = 0.0
	for i in rails.size():
		_lengths.append(_total)
		_total += rails[i].distance_to(rails[(i + 1) % rails.size()])
	for k in 4:
		var body := AnimatableBody2D.new()
		body.name = "Engine" if k == 0 else "Wagon%d" % k
		body.collision_layer = Car.LAYER_WORLD
		body.collision_mask = 0
		body.sync_to_physics = false  # placed by hand each physics frame, not by an animation
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = CARRIAGE - Vector2(10, 10)
		shape.shape = box
		body.add_child(shape)
		var picture := Carriage.new()
		picture.engine = k == 0
		picture.colour = ENGINE_COLOUR if k == 0 else WAGON_COLOURS[(k - 1) % WAGON_COLOURS.size()]
		body.add_child(picture)
		add_child(body)
		cars.append(body)
	_smoke = CPUParticles2D.new()
	_smoke.local_coords = false
	_smoke.amount = 24
	_smoke.lifetime = 1.6
	_smoke.direction = Vector2(-1, -0.4)
	_smoke.spread = 25.0
	_smoke.initial_velocity_min = 30.0
	_smoke.initial_velocity_max = 60.0
	_smoke.gravity = Vector2.ZERO
	_smoke.scale_amount_min = 10.0
	_smoke.scale_amount_max = 20.0
	_smoke.color = Color(1, 1, 1, 0.55)
	_smoke.z_index = 2
	add_child(_smoke)
	_place()


func _physics_process(delta: float) -> void:
	travelled = fmod(travelled + speed * delta, _total)
	_place()


## Where the engine is.
func engine_at() -> Vector2:
	return cars[0].global_position


func _place() -> void:
	for k in cars.size():
		var d := fposmod(travelled - k * GAP, _total)
		var at := _point(d)
		var ahead := _point(fposmod(d + 20.0, _total))
		cars[k].global_position = at
		cars[k].global_rotation = (ahead - at).angle()
	_smoke.global_position = cars[0].global_position + Vector2(30, 0).rotated(cars[0].global_rotation)


func _point(d: float) -> Vector2:
	var i := _lengths.bsearch(d, true) - 1
	i = clampi(i, 0, rails.size() - 1)
	var a := rails[i]
	var b := rails[(i + 1) % rails.size()]
	var length := a.distance_to(b)
	return a.lerp(b, (d - _lengths[i]) / length if length > 0.0 else 0.0)


## One carriage seen from above, facing right: a shadow, wheels sticking out each side, the
## body; the engine with its cab, boiler and chimney, a wagon with a load of toy bricks.
class Carriage extends Node2D:
	var engine := false
	var colour := Color.WHITE

	func _draw() -> void:
		var size := ToyTrain.CARRIAGE
		var half := size / 2.0
		draw_rect(Rect2(-half + Vector2(8, 10), size), Color(0, 0, 0, 0.22))
		for x in [-half.x + 30.0, half.x - 30.0]:
			for y in [-half.y - 6.0, half.y - 8.0]:
				draw_rect(Rect2(x - 16.0, y, 32.0, 14.0), Color(0.15, 0.15, 0.18))
		draw_rect(Rect2(-half, size), colour.darkened(0.25))
		draw_rect(Rect2(-half + Vector2(6, 6), size - Vector2(12, 12)), colour)
		draw_rect(Rect2(half.x - 4.0, -10.0, 16.0, 20.0), Color(0.3, 0.3, 0.32))  # the coupling
		if engine:
			draw_rect(Rect2(-half.x + 6.0, -half.y + 6.0, 52.0, size.y - 12.0), colour.darkened(0.15))  # the cab
			draw_rect(Rect2(-half.x + 14.0, -half.y + 14.0, 36.0, size.y - 28.0), Color(1.0, 0.85, 0.3))  # its roof
			draw_circle(Vector2(30, 0), 18.0, Color(0.18, 0.18, 0.2))  # the chimney
			draw_circle(Vector2(30, 0), 10.0, Color(0.05, 0.05, 0.05))
			draw_circle(Vector2(half.x - 10.0, 0), 12.0, Color(1.0, 0.95, 0.6))  # the lamp
		else:
			for k in 3:
				var brick := Rect2(-half.x + 16.0 + k * 42.0, -18.0 + (k % 2) * 6.0, 36.0, 30.0)
				draw_rect(brick, [Color(0.95, 0.3, 0.3), Color(0.3, 0.75, 0.95), Color(0.98, 0.85, 0.3)][k])
				draw_rect(brick, Color(0, 0, 0, 0.25), false, 2.0)

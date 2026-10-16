class_name CarMud
extends Node2D
## Mud splashed up a car from one of the jungle's mud pools (docs/DESIGN.md §35): brown
## splodges round the edges of its body, more with every pool, that stay on until the car
## goes through the car wash (CAR_washed).

const MUD_COLOUR := Color(0.42, 0.28, 0.15, 0.9)
const DRIP_COLOUR := Color(0.33, 0.21, 0.11, 0.9)
## Splodges added per pool, and the most a car can carry.
const PER_SPLASH := 9
const MOST := 36

var _spots: Array[Vector3] = []  # x, y, radius, in the body's own frame
var _rng := RandomNumberGenerator.new()


## Splash `car` with mud: muddy it, or muddier if it already is.
static func splash(car: Car) -> void:
	var body: Node2D = car.get_node(^"Body")
	var mud: CarMud = body.get_node_or_null(^"Mud")
	if mud == null:
		mud = CarMud.new()
		mud.name = "Mud"
		body.add_child(mud)
	mud.add_splodges()


static func is_muddy(car: Node) -> bool:
	return car.has_node(^"Body/Mud")


func _enter_tree() -> void:
	EventSystem.CAR_washed.connect(_on_washed)


func _ready() -> void:
	_rng.randomize()


func _on_washed(car: Node) -> void:
	if car.get_node_or_null(^"Body") == get_parent():
		queue_free()


func add_splodges() -> void:
	var body: Sprite2D = get_parent()
	var half := body.texture.get_size() / 2.0 if body.texture else Vector2(50, 30)
	for k in PER_SPLASH:
		# Mostly low on the sides and at the back, where the wheels throw it, never over the
		# driver in the middle.
		var at := Vector2(_rng.randf_range(-1.0, 0.9) * half.x * 0.85, _rng.randf_range(0.55, 0.95) * half.y * (1.0 if _rng.randf() < 0.5 else -1.0))
		if _rng.randf() < 0.3:
			at = Vector2(-half.x * _rng.randf_range(0.7, 0.9), _rng.randf_range(-0.6, 0.6) * half.y)
		_spots.append(Vector3(at.x, at.y, _rng.randf_range(5.0, 11.0)))
	while _spots.size() > MOST:
		_spots.pop_front()
	queue_redraw()


func _draw() -> void:
	for spot in _spots:
		var at := Vector2(spot.x, spot.y)
		draw_circle(at, spot.z, MUD_COLOUR)
		draw_circle(at + Vector2(spot.z * 0.8, spot.z * 0.3), spot.z * 0.5, DRIP_COLOUR)
		draw_circle(at - Vector2(spot.z * 0.6, -spot.z * 0.5), spot.z * 0.35, MUD_COLOUR)

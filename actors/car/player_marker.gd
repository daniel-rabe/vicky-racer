extends Node2D
## A small white arrow floating above the player's car, always pointing down at it, so a
## child can always tell which car is theirs — including when their setup's car shares a
## colour with an opponent (Banana and Yellow), and on a crowded start grid.
##
## top_level so it stays upright while the car turns; placed in _physics_process so physics
## interpolation smooths it like the car itself.

const HEIGHT := 78.0          # px above the car's centre
const SIZE := Vector2(34, 26)  # arrow width, height
const FILL := Color.WHITE
const OUTLINE := Color(0.055, 0.078, 0.11)

@onready var car: Car = get_parent()


func _ready() -> void:
	top_level = true
	z_index = 10  # above bridges and every car
	_place()
	reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	_place()


func _place() -> void:
	global_position = car.global_position + Vector2(0.0, -HEIGHT)


func _draw() -> void:
	var points := PackedVector2Array([Vector2(-SIZE.x / 2.0, -SIZE.y / 2.0),
		Vector2(SIZE.x / 2.0, -SIZE.y / 2.0), Vector2(0.0, SIZE.y / 2.0)])
	draw_colored_polygon(points, FILL)
	points.append(points[0])
	draw_polyline(points, OUTLINE, 4.0, true)

class_name TunnelHill
extends Node2D
## The ring road's tunnel (docs/DESIGN.md §38) seen from above: a long grassy hill over the road
## with bushes on it, and the stone mouths at each end. It is drawn over the cars; while the
## player is inside it fades (`fade`), so the car can still be seen, with the lamps along the
## tunnel's roof showing.

const GRASS := Color(0.42, 0.68, 0.3)
const GRASS_DARK := Color(0.3, 0.52, 0.22)
const STONE := Color(0.62, 0.6, 0.58)

var size := Vector2(520.0, 1000.0)
## 1: the hill as it is; less: see-through, the player is inside.
var fade := 1.0:
	set(value):
		fade = value
		modulate.a = value
		queue_redraw()


func _draw() -> void:
	var half := size / 2.0
	var hill := Rect2(-half.x - 40.0, -half.y + 30.0, size.x + 80.0, size.y - 60.0)
	_round_rect(hill.grow(18.0), Color(0, 0, 0, 0.18), Vector2(16, 20))
	_round_rect(hill, GRASS_DARK, Vector2.ZERO)
	_round_rect(hill.grow(-40.0), GRASS, Vector2.ZERO)
	_round_rect(hill.grow(-140.0), GRASS.lightened(0.1), Vector2.ZERO)
	for k in 9:
		var at := Vector2(((k * 37) % 7 - 3) * 60.0, -half.y + 140.0 + k * 92.0)
		draw_circle(at + Vector2(6, 8), 34.0, Color(0, 0, 0, 0.15))
		draw_circle(at, 34.0, GRASS_DARK.darkened(0.1))
		draw_circle(at + Vector2(-8, -8), 20.0, GRASS.lightened(0.15))
	for end in [-1.0, 1.0]:
		var y: float = end * (half.y - 30.0)
		draw_rect(Rect2(-half.x + 30.0, y - 24.0, size.x - 60.0, 48.0), STONE)
		draw_rect(Rect2(-half.x + 30.0, y - 24.0, size.x - 60.0, 48.0), STONE.darkened(0.3), false, 4.0)
		for k in 7:
			var x := -half.x + 30.0 + (k + 0.5) * (size.x - 60.0) / 7.0
			draw_line(Vector2(x, y - 24.0), Vector2(x, y + 24.0), STONE.darkened(0.2), 3.0)
	if fade < 0.99:
		for k in 6:
			draw_circle(Vector2(0, -half.y + 150.0 + k * 140.0), 16.0, Color(1.0, 0.9, 0.5))


func _round_rect(rect: Rect2, colour: Color, offset: Vector2) -> void:
	var r := minf(rect.size.x, rect.size.y) * 0.45
	var points := PackedVector2Array()
	var inner := rect.grow(-r)
	var corners := [inner.end, Vector2(inner.position.x, inner.end.y), inner.position, Vector2(inner.end.x, inner.position.y)]
	for c in 4:
		for k in 9:
			points.append(corners[c] + Vector2.from_angle(c * PI / 2.0 + PI / 2.0 * k / 8.0) * r + offset)
	draw_colored_polygon(points, colour)

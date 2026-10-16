class_name LifeguardTower
extends Node2D
## The lifeguard's tower on Sunny Beach (docs/DESIGN.md §37), seen from above: four tall legs
## under a wooden platform with a red rail and a white cross on it, a little sunshade over the
## lifeguard's chair, a red flag on a pole, and a rescue ring hanging on the side.

const RED := Color(0.9, 0.22, 0.25)
const WOOD := Color(0.72, 0.53, 0.33)


func _draw() -> void:
	draw_rect(Rect2(-50, -50, 150, 150), Color(0, 0, 0, 0.2))
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		draw_rect(Rect2(corner * 68.0 - Vector2(10, 10), Vector2(20, 20)), WOOD.darkened(0.4))
	draw_rect(Rect2(-64, -64, 128, 128), RED)
	draw_rect(Rect2(-54, -54, 108, 108), WOOD)
	for k in 6:
		draw_line(Vector2(-54, -54 + k * 18.0 + 18.0), Vector2(54, -54 + k * 18.0 + 18.0), WOOD.darkened(0.2), 2.0)
	draw_rect(Rect2(-30, -10, 60, 20), Color.WHITE)  # the cross
	draw_rect(Rect2(-10, -30, 20, 60), Color.WHITE)
	# The sunshade over the chair, in the back corner.
	for k in 8:
		var points := PackedVector2Array([Vector2(-30, -30)])
		for s in 4:
			points.append(Vector2(-30, -30) + Vector2.from_angle(k * TAU / 8.0 + s * TAU / 24.0) * 46.0)
		draw_colored_polygon(points, Color(1.0, 0.82, 0.2) if k % 2 == 0 else Color.WHITE)
	draw_line(Vector2(58, -58), Vector2(58, -120), Color(0.35, 0.35, 0.38), 5.0)
	draw_colored_polygon(PackedVector2Array([Vector2(58, -120), Vector2(104, -106), Vector2(58, -92)]), RED)
	draw_arc(Vector2(86, 34), 22.0, 0.0, TAU, 24, Color(1.0, 0.5, 0.15), 12.0)
	for k in 4:
		var a := k * TAU / 4.0 + PI / 4.0
		draw_line(Vector2(86, 34) + Vector2.from_angle(a) * 16.0, Vector2(86, 34) + Vector2.from_angle(a) * 28.0, Color.WHITE, 5.0)

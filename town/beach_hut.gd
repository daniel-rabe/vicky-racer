class_name BeachHut
extends Node2D
## A beach hut on Sunny Beach (docs/DESIGN.md §37), seen from above: a pitched roof in stripes
## of its colour and white, its ridge across the middle, its door (the bottom edge) facing the
## boardwalk.

const SIZE := Vector2(170.0, 130.0)
const STRIPES := 6

var colour := Color(0.25, 0.55, 0.95)


func _draw() -> void:
	var half := SIZE / 2.0
	draw_rect(Rect2(-half + Vector2(10, 14), SIZE), Color(0, 0, 0, 0.2))
	var width := SIZE.x / STRIPES
	for k in STRIPES:
		var stripe := colour if k % 2 == 0 else Color(0.97, 0.96, 0.92)
		draw_rect(Rect2(-half.x + k * width, -half.y, width, half.y), stripe)  # the sunny side
		draw_rect(Rect2(-half.x + k * width, 0.0, width, half.y), stripe.darkened(0.18))
	draw_line(Vector2(-half.x, 0), Vector2(half.x, 0), colour.darkened(0.35), 6.0)  # the ridge
	draw_rect(Rect2(-half, SIZE), colour.darkened(0.35), false, 4.0)
	draw_rect(Rect2(-22.0, half.y - 2.0, 44.0, 14.0), Color(0.62, 0.45, 0.28))  # the step

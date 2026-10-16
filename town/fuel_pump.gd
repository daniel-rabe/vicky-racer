class_name FuelPump
extends Node2D
## The fuel station's pump island (docs/DESIGN.md §38) seen from above: a kerb round it, two
## pumps with their hoses, and on each a round gauge that fills up while a car stands at it
## (`fill`, one for each side), and a little roof over it all.

const RED := Color(0.9, 0.25, 0.25)

var size := Vector2(70.0, 160.0)
var fill: Array[float] = [0.0, 0.0]:
	set(value):
		fill = value
		queue_redraw()


func _draw() -> void:
	var half := size / 2.0
	draw_rect(Rect2(-half - Vector2(14, 14), size + Vector2(28, 28)), Color(0.85, 0.85, 0.82))
	for k in 2:
		var side := -1.0 if k == 0 else 1.0
		var at := Vector2(0, -38.0 + k * 76.0)
		draw_rect(Rect2(at - Vector2(26, 26) + Vector2(5, 6), Vector2(52, 52)), Color(0, 0, 0, 0.2))
		draw_rect(Rect2(at - Vector2(26, 26), Vector2(52, 52)), RED)
		draw_rect(Rect2(at - Vector2(26, 26), Vector2(52, 52)), RED.darkened(0.35), false, 3.0)
		# Its gauge: a dial with the needle going round as it fills.
		draw_circle(at, 17.0, Color.WHITE)
		draw_arc(at, 13.0, PI * 0.75, PI * 0.75 + PI * 1.5 * fill[k], 20, Color(0.25, 0.75, 0.3), 6.0)
		draw_line(at, at + Vector2.from_angle(PI * 0.75 + PI * 1.5 * fill[k]) * 14.0, Color(0.15, 0.15, 0.15), 3.0)
		# The hose, out to the side the car stands on.
		draw_line(at + Vector2(side * 26.0, 8.0), at + Vector2(side * 46.0, 22.0), Color(0.15, 0.15, 0.15), 6.0)
		draw_rect(Rect2(at + Vector2(side * 46.0 - 7.0, 16.0), Vector2(14, 12)), Color(0.25, 0.25, 0.28))

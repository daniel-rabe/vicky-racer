class_name SpeedSign
extends Node2D
## The ring road's speed sign (docs/DESIGN.md §38), seen from above and a little from the front:
## two legs, and a dark board showing the speed of the car going by in big glowing numbers, with
## a smiley; very fast says WOW! in orange.

const BOARD := Vector2(300.0, 150.0)
const FONT_SIZE := 88

## The number to show (-1: nothing going by), and whether it is a WOW.
var speed := -1:
	set(value):
		if value != speed:
			speed = value
			queue_redraw()
var wow := false:
	set(value):
		if value != wow:
			wow = value
			queue_redraw()


func _draw() -> void:
	var half := BOARD / 2.0
	for x in [-half.x + 40.0, half.x - 40.0]:
		draw_rect(Rect2(x - 8.0, half.y - 10.0, 16.0, 70.0), Color(0.45, 0.45, 0.5))
	draw_rect(Rect2(-half + Vector2(12, 16), BOARD), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(-half, BOARD), Color(0.12, 0.13, 0.16))
	draw_rect(Rect2(-half, BOARD), Color(0.95, 0.85, 0.2), false, 8.0)
	var font := ThemeDB.fallback_font
	var text := "--" if speed < 0 else ("WOW!" if wow else str(speed))
	var colour := Color(1.0, 0.55, 0.15) if wow else Color(0.4, 1.0, 0.5)
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	draw_string(font, Vector2(-width / 2.0 - 30.0, FONT_SIZE * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour)
	# The smiley.
	var face := Vector2(half.x - 44.0, 0)
	draw_circle(face, 26.0, colour)
	draw_circle(face + Vector2(-9, -7), 4.0, Color(0.12, 0.13, 0.16))
	draw_circle(face + Vector2(9, -7), 4.0, Color(0.12, 0.13, 0.16))
	draw_arc(face + Vector2(0, 2), 13.0, 0.3, PI - 0.3, 12, Color(0.12, 0.13, 0.16), 4.0)

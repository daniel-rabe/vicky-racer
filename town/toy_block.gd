class_name ToyBlock
extends Node2D
## A giant wooden letter block in toy town (docs/DESIGN.md §36), seen from above and a little
## from the front: its top with the letter on it, a darker front face, a soft shadow.

const SIZE := 150.0
const FONT_SIZE := 96

var letter := "A"
var colour := Color(0.95, 0.3, 0.35)


func _draw() -> void:
	var half := SIZE / 2.0
	draw_rect(Rect2(-half + 10.0, -half + 14.0, SIZE, SIZE + 26.0), Color(0, 0, 0, 0.22))
	draw_rect(Rect2(-half, half - 6.0, SIZE, 30.0), colour.darkened(0.35))  # the front face
	draw_rect(Rect2(-half, -half, SIZE, SIZE), colour)
	draw_rect(Rect2(-half + 12.0, -half + 12.0, SIZE - 24.0, SIZE - 24.0), colour.lightened(0.55))
	draw_rect(Rect2(-half, -half, SIZE, SIZE), colour.darkened(0.2), false, 6.0)
	var font := ThemeDB.fallback_font
	var size := font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	draw_string(font, Vector2(-size.x / 2.0, FONT_SIZE * 0.36), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, colour.darkened(0.25))

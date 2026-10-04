class_name CupCard
extends Button
## One cup on the select screen: its icon and name, its three tracks, and the best trophy
## won — or CONTINUE while it is running, or a padlock and which cup to win first.

signal chosen(config: CupConfig)

const SIZE := Vector2(640, 280)
const TROPHY_ART := {
	&"gold": preload("res://art/ui/cups/trophy_gold.png"),
	&"silver": preload("res://art/ui/cups/trophy_silver.png"),
	&"bronze": preload("res://art/ui/cups/trophy_bronze.png"),
	&"ribbon": preload("res://art/ui/cups/ribbon.png"),
}
const DARK := Color(0.055, 0.078, 0.11)
const YELLOW := Color(1, 0.824, 0.247)
const DIM := Color(0.75, 0.8, 0.86)

var config: CupConfig
var unlocked := true
## The cup that must be won to open this one.
var opened_by := ""


## `running_race`: the race the cup is on if it is the one in progress (1-based), else 0.
func setup(cup: CupConfig, is_unlocked: bool, trophy: StringName, running_race: int, previous: String) -> void:
	config = cup
	unlocked = is_unlocked
	opened_by = previous
	name = String(cup.id).to_pascal_case()
	custom_minimum_size = SIZE
	theme_type_variation = &"SettingsRow"
	var icon := TextureRect.new()
	icon.texture = cup.icon
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # before the size, or it keeps the art's size
	icon.position = Vector2(24, 40)
	icon.size = Vector2(180, 180)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(icon)
	_label(cup.display_name.to_upper(), 28, Color.WHITE, Vector2(228, 34))
	var tracks := PackedStringArray()
	for track in cup.tracks:
		tracks.append(track.display_name.to_upper())
	_label("\n".join(tracks), 18, DIM, Vector2(228, 90))
	var status := ""
	if not unlocked:
		status = "LOCKED\nWIN %s" % previous.to_upper()
	elif running_race > 0:
		status = "CONTINUE\nRACE %d OF %d" % [running_race, cup.tracks.size()]
	elif trophy == &"":
		status = "NEW!"
	_label(status, 20, YELLOW if unlocked else DIM, Vector2(228, 196))
	if trophy != &"":
		var cup_art := TextureRect.new()
		cup_art.texture = TROPHY_ART[trophy]
		cup_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		cup_art.position = Vector2(SIZE.x - 150, 90)
		cup_art.size = Vector2(130, 130)
		cup_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		cup_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cup_art)
	modulate = Color.WHITE if unlocked else Color(0.7, 0.7, 0.7)
	pressed.connect(func() -> void: chosen.emit(config))


func _draw() -> void:
	if not unlocked:
		var c := Vector2(SIZE.x - 85, 150)
		draw_rect(Rect2(c - Vector2(45, 10), Vector2(90, 70)), DARK)
		draw_rect(Rect2(c - Vector2(39, 4), Vector2(78, 58)), YELLOW)
		draw_arc(c - Vector2(0, 14), 28.0, PI, TAU, 24, DARK, 14.0)


func _label(text: String, font_size: int, colour: Color, at: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", DARK)
	label.add_theme_constant_override("outline_size", 6 if font_size >= 26 else 0)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label

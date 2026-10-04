class_name TrackCard
extends Button
## One track on the track-select screen: its shape (drawn from the racing line), its name,
## and the best lap, NEW! or — while it is locked — a padlock and which track opens it.

signal chosen(config: TrackConfig)

const SIZE := Vector2(380, 400)
const SHAPE_RECT := Rect2(24, 24, 332, 210)
const DARK := Color(0.055, 0.078, 0.11)
const YELLOW := Color(1, 0.824, 0.247)

var config: TrackConfig
var unlocked := true
## The track whose finish unlocks this one.
var opened_by := ""
var _line := PackedVector2Array()  # the racing line, fitted into SHAPE_RECT
var _colour := Color(0.36, 0.73, 0.29)
var _name: Label
var _info: Label
var _race_info := ""
var _race_colour := YELLOW


func setup(track_config: TrackConfig, is_unlocked: bool, best_lap: float, completed: bool, previous: String) -> void:
	config = track_config
	unlocked = is_unlocked
	opened_by = previous
	name = String(config.track_id).to_pascal_case()
	custom_minimum_size = SIZE
	theme_type_variation = &"SettingsRow"
	_read_track()
	_name = _label(config.display_name.to_upper(), 30, Color.WHITE, Vector2(0, 250))
	var info := "NEW!"
	if not unlocked:
		info = "LOCKED\nFINISH %s" % opened_by.to_upper()
	elif best_lap > 0.0:
		info = "BEST %s" % _format(best_lap)
	elif completed:
		info = ""
	_race_info = info
	_race_colour = YELLOW if unlocked else Color(0.75, 0.8, 0.86)
	_info = _label(info, 22, _race_colour, Vector2(0, 304))
	modulate = Color.WHITE if unlocked else Color(0.7, 0.7, 0.7)
	pressed.connect(func() -> void: chosen.emit(config))


## The track's shape and colours, read from its scene without adding it to the tree (so its
## road is never built — only the curve and the theme are needed).
func _read_track() -> void:
	var track: Track = config.track_scene.instantiate()
	if track.theme:
		_colour = track.theme.card_colour
	var curve: Curve2D = (track.get_node("RacingLine") as Path2D).curve
	var points := curve.get_baked_points()
	track.free()
	var bounds := Rect2(points[0], Vector2.ZERO)
	for p in points:
		bounds = bounds.expand(p)
	# Inset by the road's drawn width, so the road stays inside the coloured panel.
	var inner := SHAPE_RECT.size - Vector2(40, 40)
	var fit := minf(inner.x / bounds.size.x, inner.y / bounds.size.y)
	var origin := SHAPE_RECT.get_center() - bounds.size * fit / 2.0
	for i in range(0, points.size(), 4):
		_line.append(origin + (points[i] - bounds.position) * fit)
	_line.append(_line[0])


func _draw() -> void:
	draw_rect(SHAPE_RECT.grow(10), _colour)
	draw_polyline(_line, DARK, 26.0, true)
	draw_polyline(_line, Color(0.37, 0.4, 0.45), 18.0, true)
	if not unlocked:
		var c := SHAPE_RECT.get_center()
		draw_rect(Rect2(c - Vector2(45, 10), Vector2(90, 70)), DARK)
		draw_rect(Rect2(c - Vector2(39, 4), Vector2(78, 58)), YELLOW)
		draw_arc(c - Vector2(0, 14), 28.0, PI, TAU, 24, DARK, 14.0)


func _label(text: String, font_size: int, colour: Color, at: Vector2) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.size = Vector2(SIZE.x, 60)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", DARK)
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
	return label


## What the card says under the name: the race's best lap (as set up), or in time-trial mode
## the track's record — `record` 0 when there is none yet.
func show_mode(time_trial: bool, record: float) -> void:
	if not time_trial or not unlocked:
		_info.text = _race_info
		_info.add_theme_color_override("font_color", _race_colour)
		return
	_info.text = "RECORD %s" % _format(record) if record > 0.0 else "NO RECORD YET"
	_info.add_theme_color_override("font_color", Color(1, 0.84, 0.3))


static func _format(seconds: float) -> String:
	return "%d:%05.2f" % [int(seconds) / 60, fmod(seconds, 60.0)]

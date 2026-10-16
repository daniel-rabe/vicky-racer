class_name WorldMap
extends TownMinimap
## The big map (docs/DESIGN.md §28), from the pause menu's MAP: the whole island and its sea
## over the screen, with a picture for every race gate (a tick once its race is finished, a
## padlock while it is locked), the garage, the trophy house, the rocket pad and the harbour.
## The arrows move from picture to picture, its name shows underneath, and A / Enter chooses it:
## the map closes and an arrow at the screen's edge shows the way there (TownScreen.set_pin).
## B / Escape goes back to the pause menu.
##
## The places come as `places`: {"at", "name", "picture", "done", "locked"}. It runs while the
## game is paused. The name and the controls sit under the map, outside it.

signal chosen(place: Dictionary)
signal closed

const ICON := 44.0
const RING := Color(1, 0.824, 0.247)
const DONE := Color(0.18, 0.769, 0.42)

var places: Array = []
var selected := 0
var _name: Label
var _hints: Label
var _time := 0.0
## Golden stars found so far and how many there are (§32), shown in the map's top left corner.
var stars := Vector2i(0, 0)
var _stars: Label


func _ready() -> void:
	super()
	clip_contents = false  # the name and the controls hang below the map
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_name = Label.new()
	_name.name = "PlaceName"
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", 52)
	_name.add_theme_color_override("font_color", RING)
	_name.add_theme_color_override("font_outline_color", Color(0.055, 0.078, 0.11))
	_name.add_theme_constant_override("outline_size", 14)
	_name.anchor_left = 0.0
	_name.anchor_right = 1.0
	_name.anchor_top = 1.0
	_name.anchor_bottom = 1.0
	_name.offset_top = 16.0
	_name.offset_bottom = 86.0
	add_child(_name)
	_hints = Label.new()
	_hints.text = "ARROWS  CHOOSE     ENTER  SHOW THE WAY     ESC  BACK"
	_hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hints.add_theme_font_size_override("font_size", 24)
	_hints.add_theme_color_override("font_outline_color", Color(0.055, 0.078, 0.11))
	_hints.add_theme_constant_override("outline_size", 8)
	_hints.anchor_right = 1.0
	_hints.anchor_top = 1.0
	_hints.anchor_bottom = 1.0
	_hints.offset_top = 96.0
	_hints.offset_bottom = 136.0
	add_child(_hints)
	_stars = Label.new()
	_stars.name = "Stars"
	_stars.add_theme_font_size_override("font_size", 40)
	_stars.add_theme_color_override("font_color", RING)
	_stars.add_theme_color_override("font_outline_color", Color(0.055, 0.078, 0.11))
	_stars.add_theme_constant_override("outline_size", 12)
	_stars.offset_left = 78.0
	_stars.offset_top = 14.0
	_stars.offset_bottom = 70.0
	add_child(_stars)


## Open on `places`, the one nearest the player chosen first.
func open(town: Town, player: Car, traffic: Array[Car], with_places: Array) -> void:
	places = with_places
	setup(town, player, traffic)
	selected = 0
	var nearest := INF
	for i in places.size():
		var distance: float = player.global_position.distance_to(places[i]["at"])
		if distance < nearest:
			nearest = distance
			selected = i
	_show_name()
	_stars.text = "%d / %d" % [stars.x, stars.y] if stars.y > 0 else ""
	visible = true


## The whole island and every place round it, with a margin of sea.
func _fit() -> void:
	var area := Rect2(Island.outline(0.0)[0], Vector2.ZERO)
	for p in Island.outline(0.0):
		area = area.expand(p)
	for place: Dictionary in places:
		area = area.expand(place["at"])
	area = area.merge(Rect2(SnowIsland.CENTRE - SnowIsland.RADII, SnowIsland.RADII * 2.0))  # the snowy hill (§33)
	area = area.merge(Rect2(CandyIsland.CENTRE - CandyIsland.RADII, CandyIsland.RADII * 2.0))  # candy land (§34)
	area = area.merge(Rect2(JungleIsland.CENTRE - JungleIsland.RADII, JungleIsland.RADII * 2.0))  # the jungle (§35)
	area = area.merge(Rect2(ToyIsland.CENTRE - ToyIsland.RADII, ToyIsland.RADII * 2.0))  # toy town (§36)
	area = area.merge(Rect2(BeachIsland.CENTRE - BeachIsland.RADII, BeachIsland.RADII * 2.0))  # Sunny Beach (§37)
	area = area.grow(500.0)
	var room := size - Vector2(PADDING, PADDING) * 2.0
	_scale = minf(room.x / area.size.x, room.y / area.size.y)
	_origin = Vector2(PADDING, PADDING) + (room - area.size * _scale) / 2.0 - area.position * _scale
	_sand = _mapped(Island.outline(0.0))
	_grass = _mapped(Island.outline(-Island.BEACH))
	_islets.clear()
	for islet in _town.islets:
		_islets.append(_mapped(islet))
	_snow = _mapped(SnowIsland.outline(0.0))
	_candy = _mapped(CandyIsland.outline(0.0))
	_jungle = _mapped(JungleIsland.outline(0.0))
	_toys = _mapped(ToyIsland.outline(0.0))
	_beach = _mapped(BeachIsland.outline(0.0))


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or places.is_empty():
		return
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_hints.text = "STICK  CHOOSE     A  SHOW THE WAY     B  BACK"
	elif event is InputEventKey:
		_hints.text = "ARROWS  CHOOSE     ENTER  SHOW THE WAY     ESC  BACK"
	var step := Vector2.ZERO
	if event.is_action_pressed("ui_left"):
		step = Vector2.LEFT
	elif event.is_action_pressed("ui_right"):
		step = Vector2.RIGHT
	elif event.is_action_pressed("ui_up"):
		step = Vector2.UP
	elif event.is_action_pressed("ui_down"):
		step = Vector2.DOWN
	if step != Vector2.ZERO:
		_move(step)
	elif event.is_action_pressed("ui_accept") or event.is_action_pressed("race_start"):
		visible = false
		chosen.emit(places[selected])
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		visible = false
		closed.emit()
	else:
		return
	get_viewport().set_input_as_handled()


## To the nearest place in that direction (within 70° of it), if there is one.
func _move(direction: Vector2) -> void:
	if places.is_empty():
		return
	var from: Vector2 = places[selected]["at"]
	var best := -1
	var best_score := INF
	for i in places.size():
		if i == selected:
			continue
		var offset: Vector2 = places[i]["at"] - from
		if offset.length() < 1.0 or absf(offset.angle_to(direction)) > deg_to_rad(70.0):
			continue
		# Straight ahead counts as nearer than off to the side.
		var score := offset.length() * (1.0 + 2.0 * absf(offset.angle_to(direction)))
		if score < best_score:
			best_score = score
			best = i
	if best >= 0:
		selected = best
		_show_name()


func _show_name() -> void:
	if places.is_empty():
		_name.text = ""
		return
	var place: Dictionary = places[selected]
	_name.text = place["name"] + ("  (LOCKED)" if place.get("locked", false) else "")


func _draw() -> void:
	super()
	for i in places.size():
		if i != selected:
			_draw_place(places[i], false)
	if not places.is_empty():
		_draw_place(places[selected], true)
	if stars.y > 0:
		JobsBoard.JobIcon.draw_picture(self, null, Rect2(Vector2(18, 16), Vector2(52, 52)))


func _draw_place(place: Dictionary, chosen_one: bool) -> void:
	var at := _map(place["at"])
	var radius := ICON * (1.3 if chosen_one else 1.0) * 0.62
	if chosen_one:
		draw_circle(at, radius + 12.0 + 3.0 * sin(_time * 6.0), RING)
	draw_circle(at, radius + 4.0, Color(0.055, 0.078, 0.11))
	draw_circle(at, radius, Color.WHITE if not place.get("locked", false) else Color(0.7, 0.72, 0.76))
	var picture: Texture2D = place.get("picture")
	if picture:
		var size := Vector2(picture.get_size())
		var fit := radius * 1.6 / maxf(size.x, size.y)
		draw_texture_rect(picture, Rect2(at - size * fit / 2.0, size * fit), false,
			Color(1, 1, 1, 0.55) if place.get("locked", false) else Color.WHITE)
	if place.get("done", false):
		var badge := at + Vector2(radius * 0.75, -radius * 0.75)
		draw_circle(badge, 14.0, DONE)
		draw_polyline(PackedVector2Array([badge + Vector2(-7, 0), badge + Vector2(-2, 6), badge + Vector2(8, -6)]),
			Color.WHITE, 4.0, true)
	elif place.get("locked", false):
		draw_set_transform(at + Vector2(radius * 0.75, -radius * 0.75), 0.0, Vector2.ONE * 0.32)
		RaceGate.Padlock.draw_on(self)
		draw_set_transform(Vector2.ZERO)

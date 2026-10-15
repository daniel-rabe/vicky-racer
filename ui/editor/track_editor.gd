extends Control
## The track editor (docs/DESIGN.md §26): the child builds their own race track and races on it.
##
## The map in the middle is the real track, rebuilt after every change, so what is built is
## what is raced. The road is a loop through white dots: tap the map to add a dot (it joins
## the loop where it fits best), drag a dot to bend the road. The chequered dot is the start,
## and the yellow arrows show which way round the race goes. Where the road crosses itself,
## one pass becomes a bridge on its own.
##
## Left, the tools, as big pictures: ROAD, ERASE, the theme's props (trees, snowmen...),
## PUDDLE (the theme's sand, ice or mud), BOOST, and UNDO. Top, the themes, MY TRACKS and RACE!
##
## Every change is saved straight away (MyTracks), so there is nothing to forget. MY TRACKS
## shows every track here, starts a new one, and shares them: SHARE writes the track's
## .vrtrack file wherever the parent wants it (on the web the browser downloads it), and GET A
## TRACK reads one in (on the web through the browser's file picker). A file dropped on the
## window is read in too.
##
## Pointer only (mouse or touch); Escape goes back, Ctrl+Z undoes.

const BUILDER := preload("res://track/build/build_track.gd")
const BOOST_PAD := preload("res://art/tiles/boost_pad.png")
const CLICK := preload("res://art/sfx/ui_click.wav")
const SPARKLE := preload("res://art/sfx/sparkle.wav")
const SPLASH := preload("res://art/sfx/splash.wav")
const BOOST_SOUND := preload("res://art/sfx/boost.wav")
const BUMP := preload("res://art/sfx/wall_bump.wav")
const CHEER := preload("res://art/sfx/cheer.wav")
## Where the map is drawn, screen px.
const MAP_RECT := Rect2(300, 132, 1596, 924)
const DOT_RADIUS := 22.0
const DOT_GRAB := 40.0
const ARROW_EVERY := 900.0  # px of road between direction arrows
const UNDO_STEPS := 60
const BG := Color(0.078, 0.125, 0.18)
const INK := Color(0.055, 0.078, 0.11)
const YELLOW := Color(1, 0.824, 0.247)
const RED := Color(0.9, 0.22, 0.27)

enum Tool { ROAD, ERASE, PROP, PUDDLE, BOOST }

var spec: Dictionary
var path := ""
var _tool := Tool.ROAD
var _prop_kind := ""
var _undo: Array[Dictionary] = []
var _curve: Curve2D
var _track: Track
var _drag := -1
var _drag_moved := false
var _scale := 1.0
var _offset := Vector2.ZERO
var _refused_at := Vector2(-1000, -1000)
var _refused_time := 0.0
var _tool_buttons := {}  # Tool or prop kind -> Button
var _theme_buttons := {}  # theme id -> Button
var _sounds: AudioStreamPlayer
var _web_callback: JavaScriptObject

var _viewport: SubViewport
var _world: Node2D
var _map_area: Control
var _tools_box: GridContainer
var _name_label: Label
var _message: Label
var _gallery: Control
var _gallery_grid: GridContainer
var _file_dialog: FileDialog


func _ready() -> void:
	var map_px := Vector2(CustomTrack.MAP_TILES) * CustomTrack.TILE_PX
	_scale = minf(MAP_RECT.size.x / map_px.x, MAP_RECT.size.y / map_px.y)
	_offset = (MAP_RECT.size - map_px * _scale) / 2.0
	_sounds = AudioStreamPlayer.new()
	_sounds.bus = &"SFX"
	add_child(_sounds)
	_build_screen()
	get_window().files_dropped.connect(_on_files_dropped)
	var tracks := MyTracks.list()
	if tracks.is_empty():
		_open_new()
	else:
		_open(tracks[0]["path"])


func _exit_tree() -> void:
	if get_window().files_dropped.is_connected(_on_files_dropped):
		get_window().files_dropped.disconnect(_on_files_dropped)


# --- the screen -----------------------------------------------------------------------------

func _build_screen() -> void:
	var background := ColorRect.new()
	background.color = BG
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	# The real track, drawn in a viewport of its own so its bridges and props stay under the menus.
	var container := SubViewportContainer.new()
	container.position = MAP_RECT.position
	container.size = MAP_RECT.size
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(MAP_RECT.size)
	_viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_viewport.physics_object_picking = false
	container.add_child(_viewport)
	var backdrop := ColorRect.new()
	backdrop.color = INK
	backdrop.size = MAP_RECT.size
	_viewport.add_child(backdrop)
	_world = Node2D.new()
	_world.position = _offset
	_world.scale = Vector2(_scale, _scale)
	_viewport.add_child(_world)

	_map_area = Control.new()
	_map_area.name = "Map"
	_map_area.position = MAP_RECT.position
	_map_area.size = MAP_RECT.size
	_map_area.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_area.gui_input.connect(_on_map_input)
	_map_area.draw.connect(_draw_overlay)
	add_child(_map_area)

	var back := _button("BACK", Vector2(250, 92), &"NavButton")
	back.position = Vector2(24, 24)
	back.pressed.connect(_go_back)
	add_child(back)

	var themes := HBoxContainer.new()
	themes.position = Vector2(300, 24)
	themes.add_theme_constant_override("separation", 10)
	add_child(themes)
	for theme_id in CustomTrack.THEMES:
		var theme: TrackTheme = load("res://game/configs/themes/%s.tres" % theme_id)
		var button := Button.new()
		button.custom_minimum_size = Vector2(112, 92)
		button.tooltip_text = theme.display_name
		button.icon = _prop_texture(CustomTrack.props_of(theme_id)[0])
		button.expand_icon = true
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.add_theme_constant_override("icon_max_width", 70)
		button.focus_mode = Control.FOCUS_NONE
		button.set_meta(&"colour", theme.card_colour)
		button.pressed.connect(_set_theme.bind(theme_id))
		themes.add_child(button)
		_theme_buttons[theme_id] = button

	var mine := _button("MY TRACKS", Vector2(330, 92), &"NavButton")
	mine.position = Vector2(1180, 24)
	mine.pressed.connect(_show_gallery)
	add_child(mine)
	var race := _button("RACE!", Vector2(370, 92), &"RaceButton")
	race.position = Vector2(1526, 24)
	race.add_theme_font_size_override("font_size", 46)
	race.pressed.connect(_race)
	add_child(race)

	_name_label = Label.new()
	_name_label.position = Vector2(24, 140)
	_name_label.size = Vector2(250, 40)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 24)
	_name_label.add_theme_color_override("font_color", YELLOW)
	add_child(_name_label)
	_tools_box = GridContainer.new()
	_tools_box.columns = 2
	_tools_box.position = Vector2(24, 192)
	_tools_box.add_theme_constant_override("h_separation", 10)
	_tools_box.add_theme_constant_override("v_separation", 10)
	add_child(_tools_box)

	_message = Label.new()
	_message.position = Vector2(300, 980)
	_message.size = Vector2(MAP_RECT.size.x, 60)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_size_override("font_size", 34)
	_message.add_theme_color_override("font_outline_color", INK)
	_message.add_theme_constant_override("outline_size", 12)
	_message.modulate.a = 0.0
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_message)
	_build_gallery()


func _button(text: String, size: Vector2, variation: StringName) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = size
	button.size = size
	button.theme_type_variation = variation
	button.focus_mode = Control.FOCUS_NONE
	return button


## The tools for this theme: its props differ, and so does the puddle's picture.
func _build_tools() -> void:
	for child in _tools_box.get_children():
		child.queue_free()
	_tool_buttons.clear()
	_add_tool(Tool.ROAD, "ROAD", null, _draw_road_icon)
	_add_tool(Tool.ERASE, "ERASE", null, _draw_eraser_icon)
	for kind: String in CustomTrack.props_of(StringName(spec["theme"])):
		_add_tool(Tool.PROP, "", _prop_texture(kind), Callable(), kind)
	_add_tool(Tool.PUDDLE, "PUDDLE", _patch_texture(), Callable())
	_add_tool(Tool.BOOST, "BOOST", BOOST_PAD, Callable())
	var undo := _tool_tile("UNDO", null, _draw_undo_icon)
	undo.pressed.connect(_undo_last)
	_tools_box.add_child(undo)
	if _tool == Tool.PROP and _prop_kind not in CustomTrack.props_of(StringName(spec["theme"])):
		_prop_kind = CustomTrack.props_of(StringName(spec["theme"]))[0]
	_show_tool()


func _add_tool(tool: Tool, text: String, picture: Texture2D, icon: Callable, kind := "") -> void:
	var button := _tool_tile(text, picture, icon)
	button.pressed.connect(func() -> void:
		_tool = tool
		_prop_kind = kind
		_play(CLICK, -4.0)
		_show_tool())
	_tools_box.add_child(button)
	_tool_buttons[kind if kind != "" else tool] = button


## A square picture button with a small word under the picture (for the grown-ups).
func _tool_tile(text: String, picture: Texture2D, icon: Callable) -> Button:
	var button := Button.new()
	button.custom_minimum_size = Vector2(120, 120)
	button.focus_mode = Control.FOCUS_NONE
	button.theme_type_variation = &"NavButton"
	var art := Control.new()
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art.position = Vector2(14, 8)
	art.size = Vector2(92, 80 if text != "" else 104)
	button.add_child(art)
	if picture:
		var rect := TextureRect.new()
		rect.texture = picture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.add_child(rect)
	elif icon.is_valid():
		art.draw.connect(icon.bind(art))
	if text != "":
		var label := Label.new()
		label.text = text
		label.add_theme_font_size_override("font_size", 16)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.position = Vector2(0, 90)
		label.size = Vector2(120, 24)
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(label)
	return button


func _show_tool() -> void:
	var chosen: Variant = _prop_kind if _tool == Tool.PROP else _tool
	for key: Variant in _tool_buttons:
		var on: bool = typeof(key) == typeof(chosen) and key == chosen
		(_tool_buttons[key] as Button).theme_type_variation = &"RaceButton" if on else &"NavButton"
	_map_area.queue_redraw()


func _show_theme() -> void:
	for theme_id: StringName in _theme_buttons:
		var button: Button = _theme_buttons[theme_id]
		var box := StyleBoxFlat.new()
		box.bg_color = button.get_meta(&"colour")
		box.set_corner_radius_all(22)
		box.set_border_width_all(8 if theme_id == StringName(spec["theme"]) else 4)
		box.border_color = YELLOW if theme_id == StringName(spec["theme"]) else INK
		for state in ["normal", "hover", "pressed"]:
			button.add_theme_stylebox_override(state, box)


static func _prop_texture(kind: String) -> Texture2D:
	var first: Variant = BUILDER.PROPS[kind][0]
	return load(first[0] if first is Array else first)


## The theme's patch (sand, ice, mud...): its all-patch ground tile.
func _patch_texture() -> Texture2D:
	var theme: TrackTheme = load("res://game/configs/themes/%s.tres" % spec["theme"])
	var source := theme.ground_tiles.get_source(0) as TileSetAtlasSource
	var atlas := AtlasTexture.new()
	atlas.atlas = source.texture
	atlas.region = source.get_tile_texture_region(Vector2i(3, 3))  # all four corners patch
	return atlas


# --- icons, drawn ---------------------------------------------------------------------------

func _draw_road_icon(art: Control) -> void:
	var pts := PackedVector2Array()
	for i in 13:
		var t := i / 12.0
		pts.append(Vector2(8 + t * 76, 40 + sin(t * TAU) * 22))
	art.draw_polyline(pts, INK, 30, true)
	art.draw_polyline(pts, Color(0.42, 0.45, 0.5), 22, true)
	for i in range(0, 12, 3):
		art.draw_line(pts[i], pts[i + 1], Color.WHITE, 3)
	for p in [pts[0], pts[6], pts[12]]:
		art.draw_circle(p, 11, INK)
		art.draw_circle(p, 8, Color.WHITE)


func _draw_eraser_icon(art: Control) -> void:
	art.draw_set_transform(Vector2(46, 42), -0.6)
	art.draw_rect(Rect2(-34, -17, 68, 34), INK)
	art.draw_rect(Rect2(-31, -14, 36, 28), Color(1, 0.55, 0.7))
	art.draw_rect(Rect2(5, -14, 26, 28), Color(0.35, 0.6, 1.0))
	art.draw_set_transform(Vector2.ZERO)


func _draw_undo_icon(art: Control) -> void:
	var pts := PackedVector2Array()
	for i in 15:
		var a := lerpf(PI * 1.05, PI * 2.25, i / 14.0)
		pts.append(Vector2(48, 46) + Vector2(cos(a), sin(a)) * 26)
	art.draw_polyline(pts, INK, 16, true)
	art.draw_polyline(pts, YELLOW, 9, true)
	var tip := pts[0]
	art.draw_colored_polygon(PackedVector2Array([tip + Vector2(-16, -6), tip + Vector2(14, -8), tip + Vector2(-2, 18)]), YELLOW)


# --- the map --------------------------------------------------------------------------------

## Screen px in the map area -> tiles.
func _to_tiles(local: Vector2) -> Vector2:
	return (local - _offset) / (_scale * CustomTrack.TILE_PX)


func _to_local(tiles: Vector2) -> Vector2:
	return tiles * CustomTrack.TILE_PX * _scale + _offset


func _dot(i: int) -> Vector2:
	return Vector2(spec["road"][i][0], spec["road"][i][1])


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event.position)
		elif _drag >= 0:
			_drag = -1
			_commit()
	elif event is InputEventMouseMotion and _drag >= 0:
		spec["road"][_drag] = CustomTrack._round2(CustomTrack.clamp_to_map(_to_tiles(event.position)))
		_drag_moved = true
		_curve = CustomTrack.curve_of(spec["road"])
		if _track:
			_track.visible = false  # the preview line shows the road while it moves
		_map_area.queue_redraw()


func _press(local: Vector2) -> void:
	var at := CustomTrack.clamp_to_map(_to_tiles(local))
	var px := at * CustomTrack.TILE_PX
	match _tool:
		Tool.ROAD:
			var hit := _dot_at(local)
			_remember()
			if hit < 0:
				if spec["road"].size() >= CustomTrack.MAX_DOTS:
					_undo.pop_back()
					_refuse(local)
					return
				hit = CustomTrack.insert_index(spec["road"], at)
				spec["road"].insert(hit, CustomTrack._round2(at))
				_curve = CustomTrack.curve_of(spec["road"])
			_play(CLICK)
			_drag = hit
			_drag_moved = false
			_map_area.queue_redraw()
		Tool.ERASE:
			_erase(local)
		Tool.PROP:
			var radius: float = BUILDER.PROPS[_prop_kind][1]
			if CustomTrack.on_road(_curve, px, radius) or _prop_count() >= CustomTrack.MAX_PROPS:
				_refuse(local)
				return
			_remember()
			var spots: Array = spec["props"].get(_prop_kind, [])
			spots.append(CustomTrack._round2(at))
			spec["props"][_prop_kind] = spots
			_play(SPARKLE, -6.0)
			_commit()
		Tool.PUDDLE:
			if spec["puddles"].size() >= CustomTrack.MAX_PUDDLES:
				_refuse(local)
				return
			_remember()
			spec["puddles"].append(CustomTrack._round2(at))
			_play(SPLASH, -6.0)
			_commit()
		Tool.BOOST:
			var near := _curve.get_closest_point(px).distance_to(px) < CustomTrack.ROAD_TILES * CustomTrack.TILE_PX
			if not near or spec["boosts"].size() >= CustomTrack.MAX_BOOSTS:
				_refuse(local)
				return
			_remember()
			spec["boosts"].append(CustomTrack._round2(at))
			_play(BOOST_SOUND, -6.0)
			_commit()


func _dot_at(local: Vector2) -> int:
	var best := -1
	var best_d := DOT_GRAB
	for i in spec["road"].size():
		var d := _to_local(_dot(i)).distance_to(local)
		if d < best_d:
			best_d = d
			best = i
	return best


func _prop_count() -> int:
	var n := 0
	for kind: String in spec["props"]:
		n += spec["props"][kind].size()
	return n


## The nearest thing under the finger goes: a prop, a boost pad, a dot (a loop keeps four), a puddle.
func _erase(local: Vector2) -> void:
	var at := _to_tiles(local)
	for kind: String in spec["props"]:
		var spots: Array = spec["props"][kind]
		var reach: float = maxf(BUILDER.PROPS[kind][1] / CustomTrack.TILE_PX, 0.6)
		for i in range(spots.size() - 1, -1, -1):
			if Vector2(spots[i][0], spots[i][1]).distance_to(at) < reach:
				_remember()
				spots.remove_at(i)
				if spots.is_empty():
					spec["props"].erase(kind)
				_erased()
				return
	for i in range(spec["boosts"].size() - 1, -1, -1):
		var on_road := _curve.get_closest_point(Vector2(spec["boosts"][i][0], spec["boosts"][i][1]) * CustomTrack.TILE_PX)
		if (on_road / CustomTrack.TILE_PX).distance_to(at) < 1.5:
			_remember()
			spec["boosts"].remove_at(i)
			_erased()
			return
	var dot := _dot_at(local)
	if dot >= 0:
		if spec["road"].size() <= CustomTrack.MIN_DOTS:
			_refuse(local)
			return
		_remember()
		spec["road"].remove_at(dot)
		_erased()
		return
	for i in range(spec["puddles"].size() - 1, -1, -1):
		var d: Vector2 = (at - Vector2(spec["puddles"][i][0], spec["puddles"][i][1])) / CustomTrack.PUDDLE_RADII
		if d.length() < 1.0:
			_remember()
			spec["puddles"].remove_at(i)
			_erased()
			return


func _erased() -> void:
	_play(CLICK)
	_commit()


func _refuse(local: Vector2) -> void:
	_refused_at = local
	_refused_time = 0.6
	_play(BUMP, -4.0)
	_map_area.queue_redraw()


func _process(delta: float) -> void:
	if _refused_time > 0.0:
		_refused_time = maxf(_refused_time - delta, 0.0)
		_map_area.queue_redraw()


func _draw_overlay() -> void:
	if _curve == null:
		return
	var length := _curve.get_baked_length()
	if _drag >= 0 and _drag_moved:  # the road, roughly, while a dot moves
		var pts := PackedVector2Array()
		var steps := int(length / 40.0)
		for i in steps + 1:
			pts.append(_to_local(_curve.sample_baked(length * i / steps) / CustomTrack.TILE_PX))
		var width := CustomTrack.ROAD_TILES * CustomTrack.TILE_PX * _scale
		_map_area.draw_polyline(pts, INK, width + 6, true)
		_map_area.draw_polyline(pts, Color(0.36, 0.38, 0.42), width, true)
	var road_tool := _tool in [Tool.ROAD, Tool.ERASE]
	# Which way round: yellow arrows along the road.
	var along := ARROW_EVERY * 0.5
	while along < length:
		var p := _to_local(_curve.sample_baked(along) / CustomTrack.TILE_PX)
		var dir := (_curve.sample_baked(minf(along + 10.0, length)) - _curve.sample_baked(along)).normalized()
		var n := Vector2(-dir.y, dir.x)
		var tri := PackedVector2Array([p + dir * 14, p - dir * 10 + n * 12, p - dir * 10 - n * 12])
		_map_area.draw_colored_polygon(tri, YELLOW)
		_map_area.draw_polyline(PackedVector2Array([tri[0], tri[1], tri[2], tri[0]]), INK, 3)
		along += ARROW_EVERY
	var radius := DOT_RADIUS if road_tool else DOT_RADIUS * 0.6
	for i in spec["road"].size():
		var p := _to_local(_dot(i))
		_map_area.draw_circle(p, radius + 4, INK)
		if i == 0:  # the start: chequered
			_map_area.draw_circle(p, radius, Color.WHITE)
			var s := radius * 0.6
			for cx in 2:
				for cy in 2:
					if (cx + cy) % 2 == 0:
						_map_area.draw_rect(Rect2(p + Vector2((cx - 1) * s, (cy - 1) * s), Vector2(s, s)), INK)
		else:
			_map_area.draw_circle(p, radius, YELLOW if i == _drag else Color.WHITE)
	if _refused_time > 0.0:
		var a := _refused_time / 0.6
		_map_area.draw_arc(_refused_at, 30 + (1.0 - a) * 30, 0, TAU, 32, Color(RED, a), 8)
		_map_area.draw_line(_refused_at + Vector2(-18, -18), _refused_at + Vector2(18, 18), Color(RED, a), 8)
		_map_area.draw_line(_refused_at + Vector2(18, -18), _refused_at + Vector2(-18, 18), Color(RED, a), 8)


# --- changes --------------------------------------------------------------------------------

func _remember() -> void:
	_undo.append(spec.duplicate(true))
	if _undo.size() > UNDO_STEPS:
		_undo.pop_front()


func _undo_last() -> void:
	if _undo.is_empty():
		_play(BUMP, -6.0)
		return
	var theme_before: String = spec["theme"]
	spec = _undo.pop_back()
	_play(CLICK)
	if spec["theme"] != theme_before:
		_build_tools()
		_show_theme()
	_commit()


func _set_theme(theme_id: StringName) -> void:
	if theme_id == StringName(spec["theme"]):
		return
	_remember()
	spec = CustomTrack.with_theme(spec, theme_id)
	_play(SPARKLE, -6.0)
	_build_tools()
	_show_theme()
	_commit()


## After every change: trees the road now runs over make way, the track is built again, saved.
func _commit() -> void:
	_curve = CustomTrack.curve_of(spec["road"])
	for kind: String in spec["props"].keys():
		var radius: float = BUILDER.PROPS[kind][1]
		var spots: Array = spec["props"][kind].filter(func(p: Array) -> bool:
			return not CustomTrack.on_road(_curve, Vector2(p[0], p[1]) * CustomTrack.TILE_PX, radius))
		if spots.is_empty():
			spec["props"].erase(kind)
		else:
			spec["props"][kind] = spots
	_rebuild()
	if path != "":
		MyTracks.save(spec, path)


func _rebuild() -> void:
	if _track:
		_track.queue_free()
	_track = CustomTrack.make_track(spec)
	_world.add_child(_track)
	_name_label.text = spec["name"]
	_map_area.queue_redraw()


func _open(track_path: String) -> void:
	var loaded := CustomTrack.from_json(FileAccess.get_file_as_string(track_path))
	if loaded.is_empty():
		return
	path = track_path
	spec = loaded
	_undo.clear()
	_build_tools()
	_show_theme()
	_commit()


func _open_new() -> void:
	if MyTracks.full():
		_say("TOO MANY TRACKS! ERASE ONE FIRST")
		return
	var theme: StringName = StringName(spec["theme"]) if not spec.is_empty() else &"meadow"
	var fresh := CustomTrack.default_spec(theme)
	_open(MyTracks.create(fresh))
	_play(SPARKLE)


func _race() -> void:
	_commit()
	_play(CHEER, -8.0)
	EventSystem.PRO_custom_race_requested.emit(CustomTrack.make_config(spec))
	EventSystem.UI_screen_requested.emit(&"race")


func _go_back() -> void:
	EventSystem.UI_screen_requested.emit(&"tracks")


func _play(stream: AudioStream, volume_db := 0.0) -> void:
	if not SoundManager.audible():
		return
	_sounds.stream = stream
	_sounds.volume_db = volume_db
	_sounds.play()


func _say(text: String) -> void:
	_message.text = text
	var tween := create_tween()
	tween.tween_property(_message, "modulate:a", 1.0, 0.15)
	tween.tween_interval(2.2)
	tween.tween_property(_message, "modulate:a", 0.0, 0.4)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _gallery.visible:
			_gallery.visible = false
		else:
			_go_back()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_Z and event.ctrl_pressed:
		_undo_last()
		get_viewport().set_input_as_handled()


# --- my tracks: open, new, share, get -------------------------------------------------------

func _build_gallery() -> void:
	_gallery = ColorRect.new()
	(_gallery as ColorRect).color = Color(BG, 0.97)
	_gallery.set_anchors_preset(Control.PRESET_FULL_RECT)
	_gallery.visible = false
	add_child(_gallery)
	var title := Label.new()
	title.text = "MY TRACKS"
	title.position = Vector2(48, 44)
	title.add_theme_font_size_override("font_size", 56)
	_gallery.add_child(title)
	var close := _button("CLOSE", Vector2(250, 92), &"NavButton")
	close.position = Vector2(1646, 32)
	close.pressed.connect(func() -> void: _gallery.visible = false)
	_gallery.add_child(close)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(40, 150)
	scroll.size = Vector2(1840, 770)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_gallery.add_child(scroll)
	_gallery_grid = GridContainer.new()
	_gallery_grid.columns = 5
	_gallery_grid.add_theme_constant_override("h_separation", 20)
	_gallery_grid.add_theme_constant_override("v_separation", 20)
	scroll.add_child(_gallery_grid)
	var share := _button("SHARE THIS TRACK", Vector2(640, 100), &"RaceButton")
	share.position = Vector2(280, 950)
	share.pressed.connect(_share)
	_gallery.add_child(share)
	var get_one := _button("GET A TRACK", Vector2(640, 100), &"NavButton")
	get_one.position = Vector2(1000, 950)
	get_one.pressed.connect(_get_track)
	_gallery.add_child(get_one)
	_file_dialog = FileDialog.new()
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.use_native_dialog = true
	_file_dialog.filters = PackedStringArray(["*.%s ; Vicky Racer track" % CustomTrack.EXTENSION])
	_file_dialog.file_selected.connect(_on_file_chosen)
	add_child(_file_dialog)


func _show_gallery() -> void:
	for child in _gallery_grid.get_children():
		child.queue_free()
	var new_card := _card_frame(Color(0.169, 0.227, 0.306))
	new_card.draw.connect(func() -> void:
		var c := new_card.size / 2.0 - Vector2(0, 14)
		new_card.draw_rect(Rect2(c - Vector2(14, 60), Vector2(28, 120)), YELLOW)
		new_card.draw_rect(Rect2(c - Vector2(60, 14), Vector2(120, 28)), YELLOW))
	_card_label(new_card, "NEW TRACK")
	new_card.pressed.connect(func() -> void:
		_gallery.visible = false
		_open_new())
	_gallery_grid.add_child(new_card)
	for entry: Dictionary in MyTracks.list():
		_gallery_grid.add_child(_track_card(entry))
	_gallery.visible = true


func _card_frame(colour: Color) -> Button:
	var card := Button.new()
	card.custom_minimum_size = Vector2(348, 250)
	card.focus_mode = Control.FOCUS_NONE
	var box := StyleBoxFlat.new()
	box.bg_color = colour
	box.set_corner_radius_all(24)
	box.set_border_width_all(6)
	box.border_color = INK
	var hover := box.duplicate()
	hover.border_color = YELLOW
	card.add_theme_stylebox_override("normal", box)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)
	return card


func _card_label(card: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_outline_color", INK)
	label.add_theme_constant_override("outline_size", 8)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = Vector2(0, 208)
	label.size = Vector2(348, 32)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(label)


## A track's card: its road drawn small on its theme's colour, and its name. The open one has a
## yellow rim; the little cross erases it, after a second tap.
func _track_card(entry: Dictionary) -> Button:
	var track_spec: Dictionary = entry["spec"]
	var theme: TrackTheme = load("res://game/configs/themes/%s.tres" % track_spec["theme"])
	var card := _card_frame(theme.card_colour)
	if entry["path"] == path:
		var open_box: StyleBoxFlat = card.get_theme_stylebox("normal").duplicate()
		open_box.border_color = YELLOW
		open_box.set_border_width_all(10)
		card.add_theme_stylebox_override("normal", open_box)
	var curve := CustomTrack.curve_of(track_spec["road"])
	var length := curve.get_baked_length()
	var map := Vector2(CustomTrack.MAP_TILES) * CustomTrack.TILE_PX
	var fit := minf(300.0 / map.x, 180.0 / map.y)
	var corner := Vector2((348 - map.x * fit) / 2.0, 20)
	var pts := PackedVector2Array()
	for i in 121:
		pts.append(corner + curve.sample_baked(length * i / 120.0) * fit)
	card.draw.connect(func() -> void:
		card.draw_polyline(pts, INK, 16, true)
		card.draw_polyline(pts, Color(0.42, 0.45, 0.5), 11, true)
		card.draw_circle(pts[0], 9, Color.WHITE)
		card.draw_circle(pts[0], 5, INK))
	_card_label(card, track_spec["name"])
	card.pressed.connect(func() -> void:
		_gallery.visible = false
		_open(entry["path"])
		_play(CLICK))
	var erase := Button.new()
	erase.text = "X"
	erase.focus_mode = Control.FOCUS_NONE
	erase.custom_minimum_size = Vector2(60, 60)
	erase.position = Vector2(280, 8)
	erase.add_theme_font_size_override("font_size", 26)
	erase.pressed.connect(func() -> void:
		if erase.text == "X":
			erase.text = "SURE?"
			erase.position.x = 196
			erase.add_theme_color_override("font_color", RED)
			return
		MyTracks.remove(entry["path"])
		_play(BUMP, -6.0)
		if entry["path"] == path:
			var rest := MyTracks.list()
			if rest.is_empty():
				path = ""
				_open_new()
			else:
				_open(rest[0]["path"])
		_show_gallery())
	card.add_child(erase)
	return card


## SHARE: the open track's file, where the grown-up wants it (the browser downloads it).
func _share() -> void:
	if spec.is_empty():
		return
	var file_name := MyTracks.share_name(spec)
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(CustomTrack.to_json(spec).to_utf8_buffer(), file_name, "application/json")
		_say("SAVED %s" % file_name.to_upper())
		return
	_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	_file_dialog.title = "Share this track"
	_file_dialog.current_file = file_name
	_file_dialog.popup_centered_ratio(0.7)


## GET A TRACK: somebody's file, read in as a new track here.
func _get_track() -> void:
	if OS.has_feature("web"):
		_pick_file_on_web()
		return
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.title = "Get a track"
	_file_dialog.popup_centered_ratio(0.7)


func _on_file_chosen(chosen: String) -> void:
	if _file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		if not chosen.ends_with("." + CustomTrack.EXTENSION):
			chosen += "." + CustomTrack.EXTENSION
		var error := MyTracks.save(spec, chosen)
		_say("SAVED %s" % chosen.get_file().to_upper() if error == OK else "COULD NOT SAVE THERE")
	else:
		_import_text(FileAccess.get_file_as_string(chosen) if FileAccess.file_exists(chosen) else "")


func _on_files_dropped(files: PackedStringArray) -> void:
	for file in files:
		_import_text(FileAccess.get_file_as_string(file))


func _import_text(text: String) -> void:
	var new_path := MyTracks.import_text(text)
	if new_path == "":
		_say("TOO MANY TRACKS! ERASE ONE FIRST" if MyTracks.full() else "THAT IS NOT A TRACK")
		_play(BUMP)
		return
	_gallery.visible = false
	_open(new_path)
	_play(CHEER, -8.0)
	_say("NEW TRACK: %s!" % spec["name"])


## The browser's own file picker, reading the chosen file as text and handing it back here.
func _pick_file_on_web() -> void:
	_web_callback = JavaScriptBridge.create_callback(func(args: Array) -> void:
		_import_text(str(args[0]) if not args.is_empty() else ""))
	JavaScriptBridge.get_interface("window").vickyTrackPicked = _web_callback
	JavaScriptBridge.eval("""(function () {
		var input = document.createElement('input');
		input.type = 'file';
		input.accept = '.%s,application/json';
		input.onchange = function () {
			var file = input.files[0];
			if (!file) return;
			if (file.size > %d) { window.vickyTrackPicked(''); return; }
			file.text().then(function (text) { window.vickyTrackPicked(text); });
		};
		input.click();
	})();""" % [CustomTrack.EXTENSION, CustomTrack.MAX_FILE_BYTES], true)

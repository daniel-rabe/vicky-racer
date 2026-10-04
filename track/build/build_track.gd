extends Node
## Builds track scenes from the layouts written by tools/layouts/track_layout.py, so the
## layout that was reviewed is exactly the track that is driven. Run headless:
##   Godot_console.exe --path . --headless res://track/build/build_track.tscn -- --ids=track_01,track_02
## Each id reads docs/mockups/<id>_points.json and writes track/tracks/<id>.tscn, dressed in
## the layout's theme (game/configs/themes/<theme>.tres). Default: every track.
##
## The result is an ordinary scene: open it, edit the RacingLine curve (the road follows),
## or paint more sand with the Grass/Sand terrain. Rebuilding overwrites those edits.

const TRACK_SCRIPT := preload("res://track/track.gd")
const GROUND_TILES := preload("res://track/ground_tiles.tres")
const TYRES := preload("res://art/props/tyre_stack.png")
const BOOST_PAD := preload("res://art/tiles/boost_pad.png")
const ALL_TRACKS := "track_01,track_02,track_03,track_04"
## Prop kind (as in the layout) -> texture and collision radius. Radii are smaller than the
## pictures: clipping a palm frond or a parasol's edge should not stop a car.
const PROPS := {
	"tree": ["res://art/props/tree.png", 56.0],
	"tyre_stack": ["res://art/props/tyre_stack.png", 34.0],
	"palm_tree": ["res://art/props/beach/palm_tree.png", 38.0],
	"parasol": ["res://art/props/beach/parasol.png", 30.0],
	"beach_ball": ["res://art/props/beach/beach_ball.png", 28.0],
	"pine_tree": ["res://art/props/snow/pine_tree.png", 46.0],
	"snowman": ["res://art/props/snow/snowman.png", 40.0],
	"toy_house": ["res://art/props/town/toy_house.png", 92.0],
	"traffic_cone": ["res://art/props/town/traffic_cone.png", 22.0],
}
const BOOST_PAD_SIZE := Vector2(150, 210)
const WALL_THICKNESS := 64.0
const TYRE_SPACING := 76.0
const GATE_DEPTH := 24.0      # finish line / checkpoint trigger thickness along the road
const KERB_WIDTH := 38.0
const TL := 8
const TR := 4
const BL := 2
const BR := 1

var _root: Node2D


func _ready() -> void:
	var ids := ALL_TRACKS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--ids="):
			ids = arg.get_slice("=", 1)
	var failed := false
	for id in ids.split(","):
		var layout := "res://docs/mockups/%s_points.json" % id
		var out := "res://track/tracks/%s.tscn" % id
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(layout))
		var error := _build(data, StringName(id), out)
		print("built %s -> %s (%s)" % [layout, out, error_string(error)])
		failed = failed or error != OK
	get_tree().quit(1 if failed else 0)


func _build(data: Dictionary, id: StringName, out_path: String) -> Error:
	var tile: float = data["tile_px"]
	var map_tiles := Vector2i(data["map_tiles"][0], data["map_tiles"][1])
	_root = Node2D.new()
	_root.name = String(id).to_pascal_case()
	_root.set_script(TRACK_SCRIPT)
	_root.set("track_id", id)
	_root.set("map_size", Vector2(map_tiles) * tile)
	_root.set("road_half_width", float(data["road_tiles"]) * tile / 2.0)
	var theme: TrackTheme = load("res://game/configs/themes/%s.tres" % data.get("theme", "meadow"))
	_root.set("theme", theme)
	var spans := PackedVector2Array()
	for span: Array in data.get("ice_spans", []):
		spans.append(Vector2(span[0], span[1]))
	_root.set("ice_spans", spans)

	_add(_ground(data, map_tiles, theme))
	_add(_named(Node2D.new(), "Road"))
	var line := _racing_line(data["control_points_tiles"], tile)
	_add(line)
	_add(_start_grid(data["grid_slots_px"], line.curve))
	var road_width := float(data["road_tiles"]) * tile + 2.0 * KERB_WIDTH + 40.0
	_add(_gate("FinishLine", data["finish_line_px"], road_width))
	_add(_gate("Checkpoint", data["checkpoint_px"], road_width))
	_add(_walls(Vector2(map_tiles) * tile, theme))
	_add(_props(data, tile))
	if not data.get("boost_pads", []).is_empty():
		_add(_boost_pads(data["boost_pads"], line.curve))

	var packed := PackedScene.new()
	var error := packed.pack(_root)
	if error == OK:
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		error = ResourceSaver.save(packed, out_path)
	_root.free()
	return error


func _add(node: Node) -> void:
	_root.add_child(node)
	_own(node)


func _own(node: Node) -> void:
	node.owner = _root
	for child in node.get_children():
		_own(child)


func _named(node: Node, node_name: String) -> Node:
	node.name = node_name
	return node


func _ground(data: Dictionary, map_tiles: Vector2i, theme: TrackTheme) -> TileMapLayer:
	var ground: TileMapLayer = _named(TileMapLayer.new(), "Ground")
	ground.tile_set = theme.ground_tiles if theme else GROUND_TILES
	# A tile corner (x, y) is patch (sand, ice...) when it lies inside one of the layout's
	# patch ellipses.
	var traps: Array = data.get("patches_tiles", data.get("sand_traps_tiles", []))
	var sand := func(x: int, y: int) -> bool:
		for trap: Array in traps:
			var d := Vector2((x - trap[0][0]) / trap[1][0], (y - trap[0][1]) / trap[1][1])
			if d.length_squared() < 1.0:
				return true
		return false
	for y in map_tiles.y:
		for x in map_tiles.x:
			var c := (TL if sand.call(x, y) else 0) | (TR if sand.call(x + 1, y) else 0) \
				| (BL if sand.call(x, y + 1) else 0) | (BR if sand.call(x + 1, y + 1) else 0)
			ground.set_cell(Vector2i(x, y), 0, Vector2i(c % 4, c / 4))
	return ground


## The layout's closed Catmull-Rom spline, as an exactly equivalent Bezier Curve2D.
func _racing_line(points_tiles: Array, tile: float) -> Path2D:
	var pts: Array[Vector2] = []
	for p: Array in points_tiles:
		pts.append(Vector2(p[0], p[1]) * tile)
	var n := pts.size()
	var curve := Curve2D.new()
	# Every car searches this curve for its closest point several times a frame, and the
	# search visits every baked point. 20 px instead of the default 5 is a quarter of the
	# work, and still within a quarter pixel of the true curve on Track 01's tightest bend.
	curve.bake_interval = 20.0
	for i in n + 1:  # repeat the first point to close the loop
		var handle := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]) / 6.0
		curve.add_point(pts[i % n], -handle, handle)
	var path: Path2D = _named(Path2D.new(), "RacingLine")
	path.curve = curve
	return path


func _start_grid(slots_px: Array, curve: Curve2D) -> Node2D:
	var grid: Node2D = _named(Node2D.new(), "StartGrid")
	for i in slots_px.size():
		var marker: Marker2D = _named(Marker2D.new(), "Slot%d" % (i + 1))
		marker.position = Vector2(slots_px[i][0], slots_px[i][1])
		var offset := curve.get_closest_offset(marker.position)
		marker.rotation = (curve.sample_baked(offset + 8.0) - curve.sample_baked(offset)).angle()
		grid.add_child(marker)
	return grid


func _gate(gate_name: String, segment_px: Array, width: float) -> Area2D:
	var a := Vector2(segment_px[0][0], segment_px[0][1])
	var b := Vector2(segment_px[1][0], segment_px[1][1])
	var gate: Area2D = _named(Area2D.new(), gate_name)
	gate.position = (a + b) / 2.0
	gate.rotation = (b - a).angle()
	gate.monitorable = false
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(width, GATE_DEPTH)
	shape.shape = box
	gate.add_child(_named(shape, "Collision"))
	return gate


func _walls(size: Vector2, theme: TrackTheme) -> StaticBody2D:
	var walls: StaticBody2D = _named(StaticBody2D.new(), "Walls")
	var t := WALL_THICKNESS
	var sides := {"Top": Rect2(-t, -t, size.x + 2 * t, t), "Bottom": Rect2(-t, size.y, size.x + 2 * t, t),
		"Left": Rect2(-t, 0, t, size.y), "Right": Rect2(size.x, 0, t, size.y)}
	for side: String in sides:
		var rect: Rect2 = sides[side]
		var shape: CollisionShape2D = _named(CollisionShape2D.new(), side)
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		walls.add_child(shape)
	# The theme's wall prop (tyres, beach balls, cones) drawn just inside the map edge.
	var prop: Texture2D = theme.wall_prop if theme and theme.wall_prop else TYRES
	var spacing: float = theme.wall_spacing if theme else TYRE_SPACING
	var tyres: Node2D = _named(Node2D.new(), "TyreWall")
	walls.add_child(tyres)
	var spots: Array[Vector2] = []
	var inset := prop.get_width() / 2.0
	var x := inset
	while x < size.x:
		spots.append_array([Vector2(x, inset), Vector2(x, size.y - inset)])
		x += spacing
	var y := inset + spacing
	while y < size.y - spacing:
		spots.append_array([Vector2(inset, y), Vector2(size.x - inset, y)])
		y += spacing
	for i in spots.size():
		tyres.add_child(_named(_sprite(prop, spots[i]), "Tyre%d" % (i + 1)))
	return walls


func _props(data: Dictionary, tile: float) -> Node2D:
	var props: Node2D = _named(Node2D.new(), "Props")
	var kinds: Dictionary = data.get("props_tiles", {})
	for kind: String in kinds:
		var texture: Texture2D = load(PROPS[kind][0])
		var spots: Array = kinds[kind]
		for i in spots.size():
			var p: Array = spots[i]
			props.add_child(_obstacle(texture, Vector2(p[0], p[1]) * tile, PROPS[kind][1],
				"%s%d" % [kind.to_pascal_case(), i + 1]))
	return props


## Pads lying across the road at fractions of a lap, pointing the way cars travel.
func _boost_pads(fractions: Array, curve: Curve2D) -> Node2D:
	var pads: Node2D = _named(Node2D.new(), "BoostPads")
	var length := curve.get_baked_length()
	for i in fractions.size():
		var offset := fposmod(float(fractions[i]), 1.0) * length
		var pad: Area2D = _named(Area2D.new(), "Pad%d" % (i + 1))
		pad.position = curve.sample_baked(offset)
		pad.rotation = (curve.sample_baked(fposmod(offset + 8.0, length)) - pad.position).angle()
		pad.monitorable = false
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = BOOST_PAD_SIZE * Vector2(0.6, 1.0)  # the car must really cross it
		shape.shape = box
		pad.add_child(_named(shape, "Collision"))
		var sprite := _sprite(BOOST_PAD, Vector2.ZERO)
		sprite.scale = BOOST_PAD_SIZE / Vector2(BOOST_PAD.get_size())
		pad.add_child(_named(sprite, "Sprite"))
		pads.add_child(pad)
	return pads


func _obstacle(texture: Texture2D, pos: Vector2, radius: float, body_name: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = body_name
	body.position = pos
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	body.add_child(_named(shape, "Collision"))
	body.add_child(_named(_sprite(texture, Vector2.ZERO), "Sprite"))
	return body


func _sprite(texture: Texture2D, pos: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = pos
	return sprite

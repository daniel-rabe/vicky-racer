class_name CustomTrack
extends RefCounted
## The child's own tracks, made in the track editor (docs/DESIGN.md §26). A custom track is a
## small Dictionary — a "spec" — that is also exactly what its .vrtrack file holds (JSON):
##
##   {"format": "vicky-racer-track", "version": 1, "name": "TRACK 3", "theme": "candy",
##    "road": [[x, y], ...],             # the dots, in tiles, in driving order; the first is the finish
##    "props": {"lollipop": [[x, y], ...], ...},
##    "puddles": [[x, y], ...],          # patches of the theme's patch surface (sand, ice, mud...)
##    "boosts": [[x, y], ...]}           # boost pads, laid across the road nearest each spot
##
## to_points_data() turns a spec into the same points data tools/layouts/track_layout.py writes
## for the built-in tracks (finish, checkpoint, grid, bridges where the road crosses itself), and
## make_config() builds the race from that with track/build/build_track.gd, in memory. A file
## from somebody else is never trusted: from_json() rebuilds the spec from what it can read and
## clamps it to the limits below, so a broken or hostile file at worst gives the default track.

const FORMAT := "vicky-racer-track"
const VERSION := 1
const EXTENSION := "vrtrack"
const ID := &"custom"
const TILE_PX := 128.0
const MAP_TILES := Vector2i(48, 30)
const ROAD_TILES := 3.0
## The land themes, in the editor's order, and the props each offers (as in their built-in tracks).
const THEMES: Array[StringName] = [&"meadow", &"beach", &"snow", &"town", &"jungle", &"candy", &"moon"]
const THEME_PROPS := {
	&"meadow": ["tree", "tyre_stack"],
	&"beach": ["palm_tree", "parasol", "beach_ball"],
	&"snow": ["pine_tree", "snowman"],
	&"town": ["toy_house", "traffic_cone", "tree"],
	&"jungle": ["jungle_tree", "jungle_flower", "boulder"],
	&"candy": ["lollipop", "donut", "cupcake", "gumdrop"],
	&"moon": ["rocket", "satellite_dish", "moon_rock"],
}
const MIN_DOTS := 4
const MAX_DOTS := 40
const MAX_PROPS := 120
const MAX_PUDDLES := 24
const MAX_BOOSTS := 10
## A puddle's half-size, tiles (an ellipse, like the built-in tracks' patches).
const PUDDLE_RADII := Vector2(3.0, 2.2)
## Dots, props and puddles stay this far inside the map edge, tiles (the edge is a wall).
const EDGE := 2.0
## A file bigger than this is not a track.
const MAX_FILE_BYTES := 65536
## As in track_layout.py: the staggered grid behind the line, tiles.
const GRID_SPACING_TILES := 1.5
const GRID_LANE_TILES := 0.7
## A bridge is this long, tiles, centred on the crossing.
const BRIDGE_TILES := 16.0
## The road is searched for crossings in steps of this many px.
const CROSSING_STEP := 48.0
## The checkpoint keeps this far from a crossing, tiles.
const CROSSING_CLEAR := 6.0
const BUILDER := preload("res://track/build/build_track.gd")
const OPPONENTS := preload("res://game/configs/tracks/track_01.tres")


## The track a new one starts as: a plain oval, so there is always something to race on.
static func default_spec(theme: StringName = &"meadow", track_name := "MY TRACK") -> Dictionary:
	var road := []
	var centre := Vector2(MAP_TILES) / 2.0
	for i in 8:
		var angle := PI / 2.0 + TAU * i / 8.0  # from the bottom middle, going round clockwise
		road.append(_round2(centre + Vector2(cos(angle) * 16.0, sin(angle) * 9.0)))
	return {"format": FORMAT, "version": VERSION, "name": track_name, "theme": String(theme),
		"road": road, "props": {}, "puddles": [], "boosts": []}


static func props_of(theme: StringName) -> Array:
	return THEME_PROPS.get(theme, THEME_PROPS[&"meadow"])


## The same track in another theme: each prop becomes the new theme's prop in the same place
## of the list (the first kind, a tree, becomes a palm tree on the beach).
static func with_theme(spec: Dictionary, theme: StringName) -> Dictionary:
	var out := spec.duplicate(true)
	var old_kinds := props_of(StringName(spec["theme"]))
	var new_kinds := props_of(theme)
	var props := {}
	for kind: String in spec["props"]:
		var i := maxi(old_kinds.find(kind), 0)
		var new_kind: String = new_kinds[i % new_kinds.size()]
		var list: Array = props.get(new_kind, [])
		list.append_array(spec["props"][kind])
		props[new_kind] = list
	out["props"] = props
	out["theme"] = String(theme)
	return out


# --- files ----------------------------------------------------------------------------------

static func to_json(spec: Dictionary) -> String:
	return JSON.stringify(spec, "\t")


## A spec from a file's text, or {} when it is not a track. Only what is understood is kept,
## clamped to the map and the limits.
static func from_json(text: String) -> Dictionary:
	if text.length() > MAX_FILE_BYTES:
		return {}
	var json := JSON.new()  # not JSON.parse_string, which reports every bad file as an error
	if json.parse(text) != OK:
		return {}
	var data: Variant = json.data
	if not data is Dictionary or data.get("format") != FORMAT:
		return {}
	var theme := StringName(str(data.get("theme", "meadow")))
	if theme not in THEMES:
		theme = &"meadow"
	var road := _points(data.get("road"), MAX_DOTS)
	if road.size() < MIN_DOTS:
		return {}
	var props := {}
	var count := 0
	var raw_props: Variant = data.get("props")
	if raw_props is Dictionary:
		for kind: Variant in raw_props:
			if not kind is String or kind not in props_of(theme):
				continue
			var spots := _points(raw_props[kind], MAX_PROPS - count)
			count += spots.size()
			if not spots.is_empty():
				props[kind] = spots
	var track_name := str(data.get("name", "MY TRACK")).strip_edges().to_upper().left(24)
	return {"format": FORMAT, "version": VERSION, "name": track_name if track_name != "" else "MY TRACK",
		"theme": String(theme), "road": road, "props": props,
		"puddles": _points(data.get("puddles"), MAX_PUDDLES), "boosts": _points(data.get("boosts"), MAX_BOOSTS)}


static func _points(value: Variant, limit: int) -> Array:
	var out := []
	if not value is Array:
		return out
	for p: Variant in value:
		if out.size() >= limit:
			break
		if p is Array and p.size() == 2 and (p[0] is float or p[0] is int) and (p[1] is float or p[1] is int):
			out.append(_round2(clamp_to_map(Vector2(p[0], p[1]))))
	return out


static func clamp_to_map(p: Vector2) -> Vector2:
	if not p.is_finite():
		p = Vector2(MAP_TILES) / 2.0
	return p.clamp(Vector2(EDGE, EDGE), Vector2(MAP_TILES) - Vector2(EDGE, EDGE))


static func _round2(p: Vector2) -> Array:
	return [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]


# --- the road -------------------------------------------------------------------------------

## The road's line, px: the dots' closed Catmull-Rom spline, as build_track.gd draws it.
static func curve_of(road: Array) -> Curve2D:
	var pts: Array[Vector2] = []
	for p: Array in road:
		pts.append(Vector2(p[0], p[1]) * TILE_PX)
	var n := pts.size()
	var curve := Curve2D.new()
	curve.bake_interval = 20.0
	for i in n + 1:
		var handle := (pts[(i + 1) % n] - pts[(i - 1 + n) % n]) / 6.0
		curve.add_point(pts[i % n], -handle, handle)
	return curve


## Where a new dot goes in the loop: between the two neighbours it lengthens the loop least.
static func insert_index(road: Array, at: Vector2) -> int:
	var best := 0
	var best_cost := INF
	for i in road.size():
		var a := Vector2(road[i][0], road[i][1])
		var b := Vector2(road[(i + 1) % road.size()][0], road[(i + 1) % road.size()][1])
		var cost := a.distance_to(at) + at.distance_to(b) - a.distance_to(b)
		if cost < best_cost:
			best_cost = cost
			best = i + 1
	return best


## Where the road crosses itself: each crossing's point (px) and both passes, as lap fractions.
static func crossings(curve: Curve2D) -> Array[Dictionary]:
	var length := curve.get_baked_length()
	var steps := maxi(int(length / CROSSING_STEP), 8)
	var pts := PackedVector2Array()
	for i in steps:
		pts.append(curve.sample_baked(length * i / steps))
	var found: Array[Dictionary] = []
	for i in steps:
		var a1 := pts[i]
		var a2 := pts[(i + 1) % steps]
		for j in range(i + 2, steps):
			if (j + 1) % steps == i:
				continue
			var b1 := pts[j]
			var b2 := pts[(j + 1) % steps]
			var hit: Variant = Geometry2D.segment_intersects_segment(a1, a2, b1, b2)
			if hit == null:
				continue
			if found.any(func(c: Dictionary) -> bool: return c["point"].distance_to(hit) < TILE_PX * 2.0):
				continue  # the same crossing, found again on a neighbouring step
			found.append({"point": hit, "passes": [float(i) / steps, float(j) / steps]})
	return found


## The points data build_track.gd builds a track from (as track_layout.py writes it).
static func to_points_data(spec: Dictionary) -> Dictionary:
	var curve := curve_of(spec["road"])
	var length := curve.get_baked_length()
	var half := ROAD_TILES * TILE_PX / 2.0
	var lap_tiles := length / TILE_PX
	var found := crossings(curve)
	# Each crossing: the pass further from the finish goes over a bridge, so the line and the
	# grid stay on the ground.
	var bridges := []
	for c: Dictionary in found:
		var passes: Array = c["passes"]
		var far := func(f: float) -> float: return minf(f, 1.0 - f)
		var upper: float = passes[0] if far.call(passes[0]) >= far.call(passes[1]) else passes[1]
		var span := minf(BRIDGE_TILES / lap_tiles, 0.2)
		bridges.append([fposmod(upper - span / 2.0, 1.0), span])
	var clear := func(f: float) -> bool:
		var p := curve.sample_baked(f * length)
		for c: Dictionary in found:
			if p.distance_to(c["point"]) < CROSSING_CLEAR * TILE_PX:
				return false
		for b: Array in bridges:
			if fposmod(f - b[0], 1.0) <= b[1]:
				return false
		return true
	var checkpoint_at := 0.5
	for k in 40:  # forward off any crossing or bridge
		if clear.call(fposmod(checkpoint_at, 1.0)):
			break
		checkpoint_at += 0.02
	var grid := []
	for slot in 4:
		var behind := fposmod(-(1.5 + slot * GRID_SPACING_TILES) * TILE_PX, length)
		var p := curve.sample_baked(behind)
		var tangent := (curve.sample_baked(fposmod(behind + 8.0, length)) - p).normalized()
		var side := -GRID_LANE_TILES if slot % 2 == 0 else GRID_LANE_TILES
		grid.append(_px(p + Vector2(-tangent.y, tangent.x) * side * TILE_PX))
	var props := {}
	for kind: String in spec["props"]:
		var radius: float = BUILDER.PROPS[kind][1]
		var spots := (spec["props"][kind] as Array).filter(func(p: Array) -> bool:
			return not on_road(curve, Vector2(p[0], p[1]) * TILE_PX, radius))
		if not spots.is_empty():
			props[kind] = spots
	var boosts := []
	for p: Array in spec["boosts"]:
		boosts.append(curve.get_closest_offset(Vector2(p[0], p[1]) * TILE_PX) / length)
	return {
		"id": String(ID), "name": spec["name"], "theme": spec["theme"], "tile_px": TILE_PX,
		"map_tiles": [MAP_TILES.x, MAP_TILES.y], "road_tiles": ROAD_TILES,
		"control_points_tiles": spec["road"],
		"lap_length_px": length,
		"finish_line_px": _gate(curve, 0.0, half),
		"checkpoint_px": _gate(curve, fposmod(checkpoint_at, 1.0) * length, half),
		"grid_slots_px": grid,
		"patches_tiles": spec["puddles"].map(func(p: Array) -> Array: return [p, [PUDDLE_RADII.x, PUDDLE_RADII.y]]),
		"props_tiles": props,
		"ice_spans": [],
		"boost_pads": boosts,
		"bridge_spans": bridges,
		"crossings_px": found.map(func(c: Dictionary) -> Array: return _px(c["point"])),
	}


## Whether something this big (px radius) at this spot (px) would stand on the road.
static func on_road(curve: Curve2D, at: Vector2, radius: float) -> bool:
	return curve.get_closest_point(at).distance_to(at) < ROAD_TILES * TILE_PX / 2.0 + 40.0 + radius * 0.6


static func _gate(curve: Curve2D, offset: float, half: float) -> Array:
	var length := curve.get_baked_length()
	var p := curve.sample_baked(offset)
	var tangent := (curve.sample_baked(fposmod(offset + 8.0, length)) - p).normalized()
	var normal := Vector2(-tangent.y, tangent.x) * half
	return [_px(p + normal), _px(p - normal)]


static func _px(p: Vector2) -> Array:
	return [snappedf(p.x, 0.1), snappedf(p.y, 0.1)]


# --- the race -------------------------------------------------------------------------------

## The track itself, ready to add to the scene (the editor's preview).
static func make_track(spec: Dictionary) -> Track:
	var builder: Node = BUILDER.new()
	var track := builder.make(to_points_data(spec), ID) as Track
	builder.free()
	return track


## A race on the track: Meadow Loop's three opponents, three laps.
static func make_config(spec: Dictionary) -> TrackConfig:
	var track := make_track(spec)
	var scene := PackedScene.new()
	scene.pack(track)
	track.free()
	var config: TrackConfig = OPPONENTS.duplicate()
	config.track_id = ID
	config.display_name = spec["name"]
	config.track_scene = scene
	return config

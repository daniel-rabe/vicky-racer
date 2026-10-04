@tool
class_name Track
extends Node2D
## One race track (docs/DESIGN.md §7). Two layers:
##   - Ground: a TileMapLayer of the theme's base ground and patches (grass and sand traps,
##     snow and ice ponds...), built from the layout by track/build/build_track.gd.
##   - Road: drawn from the RacingLine Path2D — asphalt, kerbs where the bend is tight,
##     lane dashes and the chequered line. Built in _ready and, in the editor, again whenever
##     the curve is edited, so the road always matches the line the AI drives.
##
## The track also owns surfaces: every physics frame it tells each car in the "cars" group
## what it is driving on. On the road means within road_half_width (plus kerbs) of the line
## — asphalt, or ice where an ice span lies on the road; anywhere else, the ground tile
## decides. Boost pads (BoostPads) give a car a short burst of speed.
##
## It also measures every car against the racing line once per frame, before anything else
## runs (process_physics_priority -2), so the race, the AI and steering help read
## progress_of() / distance_of() instead of each searching the curve again. The search is
## local — near where the car was last frame — so where the road crosses itself a car keeps
## to its own pass of it.
##
## Bridges (docs/DESIGN.md §7.7): where the line crosses itself one pass goes over a bridge
## (bridge_spans). A car on a span is on the upper level: drawn above the deck, colliding
## only with other upper cars and the railings, while cars below drive under it.

signal finish_crossed(car: Car)
signal checkpoint_crossed(car: Car)

const SURFACES := {
	&"asphalt": {"speed_mult": 1.0, "grip_mult": 1.0},
	&"grass": {"speed_mult": 0.55, "grip_mult": 0.7},
	&"sand": {"speed_mult": 0.4, "grip_mult": 0.6},
	# Softer than a sand trap: the beach is everywhere off Sunny Beach's road, the easy track.
	&"beach": {"speed_mult": 0.6, "grip_mult": 0.65},
	&"snow": {"speed_mult": 0.6, "grip_mult": 0.55},
	# Full speed, almost no grip: drift heaven, never a stop.
	&"ice": {"speed_mult": 1.0, "grip_mult": 0.35},
}
const ASPHALT := preload("res://art/tiles/asphalt.png")
const KERB := preload("res://art/tiles/kerb.png")
const CHEQUER := preload("res://art/tiles/finish_line.png")
const ROAD_ICE := preload("res://art/tiles/snow/road_ice.png")
const OUTLINE_COLOUR := Color(0.106, 0.118, 0.137)
const DASH_COLOUR := Color(0.925, 0.925, 0.882)
const KERB_WIDTH := 38.0
## Corner bits of the ground tiles' sand_corners custom data (see build_tileset.py).
const TL := 8
const TR := 4
const BL := 2
const BR := 1

@export var track_id := &"track"
@export var theme: TrackTheme
## Ice lying on the road: x = where it starts, y = how long it is, both as fractions of a lap.
@export var ice_spans: PackedVector2Array = []
## Passes of the road that go over a bridge, as (start, length) fractions of a lap.
@export var bridge_spans: PackedVector2Array = []
@export var map_size := Vector2(6144, 3584)
@export var road_half_width := 192.0
## A bend tighter than this (radians of turn per 100 px of road) gets kerbs.
@export var kerb_turn_per_100px := 0.07
## Kerbs are continuous strips: gaps shorter than this are bridged, and pieces shorter than
## kerb_min_length are dropped, so gentle bends hovering at the threshold do not fragment.
@export var kerb_bridge_gap := 160.0
@export var kerb_min_length := 320.0

var _surface_of := {}  # car -> surface id
var _measured := {}  # car -> Vector2(progress along the line, distance from it), this frame
var _line_pts := PackedVector2Array()    # the racing line's baked points, world space
var _line_at := PackedFloat32Array()     # distance along the line of each
var _last_index := {}  # car -> baked point it was nearest last frame

## A car is searched for within this many baked points (20 px apart) either side of where it
## was; further than RELOCATE_DISTANCE from the line it was teleported, and a full search runs.
const SEARCH_WINDOW := 12
const RELOCATE_FACTOR := 3.0
## Bridge decks draw above the road and the cars beneath them; cars on a bridge above both.
const DECK_Z := 1
const RAILING_HEIGHT_FRACTION := 0.7  # the middle part of a span stands high enough for railings

@onready var ground: TileMapLayer = $Ground
@onready var road: Node2D = $Road  # sits above Ground; the generated road lines go inside it
@onready var racing_line: Path2D = $RacingLine


func _ready() -> void:
	_build_road()
	if Engine.is_editor_hint():
		racing_line.curve.changed.connect(_build_road.call_deferred)
		return
	process_physics_priority = -2  # measure the cars before the drivers and the race read them
	_cache_line()
	_build_railings()
	var car_layers := Car.LAYER_CARS_GROUND | Car.LAYER_CARS_BRIDGE
	for gate: Area2D in [$FinishLine, $Checkpoint]:
		gate.collision_mask = car_layers
	if has_node(^"BoostPads"):
		for pad: Area2D in $BoostPads.get_children():
			pad.collision_mask = car_layers
	$FinishLine.body_entered.connect(func(body: Node2D) -> void:
		if body is Car:
			finish_crossed.emit(body))
	$Checkpoint.body_entered.connect(func(body: Node2D) -> void:
		if body is Car:
			checkpoint_crossed.emit(body))
	if has_node(^"BoostPads"):
		for pad: Area2D in $BoostPads.get_children():
			pad.body_entered.connect(func(body: Node2D) -> void:
				if body is Car:
					body.boost())


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	_measured.clear()
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		var measure := _measure_car(car)
		_measured[car] = measure
		var level := 1 if on_bridge(measure.x) and measure.y <= road_half_width + KERB_WIDTH else 0
		if car.level != level:
			car.set_level(level)
		var surface := surface_at(car.global_position, measure.y)
		if _surface_of.get(car) != surface:
			_surface_of[car] = surface
			car.surface_speed_mult = SURFACES[surface]["speed_mult"]
			car.surface_grip_mult = SURFACES[surface]["grip_mult"]
			EventSystem.CAR_surface_changed.emit(car, surface)


## How far `car` is along the racing line, px, as measured at the start of this physics frame.
func progress_of(car: Node2D) -> float:
	return _measured[car].x if _measured.has(car) else progress_at(car.global_position)


## How far `car` is from the racing line, px, as measured at the start of this physics frame.
func distance_of(car: Node2D) -> float:
	return _measured[car].y if _measured.has(car) else distance_to_line(car.global_position)


## True when `offset` (px along the line) lies on a pass that goes over a bridge.
func on_bridge(offset: float) -> bool:
	var at := offset / lap_length()
	for span in bridge_spans:
		if fposmod(at - span.x, 1.0) <= span.y:
			return true
	return false


## Progress along the line and distance from it, searched near where the car was last frame.
func _measure_car(car: Node2D) -> Vector2:
	var pos := car.global_position
	var n := _line_pts.size()
	var best := Vector3(INF, 0.0, 0.0)  # distance, offset, index
	var last: int = _last_index.get(car, -1)
	if last >= 0:
		for k in range(-SEARCH_WINDOW, SEARCH_WINDOW + 1):
			var i := posmod(last + k, n - 1)
			var a := _line_pts[i]
			var b := _line_pts[i + 1]
			var ab := b - a
			var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			var d := pos.distance_to(a + ab * t)
			if d < best.x:
				best = Vector3(d, _line_at[i] + (_line_at[i + 1] - _line_at[i]) * t, i)
	if last < 0 or best.x > road_half_width * RELOCATE_FACTOR:
		# First sight of this car, or it was put somewhere new: search the whole line.
		var here := progress_at(pos)
		best = Vector3(pos.distance_to(line_point(here)), here, mini(_line_at.bsearch(here), n - 2))
	_last_index[car] = int(best.z)
	return Vector2(fposmod(best.y, lap_length()), best.x)


func _cache_line() -> void:
	var curve := racing_line.curve
	_line_pts = PackedVector2Array()
	_line_at = PackedFloat32Array()
	var total := 0.0
	var points := curve.get_baked_points()
	for i in points.size():
		var p := racing_line.to_global(points[i])
		if i > 0:
			total += p.distance_to(_line_pts[i - 1])
		_line_pts.append(p)
		_line_at.append(total)


## What a car at this point drives on: &"asphalt", &"grass" or &"sand". Pass `distance`
## (from the racing line) when it is already known, to skip a search.
func surface_at(global_pos: Vector2, distance := -1.0) -> StringName:
	if distance < 0.0:
		distance = distance_to_line(global_pos)
	if distance <= road_half_width + KERB_WIDTH - 8.0:
		return &"ice" if _on_road_ice(global_pos) else &"asphalt"
	var base := theme.base_surface if theme else &"grass"
	var patch := theme.patch_surface if theme else &"sand"
	var local := ground.to_local(global_pos)
	var cell := ground.local_to_map(local)
	var data := ground.get_cell_tile_data(cell)
	if data == null:
		return base
	var c: int = data.get_custom_data("sand_corners")
	if c == 0:
		return base
	# Same rule the tiles are drawn with: bilinear blend of the four corners, sand above 0.5.
	var tile := Vector2(ground.tile_set.tile_size)
	var uv := (local - ground.map_to_local(cell)) / tile + Vector2(0.5, 0.5)
	var f := float(c & TL > 0) * (1.0 - uv.x) * (1.0 - uv.y) + float(c & TR > 0) * uv.x * (1.0 - uv.y) \
		+ float(c & BL > 0) * (1.0 - uv.x) * uv.y + float(c & BR > 0) * uv.x * uv.y
	return patch if f > 0.5 else base


func _on_road_ice(global_pos: Vector2) -> bool:
	if ice_spans.is_empty():
		return false
	var at := progress_at(global_pos) / lap_length()
	for span in ice_spans:
		if fposmod(at - span.x, 1.0) <= span.y:
			return true
	return false


func distance_to_line(global_pos: Vector2) -> float:
	var local := racing_line.to_local(global_pos)
	return local.distance_to(racing_line.curve.get_closest_point(local))


## Distance along the racing line from the start of the curve, px.
func progress_at(global_pos: Vector2) -> float:
	return racing_line.curve.get_closest_offset(racing_line.to_local(global_pos))


func lap_length() -> float:
	return racing_line.curve.get_baked_length()


## The point `offset` px along the racing line, moved `sideways` px to its right (seen in
## the direction of travel). Offsets wrap round the lap.
func line_point(offset: float, sideways := 0.0) -> Vector2:
	var p := racing_line.to_global(racing_line.curve.sample_baked(fposmod(offset, lap_length())))
	return p + line_tangent(offset).orthogonal() * sideways


## Direction of travel along the racing line at `offset`, in world space.
func line_tangent(offset: float) -> Vector2:
	var curve := racing_line.curve
	var a := curve.sample_baked(fposmod(offset, lap_length()))
	var b := curve.sample_baked(fposmod(offset + 10.0, lap_length()))
	return racing_line.global_transform.basis_xform(b - a).normalized()


## Signed distance from the racing line: positive to its right, negative to its left.
## Pass `here` (progress_at of the same point) when it is already known, to skip a search.
func side_of_line(global_pos: Vector2, here := -1.0) -> float:
	if here < 0.0:
		here = progress_at(global_pos)
	return (global_pos - line_point(here)).dot(line_tangent(here).orthogonal())


## Start positions, front of the grid first, each facing the direction of travel.
func grid_transforms() -> Array[Transform2D]:
	var out: Array[Transform2D] = []
	for slot: Node2D in $StartGrid.get_children():
		out.append(slot.global_transform)
	return out


func world_rect() -> Rect2:
	return Rect2(global_position, map_size)


# --- road drawing -------------------------------------------------------------------------

func _build_road() -> void:
	# Internal children: regenerated on every load, never saved into the scene file.
	for old in road.get_children(true):
		old.queue_free()
	var points := _sample_line(16.0)
	if points.size() < 3:
		return
	var asphalt: Texture2D = theme.asphalt if theme and theme.asphalt else ASPHALT
	var kerb: Texture2D = theme.kerb if theme and theme.kerb else KERB
	_add_road(_line(points, road_half_width * 2.0 + 12.0, null, OUTLINE_COLOUR, true))
	_add_road(_line(points, road_half_width * 2.0, asphalt, Color.WHITE, true))
	for run in _tight_runs(points):
		for side in [1.0, -1.0]:
			var edge := _offset(run, side * (road_half_width + KERB_WIDTH / 2.0 - 6.0))
			if side < 0.0:
				edge.reverse()  # keep the cream line on the road side
			_add_road(_line(edge, KERB_WIDTH, kerb, Color.WHITE, false))
	for span in ice_spans:
		_add_road(_line(_span_points(span), road_half_width * 2.0 - 8.0, ROAD_ICE, Color.WHITE, false))
	_add_road(_line(points, 12.0, _dash_texture(), DASH_COLOUR, true))
	_add_road(_finish_line())
	for span in bridge_spans:
		_add_road(_bridge_deck(span, asphalt))


## A bridge: the pass of road over the span drawn again, above everything below it — with a
## shadow on the ground and railings along the part that stands high.
func _bridge_deck(span: Vector2, asphalt: Texture2D) -> Node2D:
	var deck := Node2D.new()
	deck.z_index = DECK_Z
	var points := _span_points(span)
	var cut := int(points.size() * (1.0 - RAILING_HEIGHT_FRACTION) / 2.0)
	var high := points.slice(cut, points.size() - cut)
	var shadow := PackedVector2Array()
	for p in high:
		shadow.append(p + Vector2(18, 28))
	deck.add_child(_line(shadow, road_half_width * 2.0 + 16.0, null, Color(0, 0, 0, 0.28), false))
	deck.add_child(_line(points, road_half_width * 2.0 + 12.0, null, OUTLINE_COLOUR, false))
	deck.add_child(_line(points, road_half_width * 2.0, asphalt, Color.WHITE, false))
	deck.add_child(_line(points, 12.0, _dash_texture(), DASH_COLOUR, false))
	for side in [1.0, -1.0]:
		var rail := _offset(high, side * (road_half_width + 4.0))
		deck.add_child(_line(rail, 18.0, null, OUTLINE_COLOUR, false))
		deck.add_child(_line(rail, 10.0, null, Color(0.93, 0.93, 0.95), false))
	return deck


## Solid railings along the high part of every bridge, for cars on the bridge only.
func _build_railings() -> void:
	if bridge_spans.is_empty():
		return
	var body := StaticBody2D.new()
	body.name = "Railings"
	body.collision_layer = Car.LAYER_RAILINGS
	body.collision_mask = 0
	add_child(body)
	for span in bridge_spans:
		var points := _span_points(span)
		var cut := int(points.size() * (1.0 - RAILING_HEIGHT_FRACTION) / 2.0)
		var high := points.slice(cut, points.size() - cut)
		for side in [1.0, -1.0]:
			var rail := _offset(high, side * (road_half_width + 4.0))
			for i in rail.size() - 1:
				var shape := CollisionShape2D.new()
				var segment := SegmentShape2D.new()
				segment.a = to_local(road.to_global(rail[i]))
				segment.b = to_local(road.to_global(rail[i + 1]))
				shape.shape = segment
				body.add_child(shape)


## The racing line's points over one ice span, in Road coordinates.
func _span_points(span: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	var length := lap_length()
	var steps := maxi(2, int(span.y * length / 16.0))
	for i in steps + 1:
		var offset := (span.x + span.y * i / steps) * length
		out.append(road.to_local(line_point(offset)))
	return out


func _add_road(item: Node) -> void:
	road.add_child(item, false, Node.INTERNAL_MODE_BACK)


func _sample_line(step: float) -> PackedVector2Array:
	var curve := racing_line.curve
	var out := PackedVector2Array()
	var length := curve.get_baked_length()
	if length <= 0.0:
		return out
	var count := int(length / step)
	for i in count:
		out.append(road.to_local(racing_line.to_global(curve.sample_baked(length * i / count))))
	return out


func _line(points: PackedVector2Array, width: float, texture: Texture2D, colour: Color, closed: bool) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.closed = closed
	line.width = width
	line.default_color = colour
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	if texture:
		line.texture = texture
		line.texture_mode = Line2D.LINE_TEXTURE_TILE
		line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	return line


## Consecutive stretches of the closed line where it bends tightly enough to need kerbs.
func _tight_runs(points: PackedVector2Array) -> Array[PackedVector2Array]:
	var n := points.size()
	var tight: Array[bool] = []
	for i in n:
		var a := points[i] - points[(i - 1 + n) % n]
		var b := points[(i + 1) % n] - points[i]
		var turn := absf(a.angle_to(b)) / maxf(b.length(), 1.0) * 100.0
		tight.append(turn > kerb_turn_per_100px)
	_bridge_and_trim(tight, points)
	var runs: Array[PackedVector2Array] = []
	var start := tight.find(false)
	if start == -1:
		return runs
	var current := PackedVector2Array()
	for k in range(1, n + 1):
		var i := (start + k) % n
		if tight[i]:
			current.append(points[i])
		elif current.size() > 0:
			if current.size() >= 3:
				runs.append(current)
			current = PackedVector2Array()
	if current.size() >= 3:
		runs.append(current)
	return runs


## Fill short gaps between tight stretches, then clear stretches that are still too short.
func _bridge_and_trim(tight: Array[bool], points: PackedVector2Array) -> void:
	var n := points.size()
	var step := points[0].distance_to(points[1])
	for want in [false, true]:  # first bridge gaps (runs of false), then trim runs of true
		var limit := kerb_bridge_gap if not want else kerb_min_length
		var start := tight.find(not want)
		if start == -1:
			continue
		var run: Array[int] = []
		for k in range(1, n + 1):
			var i := (start + k) % n
			if tight[i] == want:
				run.append(i)
			else:
				if run.size() > 0 and run.size() * step < limit:
					for j in run:
						tight[j] = not want
				run.clear()


func _offset(points: PackedVector2Array, distance: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points.size():
		var a := points[maxi(i - 1, 0)]
		var b := points[mini(i + 1, points.size() - 1)]
		out.append(points[i] + (b - a).normalized().orthogonal() * distance)
	return out


func _finish_line() -> Line2D:
	var at := racing_line.to_local($FinishLine.global_position)
	var offset := racing_line.curve.get_closest_offset(at)
	var centre := road.to_local(racing_line.to_global(racing_line.curve.sample_baked(offset)))
	var ahead := road.to_local(racing_line.to_global(racing_line.curve.sample_baked(offset + 8.0)))
	var across := (ahead - centre).normalized().orthogonal() * road_half_width
	return _line(PackedVector2Array([centre - across, centre + across]), 64.0, CHEQUER, Color.WHITE, false)


static func _dash_texture() -> ImageTexture:
	var image := Image.create(220, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	image.fill_rect(Rect2i(0, 0, 90, 12), Color.WHITE)
	return ImageTexture.create_from_image(image)

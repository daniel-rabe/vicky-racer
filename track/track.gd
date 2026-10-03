@tool
class_name Track
extends Node2D
## One race track (docs/DESIGN.md §7). Two layers:
##   - Ground: a TileMapLayer of grass and sand, painted by hand with the Grass/Sand terrain.
##   - Road: drawn from the RacingLine Path2D — asphalt, kerbs where the bend is tight,
##     lane dashes and the chequered line. Built in _ready and, in the editor, again whenever
##     the curve is edited, so the road always matches the line the AI drives.
##
## The track also owns surfaces: every physics frame it tells each car in the "cars" group
## what it is driving on. On the road means within road_half_width (plus kerbs) of the line;
## anywhere else, the ground tile decides.

signal finish_crossed(car: Car)
signal checkpoint_crossed(car: Car)

const SURFACES := {
	&"asphalt": {"speed_mult": 1.0, "grip_mult": 1.0},
	&"grass": {"speed_mult": 0.55, "grip_mult": 0.7},
	&"sand": {"speed_mult": 0.4, "grip_mult": 0.6},
}
const ASPHALT := preload("res://art/tiles/asphalt.png")
const KERB := preload("res://art/tiles/kerb.png")
const CHEQUER := preload("res://art/tiles/finish_line.png")
const OUTLINE_COLOUR := Color(0.106, 0.118, 0.137)
const DASH_COLOUR := Color(0.925, 0.925, 0.882)
const KERB_WIDTH := 38.0
## Corner bits of the ground tiles' sand_corners custom data (see build_tileset.py).
const TL := 8
const TR := 4
const BL := 2
const BR := 1

@export var track_id := &"track"
@export var map_size := Vector2(6144, 3584)
@export var road_half_width := 192.0
## A bend tighter than this (radians of turn per 100 px of road) gets kerbs.
@export var kerb_turn_per_100px := 0.07
## Kerbs are continuous strips: gaps shorter than this are bridged, and pieces shorter than
## kerb_min_length are dropped, so gentle bends hovering at the threshold do not fragment.
@export var kerb_bridge_gap := 160.0
@export var kerb_min_length := 320.0

var _surface_of := {}  # car -> surface id

@onready var ground: TileMapLayer = $Ground
@onready var road: Node2D = $Road  # sits above Ground; the generated road lines go inside it
@onready var racing_line: Path2D = $RacingLine


func _ready() -> void:
	_build_road()
	if Engine.is_editor_hint():
		racing_line.curve.changed.connect(_build_road.call_deferred)
		return
	$FinishLine.body_entered.connect(func(body: Node2D) -> void:
		if body is Car:
			finish_crossed.emit(body))
	$Checkpoint.body_entered.connect(func(body: Node2D) -> void:
		if body is Car:
			checkpoint_crossed.emit(body))


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		var surface := surface_at(car.global_position)
		if _surface_of.get(car) != surface:
			_surface_of[car] = surface
			car.surface_speed_mult = SURFACES[surface]["speed_mult"]
			car.surface_grip_mult = SURFACES[surface]["grip_mult"]
			EventSystem.CAR_surface_changed.emit(car, surface)


## What a car at this point drives on: &"asphalt", &"grass" or &"sand".
func surface_at(global_pos: Vector2) -> StringName:
	if distance_to_line(global_pos) <= road_half_width + KERB_WIDTH - 8.0:
		return &"asphalt"
	var local := ground.to_local(global_pos)
	var cell := ground.local_to_map(local)
	var data := ground.get_cell_tile_data(cell)
	if data == null:
		return &"grass"
	var c: int = data.get_custom_data("sand_corners")
	if c == 0:
		return &"grass"
	# Same rule the tiles are drawn with: bilinear blend of the four corners, sand above 0.5.
	var tile := Vector2(ground.tile_set.tile_size)
	var uv := (local - ground.map_to_local(cell)) / tile + Vector2(0.5, 0.5)
	var f := float(c & TL > 0) * (1.0 - uv.x) * (1.0 - uv.y) + float(c & TR > 0) * uv.x * (1.0 - uv.y) \
		+ float(c & BL > 0) * (1.0 - uv.x) * uv.y + float(c & BR > 0) * uv.x * uv.y
	return &"sand" if f > 0.5 else &"grass"


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
func side_of_line(global_pos: Vector2) -> float:
	var here := progress_at(global_pos)
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
	_add_road(_line(points, road_half_width * 2.0 + 12.0, null, OUTLINE_COLOUR, true))
	_add_road(_line(points, road_half_width * 2.0, ASPHALT, Color.WHITE, true))
	for run in _tight_runs(points):
		for side in [1.0, -1.0]:
			var edge := _offset(run, side * (road_half_width + KERB_WIDTH / 2.0 - 6.0))
			if side < 0.0:
				edge.reverse()  # keep the cream line on the road side
			_add_road(_line(edge, KERB_WIDTH, KERB, Color.WHITE, false))
	_add_road(_line(points, 12.0, _dash_texture(), DASH_COLOUR, true))
	_add_road(_finish_line())


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

class_name ToyIsland
extends RefCounted
## Toy town (docs/DESIGN.md §36), the open world's fourth district in a track's theme (the
## open-world plan's idea 7): an island south of the town, across a bridge going south from the
## ring road's south-west corner, laid out like a giant play mat: patchwork squares of colour,
## a road printed round it like a children's car rug, toy houses along it, giant letter blocks,
## bouncy balls to kick about, a toy train going round its own track inside the road (it
## bumps a car that gets in its way), and the Toy Town race gate. Confetti drifts down while you
## are there.
##
## As data, like SnowIsland: where everything is, the outline, and what the ground is.

const CENTRE := Vector2(960.0, 13400.0)
const RADII := Vector2(2600.0, 2000.0)
const WOBBLE := 120.0
## Pale water round it, and the strip of sand round the mat.
const SHALLOWS := 380.0
const SAND_RIM := 130.0
## The road from the ring road's south-west corner out over the bridge, going south: its middle
## and half width. It runs on over the island to the toy road.
const BRIDGE_X := 960.0
const BRIDGE_HALF := 140.0
const ROAD_FROM := 7592.0
## The toy road round the mat: a rounded rectangle, its middle line this far out from the
## centre each way, its corners this round.
const ROAD_HALF_SIZE := Vector2(1500.0, 1050.0)
const ROAD_CORNER := 450.0
const ROAD_HALF := 130.0
## The toy train's track, inside the road, and how fast the train goes round it (px/s).
const RAILS_HALF_SIZE := Vector2(1050.0, 650.0)
const RAILS_CORNER := 300.0
const TRAIN_SPEED := 240.0
## The play mat's squares.
const PATCH := 400.0
## The Toy Town race gate, inside the train's track (TownLayout.GATES has the same).
const GATE := Vector2(1110.0, 13400.0)
const TOY_TOWN := &"track_04"


## The waterline `offset` px out (negative: inland): a wobbly oval, kept round and plain where
## the bridge comes ashore on its north side.
static func outline(offset: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 160:
		var a := TAU * i / 160.0
		var at_bridge := clampf(absf(angle_difference(a, -PI / 2.0)) / 0.35, 0.0, 1.0)
		var wobble := (sin(a * 4.0 + 1.1) * 0.6 + sin(a * 9.0 + 0.2) * 0.4) * WOBBLE * at_bridge
		var radii := RADII + Vector2.ONE * (offset + wobble)
		out.append(CENTRE + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return out


## Where the bridge's road lands on the island: the waterline's y on BRIDGE_X.
static func shore_y() -> float:
	return CENTRE.y - RADII.y


## The road from the ring road over the bridge and across the island to the toy road.
static func bridge_rect() -> Rect2:
	var road_y := CENTRE.y - ROAD_HALF_SIZE.y
	return Rect2(BRIDGE_X - BRIDGE_HALF, ROAD_FROM, BRIDGE_HALF * 2.0, road_y - ROAD_FROM)


static func contains(pos: Vector2) -> bool:
	if not Rect2(CENTRE - RADII, RADII * 2.0).grow(WOBBLE + 10.0).has_point(pos):
		return false
	return Geometry2D.is_point_in_polygon(pos, _shore())


## The ground there: the roads are asphalt, the sand round the edge beach, everywhere else the
## play mat (soft, but a car goes well on it).
static func surface(pos: Vector2) -> StringName:
	if on_road(pos) or bridge_rect().has_point(pos):
		return &"asphalt"
	if not Geometry2D.is_point_in_polygon(pos, _mat()):
		return &"beach"
	return &"playmat"


static func on_road(pos: Vector2) -> bool:
	return absf(rounded_distance(pos, ROAD_HALF_SIZE, ROAD_CORNER)) < ROAD_HALF


## How far `pos` is outside (negative: inside) the rounded rectangle round `centre` with these
## half sizes and corners: its middle line is 0. (Sunny Beach's boardwalk is one too.)
static func rounded_distance(pos: Vector2, half_size: Vector2, corner: float, centre := CENTRE) -> float:
	var q := (pos - centre).abs() - (half_size - Vector2.ONE * corner)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - corner


## A rounded rectangle round `centre` as a closed line, clockwise on screen from the top middle.
static func rounded_line(half_size: Vector2, corner: float, offset := 0.0, centre := CENTRE) -> PackedVector2Array:
	var out := PackedVector2Array()
	var inner := half_size - Vector2.ONE * corner
	var r := corner + offset
	for c in 4:
		# Corners: top right, bottom right, bottom left, top left.
		var quarter := [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)][c] as Vector2
		var start := -PI / 2.0 + c * PI / 2.0
		for k in 13:
			var a := start + PI / 2.0 * k / 12.0
			out.append(centre + inner * quarter + Vector2.from_angle(a) * r)
	return out


static func road_line() -> PackedVector2Array:
	return rounded_line(ROAD_HALF_SIZE, ROAD_CORNER)


static func rails_line() -> PackedVector2Array:
	return rounded_line(RAILS_HALF_SIZE, RAILS_CORNER)


## The island and its water, for the camera and the maps.
static func map_rect() -> Rect2:
	return Rect2(CENTRE - RADII, RADII * 2.0).grow(SHALLOWS + 900.0)


static var _cached_shore := PackedVector2Array()
static var _cached_mat := PackedVector2Array()


static func _shore() -> PackedVector2Array:
	if _cached_shore.is_empty():
		_cached_shore = outline(0.0)
	return _cached_shore


static func _mat() -> PackedVector2Array:
	if _cached_mat.is_empty():
		_cached_mat = outline(-SAND_RIM)
	return _cached_mat

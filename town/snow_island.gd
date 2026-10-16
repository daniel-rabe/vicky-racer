class_name SnowIsland
extends RefCounted
## The snowy hill (docs/DESIGN.md §33), the first of the open world's districts in a track's
## theme (the open-world plan's idea 7): an island of snow east of the town, across a long
## bridge from the ring road. On it: the big hill in the middle (driving up it is slow, rolling
## down it fast), a sledging run of ice down its side between flags, a frozen lake to slide
## about on, pine woods, snowmen, and the Snowy Peak race gate. Snow falls while you are there.
##
## As data, like Island: where everything is, the outline, and what the ground is.

const CENTRE := Vector2(16200.0, 2560.0)
const RADII := Vector2(2900.0, 2400.0)
const WOBBLE := 150.0
## Pale water round it, and the icy rim where the snow meets the sea.
const SHALLOWS := 380.0
const ICE_RIM := 70.0
## The road from the ring road's pavement out over the bridge: its middle and half width.
const BRIDGE_Y := 2560.0
const BRIDGE_HALF := 140.0
const ROAD_FROM := 9192.0
## The hill: its top, how far it spreads, and how hard it pushes a car downhill at its
## steepest (px/s², halfway down).
const HILL := Vector2(16700.0, 2260.0)
const HILL_RADIUS := 1050.0
const SLOPE := 560.0
## The sledging run: from near the top, down the hill's south-west side, ice between flags.
const SLED_FROM := Vector2(16480.0, 2500.0)
const SLED_TO := Vector2(15560.0, 3880.0)
const SLED_HALF := 130.0
## The frozen lake.
const LAKE := Vector2(17900.0, 3600.0)
const LAKE_RADII := Vector2(700.0, 440.0)
## The Snowy Peak race gate, on the flat west of the hill (TownLayout.GATES has the same).
const GATE := Vector2(14600.0, 1500.0)
const SNOWY_PEAK := &"track_03"


## The waterline `offset` px out (negative: inland): a wobbly oval, kept round and plain where
## the bridge comes ashore on its west side.
static func outline(offset: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 160:
		var a := TAU * i / 160.0
		var at_bridge := clampf(absf(angle_difference(a, PI)) / 0.35, 0.0, 1.0)
		var wobble := (sin(a * 5.0 + 0.8) * 0.6 + sin(a * 11.0 + 2.0) * 0.4) * WOBBLE * at_bridge
		var radii := RADII + Vector2.ONE * (offset + wobble)
		out.append(CENTRE + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return out


## Where the bridge's road lands on the island: the waterline's x on BRIDGE_Y.
static func shore_x() -> float:
	return CENTRE.x - RADII.x


## The road from the ring road over the bridge to the snow.
static func bridge_rect() -> Rect2:
	return Rect2(ROAD_FROM, BRIDGE_Y - BRIDGE_HALF, shore_x() + 120.0 - ROAD_FROM, BRIDGE_HALF * 2.0)


static func contains(pos: Vector2) -> bool:
	if not Rect2(CENTRE - RADII, RADII * 2.0).grow(WOBBLE + 10.0).has_point(pos):
		return false
	return Geometry2D.is_point_in_polygon(pos, _shore())


## The ground there: ice on the lake and the sledging run, snow everywhere else.
static func surface(pos: Vector2) -> StringName:
	var lake := (pos - LAKE) / LAKE_RADII
	if lake.length() < 1.0 or on_sled_run(pos):
		return &"ice"
	return &"snow"


static func on_sled_run(pos: Vector2) -> bool:
	var closest := Geometry2D.get_closest_point_to_segment(pos, SLED_FROM, SLED_TO)
	return closest.distance_to(pos) < SLED_HALF


## The push downhill at `pos`: nothing at the top or off the hill, strongest halfway down.
static func slope_at(pos: Vector2) -> Vector2:
	var off := pos - HILL
	var d := off.length()
	if d < 1.0 or d > HILL_RADIUS:
		return Vector2.ZERO
	return off / d * SLOPE * sin(PI * d / HILL_RADIUS)


## The island and its water, for the camera and the maps.
static func map_rect() -> Rect2:
	return Rect2(CENTRE - RADII, RADII * 2.0).grow(SHALLOWS + 900.0)


static var _cached_shore := PackedVector2Array()


static func _shore() -> PackedVector2Array:
	if _cached_shore.is_empty():
		_cached_shore = outline(0.0)
	return _cached_shore

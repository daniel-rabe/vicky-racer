class_name CandyIsland
extends RefCounted
## Candy land (docs/DESIGN.md §34), the open world's second district in a track's theme (the
## open-world plan's idea 7): an island of pink icing south-east of the town, across a bridge
## from the ring road's south-east corner. On it: Candy Lane, a road round the island with
## red-and-white kerbs and wobbly jelly pads that bounce a car into the air; a chocolate lake
## in the middle (gooey and slow); lollipop trees, giant cupcakes, donuts and gumdrops; and the
## Candy Lane race gate. Sprinkles fall while you are there.
##
## As data, like SnowIsland: where everything is, the outline, and what the ground is.

const CENTRE := Vector2(15800.0, 7360.0)
const RADII := Vector2(2500.0, 1750.0)
const WOBBLE := 140.0
## Pale water round it, and the rim of white icing where the pink meets the sea.
const SHALLOWS := 380.0
const ICING_RIM := 70.0
## The road from the ring road's south-east corner out over the bridge: its middle and half
## width. It runs on over the island to Candy Lane.
const BRIDGE_Y := 7360.0
const BRIDGE_HALF := 140.0
const ROAD_FROM := 9192.0
## Candy Lane: an oval road round the middle of the island, its middle line this far out.
const LANE_RADII := Vector2(1500.0, 1050.0)
const LANE_HALF := 130.0
## Jelly pads on Candy Lane, where along it (radians round the oval from east, clockwise on
## screen) they sit.
const JELLY_ANGLES: Array[float] = [-PI / 2.0, 0.35, PI / 2.0 + 0.3, PI + 0.6]
const JELLY_SIZE := Vector2(150.0, 200.0)
## The chocolate lake, inside Candy Lane.
const LAKE := Vector2(16350.0, 7760.0)
const LAKE_RADII := Vector2(560.0, 300.0)
## The Candy Lane race gate, inside the lane on its north-west (TownLayout.GATES has the same).
const GATE := Vector2(15750.0, 6980.0)
const CANDY_LANE := &"track_06"


## The waterline `offset` px out (negative: inland): a wobbly oval, kept round and plain where
## the bridge comes ashore on its west side.
static func outline(offset: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 160:
		var a := TAU * i / 160.0
		var at_bridge := clampf(absf(angle_difference(a, PI)) / 0.35, 0.0, 1.0)
		var wobble := (sin(a * 6.0 + 1.9) * 0.55 + sin(a * 13.0 + 0.4) * 0.45) * WOBBLE * at_bridge
		var radii := RADII + Vector2.ONE * (offset + wobble)
		out.append(CENTRE + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return out


## Where the bridge's road lands on the island: the waterline's x on BRIDGE_Y.
static func shore_x() -> float:
	return CENTRE.x - RADII.x


## The road from the ring road over the bridge and across the island to Candy Lane.
static func bridge_rect() -> Rect2:
	var lane_x := CENTRE.x - LANE_RADII.x
	return Rect2(ROAD_FROM, BRIDGE_Y - BRIDGE_HALF, lane_x - ROAD_FROM, BRIDGE_HALF * 2.0)


static func contains(pos: Vector2) -> bool:
	if not Rect2(CENTRE - RADII, RADII * 2.0).grow(WOBBLE + 10.0).has_point(pos):
		return false
	return Geometry2D.is_point_in_polygon(pos, _shore())


## The ground there: the road (Candy Lane and the way in from the bridge) is asphalt, the lake
## chocolate, everywhere else soft pink icing.
static func surface(pos: Vector2) -> StringName:
	if on_lane(pos) or bridge_rect().has_point(pos):
		return &"asphalt"
	if ((pos - LAKE) / LAKE_RADII).length() < 1.0:
		return &"chocolate"
	return &"candy"


static func on_lane(pos: Vector2) -> bool:
	var off := (pos - CENTRE) / LANE_RADII
	if absf(off.length() - 1.0) > 0.25:
		return false
	var lane := lane_line()
	for i in lane.size():
		if Geometry2D.get_closest_point_to_segment(pos, lane[i], lane[(i + 1) % lane.size()]).distance_to(pos) < LANE_HALF:
			return true
	return false


## Candy Lane's middle line, closed, starting at its east end and going clockwise on screen.
static func lane_line() -> PackedVector2Array:
	if _cached_lane.is_empty():
		for i in 96:
			_cached_lane.append(lane_at(TAU * i / 96.0))
	return _cached_lane


## A point on Candy Lane's middle line, `angle` round from east.
static func lane_at(angle: float) -> Vector2:
	return CENTRE + Vector2(cos(angle) * LANE_RADII.x, sin(angle) * LANE_RADII.y)


## The way along Candy Lane at `angle` (clockwise on screen).
static func lane_along(angle: float) -> Vector2:
	return Vector2(-sin(angle) * LANE_RADII.x, cos(angle) * LANE_RADII.y).normalized()


static func jelly_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for a in JELLY_ANGLES:
		out.append(lane_at(a))
	return out


## Is `pos` nearer candy land than the snowy hill, which lies north of it over the water?
static func this_side(pos: Vector2) -> bool:
	return pos.y > (SnowIsland.CENTRE.y + SnowIsland.RADII.y + CENTRE.y - RADII.y) / 2.0


## The island and its water, for the camera and the maps.
static func map_rect() -> Rect2:
	return Rect2(CENTRE - RADII, RADII * 2.0).grow(SHALLOWS + 900.0)


static var _cached_shore := PackedVector2Array()
static var _cached_lane := PackedVector2Array()


static func _shore() -> PackedVector2Array:
	if _cached_shore.is_empty():
		_cached_shore = outline(0.0)
	return _cached_shore

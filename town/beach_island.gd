class_name BeachIsland
extends RefCounted
## Sunny Beach (docs/DESIGN.md §37), the open world's fifth district in a track's theme (the
## open-world plan's idea 7): a sandy island west of the town, across a bridge going west from
## the ring road's north-west corner. A boardwalk of planks runs round it, with beach huts along
## it; sandcastles to knock down (they build themselves up again), crabs that scuttle off when
## a car comes, parasols and palms, a lifeguard's tower, and on its west side the surf: waves
## that roll up the sand and push a car back up the beach. The Sunny Beach race gate stands
## inside the boardwalk.
##
## As data, like SnowIsland: where everything is, the outline, and what the ground is.

const CENTRE := Vector2(-6100.0, 960.0)
const RADII := Vector2(2700.0, 2000.0)
const WOBBLE := 140.0
## Pale water round it.
const SHALLOWS := 420.0
## The road from the ring road's north-west corner out over the bridge, going west: its middle
## and half width, and the x of the ring road's pavement it starts at. It runs on over the
## sand to the boardwalk.
const BRIDGE_Y := 960.0
const BRIDGE_HALF := 140.0
const ROAD_FROM := 728.0
## The boardwalk round the island: a rounded rectangle, its middle line this far out from the
## centre each way, its corners this round.
const WALK_HALF_SIZE := Vector2(1500.0, 1150.0)
const WALK_CORNER := 650.0
const WALK_HALF := 130.0
## The surf, on the west side (this far round either way from due west): how far up the sand
## a wave reaches.
const SURF_ARC := 0.95
const SURF_DEPTH := 460.0
## The Sunny Beach race gate, inside the boardwalk (TownLayout.GATES has the same).
const GATE := Vector2(-5950.0, 960.0)
const SUNNY_BEACH := &"track_02"
## Sandcastles, crabs.
const CASTLES := 9
const CRABS := 7


## The waterline `offset` px out (negative: inland): a wobbly oval, kept round and plain where
## the bridge comes ashore on its east side.
static func outline(offset: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 160:
		out.append(shore_point(TAU * i / 160.0, offset))
	return out


## The point on the line `offset` px out from the waterline, `a` round from due east.
static func shore_point(a: float, offset: float) -> Vector2:
	var radii := RADII + Vector2.ONE * (offset + wobble(a))
	return CENTRE + Vector2(cos(a) * radii.x, sin(a) * radii.y)


static func wobble(a: float) -> float:
	var at_bridge := clampf(absf(angle_difference(a, 0.0)) / 0.35, 0.0, 1.0)
	return (sin(a * 3.0 + 0.4) * 0.6 + sin(a * 8.0 + 1.7) * 0.4) * WOBBLE * at_bridge


## Where the bridge's road lands on the island: the waterline's x on BRIDGE_Y.
static func shore_x() -> float:
	return CENTRE.x + RADII.x


## The road from the ring road over the bridge and across the sand to the boardwalk.
static func bridge_rect() -> Rect2:
	var walk_x := CENTRE.x + WALK_HALF_SIZE.x
	return Rect2(walk_x, BRIDGE_Y - BRIDGE_HALF, ROAD_FROM - walk_x, BRIDGE_HALF * 2.0)


static func contains(pos: Vector2) -> bool:
	if not Rect2(CENTRE - RADII, RADII * 2.0).grow(WOBBLE + 10.0).has_point(pos):
		return false
	return Geometry2D.is_point_in_polygon(pos, _shore())


## The ground there: the boardwalk and the road are firm as a road, the rest is beach.
static func surface(pos: Vector2) -> StringName:
	if on_walk(pos) or bridge_rect().has_point(pos):
		return &"asphalt"
	return &"beach"


static func on_walk(pos: Vector2) -> bool:
	return absf(ToyIsland.rounded_distance(pos, WALK_HALF_SIZE, WALK_CORNER, CENTRE)) < WALK_HALF


static func walk_line(offset := 0.0) -> PackedVector2Array:
	return ToyIsland.rounded_line(WALK_HALF_SIZE, WALK_CORNER, offset, CENTRE)


## How far up the beach from the waterline `pos` is (px; negative: out in the water), if it is
## on the surf side, or INF.
static func up_the_beach(pos: Vector2) -> float:
	var d := (pos - CENTRE) / RADII
	var a := atan2(d.y, d.x)
	if absf(angle_difference(a, PI)) > SURF_ARC:
		return INF
	# Along the line from the centre through `pos`, as far out as the waterline goes.
	var shore := shore_point(a, 0.0)
	return (shore - CENTRE).length() - (pos - CENTRE).length()


## How far up the beach the surf reaches round `a` (from due east), of SURF_DEPTH: all of it
## out west, tapering off to nothing at the ends of the surf.
static func surf_taper(a: float) -> float:
	return clampf((SURF_ARC - absf(angle_difference(a, PI))) / 0.35, 0.0, 1.0)


## Is `pos` under a wave whose water comes `front` px up the beach?
static func in_wave(pos: Vector2, front: float) -> bool:
	var d := (pos - CENTRE) / RADII
	var up := up_the_beach(pos)
	return up != INF and up > -150.0 and up < front * surf_taper(atan2(d.y, d.x))


## Up the beach, away from the sea, at `pos`.
static func inland(pos: Vector2) -> Vector2:
	return (CENTRE - pos).normalized()


## The island and its water, for the camera and the maps.
static func map_rect() -> Rect2:
	return Rect2(CENTRE - RADII, RADII * 2.0).grow(SHALLOWS + 900.0)


static var _cached_shore := PackedVector2Array()


static func _shore() -> PackedVector2Array:
	if _cached_shore.is_empty():
		_cached_shore = outline(0.0)
	return _cached_shore

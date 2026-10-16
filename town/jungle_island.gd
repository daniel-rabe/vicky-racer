class_name JungleIsland
extends RefCounted
## The jungle (docs/DESIGN.md §35), the open world's third district in a track's theme (the
## open-world plan's idea 7): a jungle island north of the town, across a bridge going north
## from the ring road's north-east corner. On it: the jungle trail, a winding road round the
## island through thick jungle, with mud pools on it (a car that splashes through comes out
## muddy, until the car wash cleans it); an old stone temple at the top of the trail, with a
## stepped pyramid behind its courtyard; boulders and flowers; and the Jungle Run race gate.
## Leaves drift down while you are there.
##
## As data, like SnowIsland: where everything is, the outline, and what the ground is.

const CENTRE := Vector2(8960.0, -5700.0)
const RADII := Vector2(2800.0, 2200.0)
const WOBBLE := 160.0
## Pale water round it, and the strip of sand where the jungle meets the sea.
const SHALLOWS := 380.0
const SAND_RIM := 110.0
## The road from the ring road's north-east corner out over the bridge, going north: its
## middle and half width. It runs on over the island to the jungle trail.
const BRIDGE_X := 8960.0
const BRIDGE_HALF := 140.0
const ROAD_FROM := 728.0
## The jungle trail: a wobbly loop round the middle of the island, its middle line this far out
## (and wobbling in and out by TRAIL_WOBBLE of that).
const TRAIL_RADII := Vector2(1650.0, 1250.0)
const TRAIL_WOBBLE := 0.12
const TRAIL_HALF := 130.0
## Mud pools on the trail, where along it (radians round from east, clockwise on screen) they
## lie, and how big they are (along and across the trail).
const MUD_ANGLES: Array[float] = [0.35, 1.25, 2.4, 3.6, 5.3]
const MUD_RADII := Vector2(230.0, 170.0)
## The temple at the top of the trail: its courtyard (the trail runs through it) and the
## stepped pyramid behind it.
const TEMPLE_ANGLE := -PI / 2.0
const COURTYARD_SIZE := Vector2(900.0, 560.0)
const PYRAMID_SIZE := Vector2(560.0, 320.0)
## The Jungle Run race gate, inside the trail (TownLayout.GATES has the same).
const GATE := Vector2(8700.0, -5700.0)
const JUNGLE_RUN := &"track_05"


## The waterline `offset` px out (negative: inland): a wobbly oval, kept round and plain where
## the bridge comes ashore on its south side.
static func outline(offset: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 160:
		var a := TAU * i / 160.0
		var at_bridge := clampf(absf(angle_difference(a, PI / 2.0)) / 0.35, 0.0, 1.0)
		var wobble := (sin(a * 7.0 + 0.3) * 0.5 + sin(a * 3.0 + 2.2) * 0.5) * WOBBLE * at_bridge
		var radii := RADII + Vector2.ONE * (offset + wobble)
		out.append(CENTRE + Vector2(cos(a) * radii.x, sin(a) * radii.y))
	return out


## Where the bridge's road lands on the island: the waterline's y on BRIDGE_X.
static func shore_y() -> float:
	return CENTRE.y + RADII.y


## The road from the ring road over the bridge and across the island to the jungle trail.
static func bridge_rect() -> Rect2:
	var trail_y := trail_at(PI / 2.0).y
	return Rect2(BRIDGE_X - BRIDGE_HALF, trail_y, BRIDGE_HALF * 2.0, ROAD_FROM - trail_y)


static func contains(pos: Vector2) -> bool:
	if not Rect2(CENTRE - RADII, RADII * 2.0).grow(WOBBLE + 10.0).has_point(pos):
		return false
	return Geometry2D.is_point_in_polygon(pos, _shore())


## The ground there: the roads and the temple's courtyard are asphalt, the mud pools mud, the
## sand by the sea beach, everywhere else jungle floor.
static func surface(pos: Vector2) -> StringName:
	for mud in MUD_ANGLES:
		if in_mud(pos, mud):
			return &"mud"
	if on_trail(pos) or bridge_rect().has_point(pos) or courtyard().has_point(pos):
		return &"asphalt"
	if not Geometry2D.is_point_in_polygon(pos, _inland()):
		return &"beach"
	return &"jungle"


static func in_mud(pos: Vector2, angle: float) -> bool:
	var along := trail_along(angle)
	var off := pos - trail_at(angle)
	return Vector2(off.dot(along) / MUD_RADII.x, off.dot(along.orthogonal()) / MUD_RADII.y).length() < 1.0


static func on_trail(pos: Vector2) -> bool:
	var off := (pos - CENTRE) / TRAIL_RADII
	if absf(off.length() - 1.0) > 0.4:
		return false
	var trail := trail_line()
	for i in trail.size():
		if Geometry2D.get_closest_point_to_segment(pos, trail[i], trail[(i + 1) % trail.size()]).distance_to(pos) < TRAIL_HALF:
			return true
	return false


## The trail's middle line, closed, starting at its east end and going clockwise on screen.
static func trail_line() -> PackedVector2Array:
	if _cached_trail.is_empty():
		for i in 120:
			_cached_trail.append(trail_at(TAU * i / 120.0))
	return _cached_trail


## A point on the trail's middle line, `angle` round from east.
static func trail_at(angle: float) -> Vector2:
	var reach := 1.0 + TRAIL_WOBBLE * sin(3.0 * angle + 0.5)
	return CENTRE + Vector2(cos(angle) * TRAIL_RADII.x, sin(angle) * TRAIL_RADII.y) * reach


## The way along the trail at `angle` (clockwise on screen).
static func trail_along(angle: float) -> Vector2:
	return (trail_at(angle + 0.01) - trail_at(angle - 0.01)).normalized()


static func courtyard() -> Rect2:
	return Rect2(trail_at(TEMPLE_ANGLE) - COURTYARD_SIZE / 2.0, COURTYARD_SIZE)


## The pyramid: solid, just north of the courtyard.
static func pyramid() -> Rect2:
	var court := courtyard()
	return Rect2(Vector2(court.get_center().x - PYRAMID_SIZE.x / 2.0, court.position.y - PYRAMID_SIZE.y - 40.0), PYRAMID_SIZE)


## The island and its water, for the camera and the maps.
static func map_rect() -> Rect2:
	return Rect2(CENTRE - RADII, RADII * 2.0).grow(SHALLOWS + 900.0)


static var _cached_shore := PackedVector2Array()
static var _cached_inland := PackedVector2Array()
static var _cached_trail := PackedVector2Array()


static func _shore() -> PackedVector2Array:
	if _cached_shore.is_empty():
		_cached_shore = outline(0.0)
	return _cached_shore


static func _inland() -> PackedVector2Array:
	if _cached_inland.is_empty():
		_cached_inland = outline(-SAND_RIM)
	return _cached_inland

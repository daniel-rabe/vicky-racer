class_name RingRoad
extends RefCounted
## The ring road (docs/DESIGN.md §38), the open world's sixth district: no island this time, but
## sights along the outer ring road round the town itself. A tunnel through a grassy hill on its
## east side (a horn in there echoes), a stream from the pond in the south-west block that runs
## under the road on a little bridge and out to the sea, a fuel station by the road on the
## north side where the Sunny Beach gate stood, and a sign on the south side that shows how fast
## you are going.
##
## As data, like SnowIsland: where everything is.

## The tunnel, on the east side of the ring road between two junctions: the hill over the road
## and its pavements.
const TUNNEL := Rect2(8700.0, 4450.0, 520.0, 1000.0)
## The stream: its middle line from inside the pond, under the road, round the Moon Base gate's
## stopwatch and out into the sea, and its half width.
const STREAM: Array[Vector2] = [Vector2(1580.0, 6590.0), Vector2(1300.0, 6615.0), Vector2(1000.0, 6650.0),
	Vector2(720.0, 6700.0), Vector2(630.0, 6860.0), Vector2(590.0, 7040.0), Vector2(450.0, 7180.0),
	Vector2(200.0, 7260.0), Vector2(-100.0, 7320.0), Vector2(-420.0, 7380.0)]
const STREAM_HALF := 60.0
## The ring road's deck over it, pavements and all.
const STREAM_BRIDGE := Rect2(728.0, 6550.0, 464.0, 250.0)
## The fuel station's yard, where the Sunny Beach gate's paving was (GoldenStars keeps it
## clear): the pump island in the middle, a place to fill up either side of it.
const FUEL_YARD := Rect2(6960.0, 180.0, 680.0, 548.0)
const PUMP := Rect2(7265.0, 320.0, 70.0, 160.0)
const FILL_PADS: Array[Rect2] = [Rect2(7080.0, 290.0, 170.0, 220.0), Rect2(7350.0, 290.0, 170.0, 220.0)]
## The speed sign, on the grass south of the road, where the Candy Lane gate's paving was; it
## reads the speed of a car going by on the road in front of it.
const SPEED_SIGN := Vector2(2400.0, 7800.0)
const SPEED_READS := Rect2(1500.0, 7128.0, 1800.0, 464.0)


static func in_tunnel(pos: Vector2) -> bool:
	return TUNNEL.has_point(pos)


static func in_stream(pos: Vector2) -> bool:
	if not Rect2(-500.0, 6500.0, 2100.0, 960.0).has_point(pos):
		return false
	for i in STREAM.size() - 1:
		if Geometry2D.get_closest_point_to_segment(pos, STREAM[i], STREAM[i + 1]).distance_to(pos) < STREAM_HALF:
			return true
	return false


## In the stream and not on the road's deck over it: wading water.
static func in_water(pos: Vector2) -> bool:
	return in_stream(pos) and not STREAM_BRIDGE.has_point(pos)


static func on_fill_pad(pos: Vector2) -> int:
	for k in FILL_PADS.size():
		if FILL_PADS[k].has_point(pos):
			return k
	return -1


## Boxes round the stream, for the trees to keep off.
static func stream_boxes() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for i in STREAM.size() - 1:
		out.append(Rect2(STREAM[i], Vector2.ZERO).expand(STREAM[i + 1]).grow(STREAM_HALF))
	return out

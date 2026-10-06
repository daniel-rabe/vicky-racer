class_name Island
extends RefCounted
## Free Drive's island (docs/DESIGN.md §21), as data: the coast round the town, the harbour on
## the south coast, and what lies out at sea. The same numbers as the approved mockups
## (tools/layouts/island_probe.py, which draws from its own copy of them).
##
## The coast is an outline round TownLayout's world rect with rounded corners. outline(d)
## is the line `d` px out from the waterline (negative: inland), so every band — grass,
## beach, wet sand, shallows — is the same outline at another offset, and they never cross.

const CORNER := 1300.0
## The waterline: this far out from the town's world edge, give or take WOBBLE.
const COAST := 250.0
const WOBBLE := 150.0
## Sand from the grass to the waterline, and the strip of wet sand at its edge.
const BEACH := 320.0
const WET := 70.0
## Pale water out from the waterline: boats are slowed here, as in a course's shallows.
const SHALLOWS := 420.0
## The outer limit of buoys and rocks, from the town's world edge.
const SEA := 2750.0
## Points along the outline, px apart.
const STEP := 80.0

# --- the harbour (§21.2) ---------------------------------------------------------------
const HARBOUR_X := Vector2(4250.0, 5750.0)
const QUAY := Rect2(4250.0, 8150.0, 1500.0, 500.0)
## The harbour road, from the ring road down to the quay: its centre line and half width.
const DRIVE_X := 5380.0
const DRIVE_HALF := 130.0
## The harbour building stands with its front on the quay's top edge.
const BUILDING_CENTRE_X := 4660.0
const LAND_PAD := Rect2(4470.0, 8165.0, 380.0, 295.0)
const PIER := Rect2(4560.0, 8650.0, 200.0, 450.0)
const MOORING := Rect2(4500.0, 9100.0, 320.0, 280.0)
const SLIPWAY := Rect2(5480.0, 8650.0, 200.0, 280.0)

# --- at sea (§21.5) ---------------------------------------------------------------------
## Islets: centre, radius across (the islet is 0.8 of that tall), what is on it.
## The lighthouse and the wreck sit nearer the island than in the mockups, so the big
## sailboat loop passes outside them (checked against every islet, ramp and coin trail).
const LIGHTHOUSE := Vector2(9920.0 + 650.0, -650.0)
const LIGHTHOUSE_RADIUS := 420.0
## Ramp islets: the islet's centre and which way the ramp throws you over it.
const RAMP_ISLETS := [[Vector2(9920.0 + 1350.0, 4700.0), Vector2.UP], [Vector2(-1450.0, 2300.0), Vector2.DOWN]]
const RAMP_ISLET_RADIUS := 180.0
## The ramp stands this far before the islet's centre.
const RAMP_LEAD := 340.0
const WRECK := Vector2(-950.0, -700.0)
const WRECK_SANDBAR := Vector2(-690.0, -480.0)
const SLALOM_Y := -1250.0
const SLALOM_X := 2400.0
const SLALOM_GAP := 560.0
const SLALOM_BUOYS := 10
const SLALOM_SWING := 220.0
const DOLPHIN_HOME := Vector2(-1700.0, 6300.0)
const GULL_SPOTS: Array[Vector2] = [Vector2(4300.0, 8320.0 + 900.0), Vector2(5600.0, 8320.0 + 1000.0),
	Vector2(9920.0 + 450.0, -350.0), Vector2(9920.0 + 900.0, -1000.0)]
## The big sailboat loop, this far out from the waterline: outside the islets, the ramps
## and the coin trails, inside the outer limit.
const SAIL_LOOP := 2100.0
## The small loop, round the lighthouse's islet.
const SAIL_SMALL_LOOP := Vector2(650.0, 520.0)


static func world() -> Rect2:
	return Rect2(Vector2.ZERO, TownLayout.world_size())


## Everything there is to see: the island and its sea, with a margin of open sea past the
## outer limit.
static func map_rect() -> Rect2:
	return world().grow(SEA + 700.0)


## The island's waterline `offset` px out (negative: inland). `wobble` 0 gives the plain
## rounded rectangle under the bays and points.
static func outline(offset: float, wobble := 1.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _path():
		var d: float = COAST + offset + wobble * _wobble(p[0], p[3])
		out.append(p[0] + p[1] * d)
	return out


## The outer limit: a plain rounded rectangle.
static func limit_outline() -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in _path():
		out.append(p[0] + p[1] * SEA)
	return out


## The waterline as a wall: the coast, with the quay standing out into the water at the
## harbour. Cars stop at it from the land side, boats from the sea side.
static func shoreline() -> PackedVector2Array:
	var out := PackedVector2Array()
	var quay_done := false
	for p in outline(0.0):
		if p.y > world().end.y and p.x > HARBOUR_X.x and p.x < HARBOUR_X.y:
			if not quay_done:
				# The south coast runs right to left (clockwise round the island).
				out.append_array([Vector2(QUAY.end.x, p.y), QUAY.end, Vector2(QUAY.position.x, QUAY.end.y),
					Vector2(QUAY.position.x, p.y)])
				quay_done = true
			continue
		out.append(p)
	return out


## An islet's outline: a wobbly oval `radius` across.
static func islet(centre: Vector2, radius: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40.0
		out.append(centre + Vector2(cos(a) * radius * (1.0 + 0.12 * sin(3.0 * a + radius)),
			sin(a) * radius * 0.8 * (1.0 + 0.1 * cos(5.0 * a))))
	return out


static func ramp_at(islet_index: int) -> Vector2:
	var islet_def: Array = RAMP_ISLETS[islet_index]
	return islet_def[0] - islet_def[1] * RAMP_LEAD


## The slalom's buoys along the north shore, alternately out and in.
static func slalom_buoys() -> PackedVector2Array:
	var out := PackedVector2Array()
	for k in SLALOM_BUOYS:
		out.append(Vector2(SLALOM_X + k * SLALOM_GAP, SLALOM_Y + (SLALOM_SWING if k % 2 else -SLALOM_SWING)))
	return out


## Every coin lying at sea: arcs round the coast, one in each slalom gate, and a line over
## each ramp islet (picked up in the air).
static func sea_coins() -> PackedVector2Array:
	var out := PackedVector2Array()
	var h := TownLayout.world_size().y
	var w := TownLayout.world_size().x
	out.append_array(_arc(Vector2(900, h + 1100), Vector2(3300, h + 1300), 400.0, 9))
	out.append_array(_arc(Vector2(w + 1000, 7200), Vector2(w + 900, 9200), -300.0, 8))
	out.append_array(_arc(Vector2(-1100, 5200), Vector2(-1200, 7200), 260.0, 8))
	out.append_array(_arc(Vector2(6200, h + 1500), Vector2(7400, h + 1000), 200.0, 6))
	for k in SLALOM_BUOYS - 1:
		out.append(Vector2(SLALOM_X + k * SLALOM_GAP + SLALOM_GAP / 2.0, SLALOM_Y))
	for i in RAMP_ISLETS.size():
		var centre: Vector2 = RAMP_ISLETS[i][0]
		var d: Vector2 = RAMP_ISLETS[i][1]
		out.append_array(_arc(centre - d * 200.0, centre + d * 420.0, 0.0, 5))
	return out


## The big sailboat's loop round the whole island, and the small one round the lighthouse.
static func sail_loops() -> Array[PackedVector2Array]:
	var small := PackedVector2Array()
	for i in 60:
		var a := TAU * i / 60.0
		small.append(LIGHTHOUSE + Vector2(cos(a) * SAIL_SMALL_LOOP.x, sin(a) * SAIL_SMALL_LOOP.y))
	return [outline(SAIL_LOOP, 0.3), small]


static func _arc(a: Vector2, b: Vector2, bulge: float, n: int) -> PackedVector2Array:
	var mid := (a + b) / 2.0
	var normal := Vector2(-(b - a).y, (b - a).x).normalized()
	var c := mid + normal * bulge
	var out := PackedVector2Array()
	for i in n:
		var t := float(i) / (n - 1)
		out.append(a.lerp(c, t).lerp(c.lerp(b, t), t))
	return out


static var _cached_path: Array = []


## Points round the town's world rect with rounded corners, clockwise from the top-left
## corner: [point, outward normal, -, distance along].
static func _path() -> Array:
	if not _cached_path.is_empty():
		return _cached_path
	var w := TownLayout.world_size()
	var r := CORNER
	var centres := [Vector2(w.x - r, r), Vector2(w.x - r, w.y - r), Vector2(r, w.y - r), Vector2(r, r)]
	var starts := [Vector2(r, 0), Vector2(w.x, r), Vector2(w.x - r, w.y), Vector2(0, w.y - r)]
	var s := 0.0
	for i in 4:
		var a0 := -PI / 2.0 + PI / 2.0 * i
		var normal := Vector2.from_angle(a0)
		var end: Vector2 = centres[i] + normal * r
		var length: float = starts[i].distance_to(end)
		for k in int(length / STEP):
			_cached_path.append([starts[i].lerp(end, k * STEP / length), normal, 0, s + k * STEP])
		s += length
		var arc := r * PI / 2.0
		for k in int(arc / STEP):
			var a := a0 + PI / 2.0 * k * STEP / arc
			_cached_path.append([centres[i] + Vector2.from_angle(a) * r, Vector2.from_angle(a), 0, s + k * STEP])
		s += arc
	_perimeter = s
	return _cached_path


static var _perimeter := 1.0


## How far the waterline wanders from COAST here: gentle bays and points, and none at the
## harbour, whose quay wall is straight.
static func _wobble(at: Vector2, s: float) -> float:
	var t := s / _perimeter * TAU
	var w := (sin(t * 7.0 + 0.6) * 0.55 + sin(t * 13.0 + 2.1) * 0.3 + sin(t * 23.0 + 4.0) * 0.15) * WOBBLE
	if at.y > TownLayout.world_size().y - 10.0:
		var d := maxf(maxf(HARBOUR_X.x - 500.0 - at.x, at.x - HARBOUR_X.y - 500.0), 0.0)
		w *= minf(1.0, d / 900.0)
	return w

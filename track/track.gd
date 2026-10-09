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
##
## A boat course (docs/DESIGN.md §20) is a track whose road is a channel of deep water (the
## theme's road_surface). It may have currents (current_spans) that carry boats along, ramps
## (Ramps) that throw them in the air, and alternative paths: branches that leave the racing
## line and rejoin it. A racer on a branch is measured along the branch, and its progress is
## the stretch of lap the branch bypasses, in proportion, so laps, places and the minimap
## need nothing new. The finish and the checkpoint never lie on a bypassed stretch.
##
## A space course (docs/DESIGN.md §24) works the same way: its road is a glowing star lane, it
## has branches, and its asteroids, comets and station tunnels are children the builder adds.

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
	# Jungle Run: lush ground like grass, and sticky mud puddles.
	&"jungle": {"speed_mult": 0.55, "grip_mult": 0.7},
	&"mud": {"speed_mult": 0.4, "grip_mult": 0.55},
	# Candy Lane: soft icing like the beach, and gooey chocolate.
	&"candy": {"speed_mult": 0.6, "grip_mult": 0.65},
	&"chocolate": {"speed_mult": 0.45, "grip_mult": 0.6},
	# Moon Base: light moon dust slides about; the craters are deeper dust.
	&"moondust": {"speed_mult": 0.6, "grip_mult": 0.45},
	&"crater": {"speed_mult": 0.45, "grip_mult": 0.45},
	# Free Drive's pond (town/town.gd): wade through slowly, with a splash.
	&"water": {"speed_mult": 0.45, "grip_mult": 0.5},
	# Free Drive's puddles when it rains (docs/DESIGN.md §23): full speed, slippery, a splash.
	&"puddle": {"speed_mult": 1.0, "grip_mult": 0.5},
	# Boat courses (docs/DESIGN.md §20.2). The channel is deep water at full speed; off it, each
	# theme's shallows hold a boat back a little, and banks more (a hovercraft skims them all).
	&"deep_water": {"speed_mult": 1.0, "grip_mult": 1.0},
	&"pond_water": {"speed_mult": 0.6, "grip_mult": 0.8},
	&"river_water": {"speed_mult": 0.6, "grip_mult": 0.8},
	&"lagoon_water": {"speed_mult": 0.6, "grip_mult": 0.8},
	&"lemonade": {"speed_mult": 0.6, "grip_mult": 0.8},
	&"sandbank": {"speed_mult": 0.35, "grip_mult": 0.6},
	# Space courses (docs/DESIGN.md §24.2). The star lane is full speed; off it, every theme's
	# starry dust holds a ship back a little, and the clouds (the moon, ring dust, a nebula,
	# cotton candy) more.
	&"star_lane": {"speed_mult": 1.0, "grip_mult": 1.0},
	&"space_navy": {"speed_mult": 0.6, "grip_mult": 0.8},
	&"space_teal": {"speed_mult": 0.6, "grip_mult": 0.8},
	&"space_purple": {"speed_mult": 0.6, "grip_mult": 0.8},
	&"space_plum": {"speed_mult": 0.6, "grip_mult": 0.8},
	&"moon_surface": {"speed_mult": 0.35, "grip_mult": 0.6},
	&"ring_dust": {"speed_mult": 0.35, "grip_mult": 0.6},
	&"nebula_cloud": {"speed_mult": 0.35, "grip_mult": 0.6},
	&"cotton_candy": {"speed_mult": 0.35, "grip_mult": 0.6},
}
const ASPHALT := preload("res://art/tiles/asphalt.png")
const KERB := preload("res://art/tiles/kerb.png")
const CHEQUER := preload("res://art/tiles/finish_line.png")
const ROAD_ICE := preload("res://art/tiles/snow/road_ice.png")
## Swaying tufts, wind and daisies on grass (living_ground.gdshader).
const LIVING_GROUND := preload("res://track/living_ground.tres")
const OUTLINE_COLOUR := Color(0.106, 0.118, 0.137)
const DASH_COLOUR := Color(0.925, 0.925, 0.882)
const KERB_WIDTH := 38.0
## A current of strength 1 carries a boat along at this many px/s (Boat.current).
const CURRENT_SPEED := 260.0
## The pale lip along a channel's edge: wider than the water, see-through white.
const LIP_COLOUR := Color(1.0, 1.0, 1.0, 0.38)
const LIP_WIDTH := 30.0
## How much further off a branch, px, a racer already on it may stray and still be on it.
const BRANCH_STICK := 160.0
## Progress settles by at most this many px a frame (_settle), unless it leaps further.
const PROGRESS_SETTLE := 60.0
const PROGRESS_LEAP := 2000.0
## Over this much of each end of a branch, px, its progress eases from the racing line's.
const BRANCH_EASE := 700.0
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

@export_group("Water")
## Currents: x = where one starts, y = how long it is (fractions of a lap), z = its strength.
@export var current_spans: PackedVector3Array = []
## Alternative paths: each branch's line (world px, in driving order), the stretch of lap it
## bypasses (x = leaves, y = rejoins, fractions of a lap), its half width, px, and the
## strength of its current (0 = none).
@export var branch_lines: Array[PackedVector2Array] = []
@export var branch_spans: PackedVector2Array = []
@export var branch_half_widths: PackedFloat32Array = []
@export var branch_currents: PackedFloat32Array = []

var _surface_of := {}  # car -> surface id
var _measured := {}  # car -> Vector2(progress along the line, distance from it), this frame
var _line_pts := PackedVector2Array()    # the racing line's baked points, world space
var _line_at := PackedFloat32Array()     # distance along the line of each
var _last_index := {}  # car -> baked point it was nearest last frame
## car -> Vector3(branch index, px along it, px from it), for a racer on a branch this frame.
var _on_branch := {}
var _branch_at: Array[PackedFloat32Array] = []  # each branch's distance along it, per point

## A car is searched for within this many baked points (20 px apart) either side of where it
## was; further than RELOCATE_DISTANCE from the line it was teleported, and a full search runs.
const SEARCH_WINDOW := 12
const RELOCATE_FACTOR := 3.0
## Bridge decks draw above the road and the cars beneath them; cars on a bridge above both.
const DECK_Z := 1
const RAILING_HEIGHT_FRACTION := 0.7
## A car is drawn above the deck from this far before the bridge starts until this far
## after it ends — more than half a car — so no part of it is ever covered by the deck's
## end. Collisions switch at the span itself. Nothing passes under a bridge near its ends.
const DECK_DRAW_MARGIN := 120.0  # the middle part of a span stands high enough for railings

@onready var ground: TileMapLayer = $Ground
@onready var road: Node2D = $Road  # sits above Ground; the generated road lines go inside it
@onready var racing_line: Path2D = $RacingLine


func _ready() -> void:
	_build_road()
	if theme == null or &"grass" in [theme.base_surface, theme.patch_surface]:
		ground.material = LIVING_GROUND
	if Engine.is_editor_hint():
		racing_line.curve.changed.connect(_build_road.call_deferred)
		return
	process_physics_priority = -2  # measure the cars before the drivers and the race read them
	_cache_line()
	_build_railings()
	_cache_branches()
	var car_layers := Car.LAYER_CARS_GROUND | Car.LAYER_CARS_BRIDGE | Car.LAYER_AIRBORNE
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
	if has_node(^"Ramps"):
		for ramp: Area2D in $Ramps.get_children():
			ramp.collision_mask = Car.LAYER_CARS_GROUND
			ramp.body_entered.connect(func(body: Node2D) -> void:
				if body is Boat:
					body.jump())


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	var previous := _measured.duplicate()
	_measured.clear()
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		var measure := _settle(_measure_car(car), previous.get(car))
		_measured[car] = measure
		var on_road := measure.y <= road_half_width + KERB_WIDTH
		var level := 1 if on_bridge(measure.x) and on_road else 0
		if car.level != level:
			car.set_level(level)
		car.set_drawn_above_deck(level == 1 or (on_road and on_bridge(measure.x, DECK_DRAW_MARGIN)))
		var branch: Vector3 = _on_branch.get(car, Vector3(-1, 0, 0))
		var half := road_half_width if branch.x < 0 else branch_half_widths[int(branch.x)]
		var surface := surface_at(car.global_position, measure.y, half)
		if car is Boat:
			(car as Boat).current = _current_at(measure, branch, half)
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


## True when `offset` (px along the line) lies on a pass that goes over a bridge, with the
## span stretched by `margin` px at both ends.
func on_bridge(offset: float, margin := 0.0) -> bool:
	var length := lap_length()
	for span in bridge_spans:
		if fposmod(offset - span.x * length + margin, length) <= span.y * length + 2.0 * margin:
			return true
	return false


## Progress may move by at most PROGRESS_SETTLE px a frame (more than any car's speed): where
## a racer passes from the racing line onto a branch or back, its two measures can differ by a
## few hundred px, and the place shown should glide across that, never jump. A bigger leap (a
## car put back on the line) is taken at once.
func _settle(measure: Vector2, before: Variant) -> Vector2:
	if before == null:
		return measure
	var lap := lap_length()
	var step := fposmod(measure.x - before.x + lap / 2.0, lap) - lap / 2.0
	if absf(step) <= PROGRESS_SETTLE or absf(step) > PROGRESS_LEAP:
		return measure
	return Vector2(fposmod(before.x + signf(step) * PROGRESS_SETTLE, lap), measure.y)


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
	var main := Vector2(fposmod(best.y, lap_length()), best.x)
	var was: int = int(_on_branch[car].x) if _on_branch.has(car) else -1
	_on_branch.erase(car)
	for b in branch_lines.size():
		var on := _nearest_on(branch_lines[b], _branch_at[b], pos)
		# Once on a branch a racer keeps to it until clearly off it, so brushing a narrow
		# branch's edge does not flicker it between the branch and the racing line.
		# Not at its ends, though, where it meets the line: there the nearer one wins.
		var middle := on.x > BRANCH_STICK and on.x < _branch_at[b][-1] - BRANCH_STICK
		var sticky := b == was and middle
		var reach := branch_half_widths[b] + KERB_WIDTH + (BRANCH_STICK if sticky else 0.0)
		if on.y <= reach and (on.y < main.y or sticky):
			_on_branch[car] = Vector3(b, on.x, on.y)
			var span := branch_spans[b]
			var bypassed := fposmod(span.y - span.x, 1.0) * lap_length()
			var lap := lap_length()
			var length := maxf(_branch_at[b][-1], 1.0)
			var mapped := span.x * lap + clampf(on.x / length, 0.0, 1.0) * bypassed
			# Near its ends a branch is close to the racing line, which measures a racer well;
			# further along, the branch's own measure (in proportion) counts. The weight eases
			# with distance along the branch, so progress flows on smoothly from the line onto
			# the branch and back. The line's search is kept at the junction the racer is
			# nearest, so where a branch passes between two stretches of the line (Pirate
			# Cove's Smuggler's Gap) it never hops from one to the other.
			var near_start := on.x < length - on.x
			var direct := fposmod(span.x * lap + on.x if near_start else span.y * lap - (length - on.x), lap)
			_last_index[car] = clampi(_line_at.bsearch(direct), 0, _line_pts.size() - 2)
			var ease_px := minf(BRANCH_EASE, length / 3.0)
			var weight := smoothstep(0.0, ease_px, minf(on.x, length - on.x))
			var gap := fposmod(mapped - main.x + lap / 2.0, lap) - lap / 2.0
			var progress := fposmod(main.x + gap * weight, lap)
			return Vector2(progress, on.y)
	return main


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


## What a car at this point drives on: the road (asphalt, or a boat course's deep water),
## ice, or the ground (grass, sand, shallows...). Pass `distance` (from the racing line, or
## from the branch the car is on, with that branch's `half_width`) when it is already known.
func surface_at(global_pos: Vector2, distance := -1.0, half_width := -1.0) -> StringName:
	if distance < 0.0:
		distance = distance_to_line(global_pos)
	if half_width < 0.0:
		half_width = road_half_width
	if distance <= half_width + KERB_WIDTH - 8.0:
		if _on_road_ice(global_pos):
			return &"ice"
		return theme.road_surface if theme else &"asphalt"
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


# --- water: branches and currents ---------------------------------------------------------

## Which branch `car` is on this frame, or -1 on the racing line.
func branch_of(car: Node2D) -> int:
	return int(_on_branch[car].x) if _on_branch.has(car) else -1


## How far along its branch `car` is, px (0 when not on one).
func branch_progress_of(car: Node2D) -> float:
	return _on_branch[car].y if _on_branch.has(car) else 0.0


func branch_length(b: int) -> float:
	return _branch_at[b][-1]


## Where on the racing line branch `b` leaves it and rejoins it, px.
func branch_entry(b: int) -> float:
	return branch_spans[b].x * lap_length()


func branch_exit(b: int) -> float:
	return branch_spans[b].y * lap_length()


## The point `offset` px along branch `b`, `sideways` px to its right. Past either end it
## carries on along the racing line, so a driver can look ahead across the junction.
func branch_point(b: int, offset: float, sideways := 0.0) -> Vector2:
	if offset < 0.0:
		return line_point(branch_entry(b) + offset, sideways)
	if offset > branch_length(b):
		return line_point(branch_exit(b) + offset - branch_length(b), sideways)
	return _along(branch_lines[b], _branch_at[b], offset) + branch_tangent(b, offset).orthogonal() * sideways


func branch_tangent(b: int, offset: float) -> Vector2:
	if offset < 0.0:
		return line_tangent(branch_entry(b) + offset)
	if offset > branch_length(b):
		return line_tangent(branch_exit(b) + offset - branch_length(b))
	var line := branch_lines[b]
	var at := _branch_at[b]
	var a := _along(line, at, maxf(offset - 5.0, 0.0))
	var c := _along(line, at, minf(offset + 5.0, at[-1]))
	return (c - a).normalized()


## The current where a racer is: along the racing line inside a current span, or along a
## branch that has one; zero anywhere else, and outside the channel.
func _current_at(measure: Vector2, branch: Vector3, half: float) -> Vector2:
	if measure.y > half + KERB_WIDTH:
		return Vector2.ZERO
	if branch.x >= 0:
		var b := int(branch.x)
		if branch_currents[b] <= 0.0:
			return Vector2.ZERO
		return branch_tangent(b, branch.y) * branch_currents[b] * CURRENT_SPEED
	var at := measure.x / lap_length()
	for span in current_spans:
		if fposmod(at - span.x, 1.0) <= span.y:
			return line_tangent(measure.x) * span.z * CURRENT_SPEED
	return Vector2.ZERO


func _cache_branches() -> void:
	_branch_at.clear()
	for line in branch_lines:
		var at := PackedFloat32Array([0.0])
		for i in range(1, line.size()):
			at.append(at[-1] + line[i].distance_to(line[i - 1]))
		_branch_at.append(at)


## (px along, px from) the nearest point of an open polyline.
static func _nearest_on(line: PackedVector2Array, at: PackedFloat32Array, pos: Vector2) -> Vector2:
	var best := Vector2(0.0, INF)
	for i in line.size() - 1:
		var a := line[i]
		var ab := line[i + 1] - a
		var t := clampf((pos - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := pos.distance_to(a + ab * t)
		if d < best.y:
			best = Vector2(at[i] + (at[i + 1] - at[i]) * t, d)
	return best


static func _along(line: PackedVector2Array, at: PackedFloat32Array, offset: float) -> Vector2:
	var i := clampi(at.bsearch(offset) - 1, 0, line.size() - 2)
	var t := clampf((offset - at[i]) / maxf(at[i + 1] - at[i], 0.001), 0.0, 1.0)
	return line[i].lerp(line[i + 1], t)


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
	var water := theme != null and theme.water
	var space := theme != null and theme.space
	if water or space:
		# A channel's pale lip, or a star lane's glow.
		var lip := theme.lane_glow if space else LIP_COLOUR
		# Branches first, so where one meets the racing line the main channel lies on top.
		for b in branch_lines.size():
			var width := branch_half_widths[b] * 2.0
			var line := PackedVector2Array()
			for p in branch_lines[b]:
				line.append(road.to_local(p))
			_add_road(_line(line, width + LIP_WIDTH, null, lip, false))
			_add_road(_line(line, width, asphalt, Color.WHITE, false))
		_add_road(_line(points, road_half_width * 2.0 + LIP_WIDTH, null, lip, true))
	else:
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
	if not water and not space:  # a channel or a star lane has no lanes
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

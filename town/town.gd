class_name Town
extends Node2D
## Free Drive's town (docs/DESIGN.md §19), built in _ready from TownLayout: grass, pavements
## and two-lane streets on a grid, the buildings along the blocks with solid walls, a park
## with a fountain and a pond, and trees. Round it lies the island (§21, Island): a beach,
## the sea out to a ring of buoys, a harbour with a pier, and islets, a lighthouse, a
## shipwreck and a buoy slalom out at sea.
##
## Like a race track it owns surfaces: every physics frame it tells each car in the "cars"
## group what it drives on — the road and the pavements are asphalt, a block's lawn is
## grass, the pond is water, the beach is sand; at sea a boat is slowed in the shallows by
## the shore and goes full speed on deep water.
##
## Phase 23 (§23) adds things to do: a football pitch, a paint shop's pad, the fire station's
## and the school's pads (the fire engine and the school bus), bus stops, jump ramps on paved
## run-ups, and puddles that show on the roads when it rains.
##
## The open world (§28) adds the race gates' paved start grids on the grass round the town
## (gates; the gates themselves, with their racers, are RaceGate), the doors of the garage and the
## trophy house (doors), and the rocket pad on the west side.
## Over bridges from the ring road lie the districts: the snowy hill (§33, SnowIsland), candy
## land (§34, CandyIsland), the jungle (§35, JungleIsland), toy town (§36, ToyIsland) and Sunny
## Beach (§37, BeachIsland).
##
## It is also the traffic's map. Junctions are grid cells (Vector2i); lane_points() and
## turn_points() give the line a car follows along a road and through a junction, on the
## right-hand side, and a car asks to reserve a junction before it drives into it, so two
## cars never cross it at once.

signal place_reached(place_id: String, display_name: String, picture: Texture2D)
## The player's car drove onto a pad that does something to it at once (&"paint").
signal pad_reached(kind: StringName, car: Car)

const GRASS := preload("res://art/tiles/grass.png")
const LIVING_GROUND := preload("res://track/living_ground.tres")
const ASPHALT := preload("res://art/tiles/asphalt.png")
const PAVEMENT := preload("res://art/town/pavement.png")
const ZEBRA := preload("res://art/town/zebra.png")
const TREE := preload("res://art/props/tree.png")
const FOUNTAIN := preload("res://art/town/props/fountain.png")
const PLAYGROUND := preload("res://art/town/props/playground.png")
const BENCH := preload("res://art/town/props/bench.png")
const FLOWER_BED := preload("res://art/town/props/flower_bed.png")
const BUILDING_ART := "res://art/town/buildings/%s.png"
const OPEN_SEA := preload("res://art/town/island/open_sea.png")
const SEA := preload("res://art/town/island/sea.png")
const SHALLOWS := preload("res://art/tiles/lagoon_water.png")
const WET_SAND := preload("res://art/town/island/wet_sand.png")
const BEACH := preload("res://art/tiles/beach.png")
const PLANKS := preload("res://art/town/island/planks.png")
const PALM := preload("res://art/props/beach/palm_tree.png")
const PARASOL := preload("res://art/props/beach/parasol.png")
const BEACH_BALL := preload("res://art/props/beach/beach_ball.png")
const ROCK := preload("res://art/props/water/rock.png")
const RAMP := preload("res://art/props/water/ramp.png")
const WRECK := preload("res://art/props/water/shipwreck_2.png")
const CHEST := preload("res://art/props/water/treasure_chest.png")
const LIGHTHOUSE := preload("res://art/town/island/lighthouse.png")
const SAILBOAT := preload("res://art/town/island/sailboat.png")
const MOORING_POST := preload("res://art/town/island/mooring_post.png")
const FIRE_ENGINE := preload("res://art/town/vehicles/fire_engine.png")
const ROCKET := preload("res://art/ships/cardboard_rocket.png")
const BUS := preload("res://art/town/vehicles/bus.png")
## The snowy hill (§33).
const SNOW := preload("res://art/tiles/snow.png")
const ICE := preload("res://art/tiles/ice.png")
const ROAD_ICE := preload("res://art/tiles/snow/road_ice.png")
const PINE := preload("res://art/props/snow/pine_tree.png")
const SNOWMAN := preload("res://art/props/snow/snowman.png")
const ICE_RIM_COLOUR := Color(0.78, 0.88, 0.97)
## Candy land (§34).
const CANDY_GROUND := preload("res://art/tiles/candy.png")
const CHOCOLATE := preload("res://art/tiles/chocolate.png")
const CANDY_KERB := preload("res://art/tiles/candy/kerb.png")
const LOLLIPOP := preload("res://art/props/candy/lollipop.png")
const CUPCAKE := preload("res://art/props/candy/cupcake.png")
const DONUT := preload("res://art/props/candy/donut.png")
const GUMDROP := preload("res://art/props/candy/gumdrop.png")
const ICING_RIM_COLOUR := Color(1.0, 0.97, 0.98)
const JELLY_COLOURS: Array[Color] = [Color(0.93, 0.2, 0.32), Color(0.35, 0.8, 0.3), Color(1.0, 0.6, 0.12), Color(0.62, 0.33, 0.88)]
## The jungle (§35).
const JUNGLE_GROUND := preload("res://art/tiles/jungle.png")
const MUD := preload("res://art/tiles/mud.png")
const JUNGLE_KERB := preload("res://art/tiles/jungle/kerb.png")
const JUNGLE_TREE := preload("res://art/props/jungle/jungle_tree.png")
const BOULDER := preload("res://art/props/jungle/boulder.png")
const JUNGLE_FLOWER := preload("res://art/props/jungle/jungle_flower.png")
const STONE := Color(0.7, 0.66, 0.56)
const MOSS := Color(0.36, 0.56, 0.26)
## Toy town (§36).
const TOWN_KERB := preload("res://art/tiles/town/kerb.png")
const TOY_HOUSE := preload("res://art/props/town/toy_house.png")
const MAT_COLOURS: Array[Color] = [Color(0.98, 0.72, 0.72), Color(0.7, 0.85, 1.0), Color(1.0, 0.92, 0.6),
	Color(0.75, 0.93, 0.7), Color(0.88, 0.78, 1.0), Color(1.0, 0.82, 0.62)]
const BLOCK_COLOURS: Array[Color] = [Color(0.92, 0.27, 0.3), Color(0.25, 0.55, 0.95), Color(0.98, 0.75, 0.15),
	Color(0.3, 0.75, 0.35), Color(0.65, 0.4, 0.9)]
const RAIL_COLOUR := Color(0.55, 0.36, 0.2)
## Sunny Beach (§37).
const BEACH_KERB := preload("res://art/tiles/beach/kerb.png")
const HUT_COLOURS: Array[Color] = [Color(0.25, 0.55, 0.95), Color(0.92, 0.3, 0.35), Color(0.3, 0.72, 0.45),
	Color(0.98, 0.72, 0.15), Color(0.6, 0.4, 0.88)]
const TOWEL_COLOURS: Array[Color] = [Color(0.95, 0.4, 0.45), Color(0.3, 0.65, 0.95), Color(1.0, 0.82, 0.25), Color(0.45, 0.8, 0.5)]
const PARAPET := Color(0.62, 0.64, 0.7)
const FOAM := Color(1, 1, 1, 0.8)
const PAD_COLOUR := Color(0.24, 0.59, 0.86, 0.92)
## The ramp's trigger, as on a boat course (track/build/build_track.gd).
const RAMP_TRIGGER := Vector2(150, 190)
## Sailing this close to the lighthouse's or the wreck's islet counts as a visit.
const SEA_PLACE_REACH := 700.0
## The shallows are drawn as this many faint bands, each nearer the shore, so they pale
## smoothly towards the sand.
const SHALLOWS_STEPS := 7

## Lanes: px from the road's centre line to a car's line, on the right of the road.
const LANE := 80.0
const KERB_COLOUR := Color(0.93, 0.92, 0.88)
const DASH_COLOUR := Color(0.95, 0.95, 0.9)
const WATER := Color(0.42, 0.72, 0.9)
const WATER_EDGE := Color(0.32, 0.55, 0.42)
const BLOCK_CORNER := 90.0
## Trees: their trunk is solid, their crown is drawn over the cars that pass beneath it.
const TREE_Z := 3
const TREE_TRUNK := 34.0
const TREE_SPACING := 190.0
## A building's solid footprint is its picture less this much all round, px.
const WALL_INSET := 14.0
const WASH_COLOUR := Color(0.55, 0.82, 0.96, 0.9)
## How far the car wash's pad reaches into the road past the pavement, px: the near lane's
## cars pass clear of it, a car steering in drives onto it.
const WASH_PAD_INTO_ROAD := 30.0
const FIRE_PAD_COLOUR := Color(0.86, 0.25, 0.22, 0.9)
const BUS_PAD_COLOUR := Color(0.98, 0.76, 0.18, 0.92)
## The open world's doors (§28): the garage's pad orange, the trophy house's gold.
const DOOR_COLOURS := {&"garage": Color(0.96, 0.55, 0.16, 0.92), &"shelf": Color(1.0, 0.82, 0.25, 0.92),
	&"tracks": Color(0.86, 0.24, 0.28, 0.92), &"editor": Color(0.36, 0.56, 0.86, 0.92)}
## A car gate's paved start area round its grid (§28): this long along the way it faces, this wide.
const GATE_AREA := Vector2(700.0, 470.0)
const ROCKET_PAD_RADIUS := 170.0
## The football pitch (§23): its size, and the goal mouths at each end.
const PITCH_SIZE := Vector2(1000.0, 700.0)
const GOAL_MOUTH := 280.0
const GOAL_DEPTH := 80.0
const POST_RADIUS := 14.0
## Puddles in the road, seen only when it rains.
const PUDDLES := 26
const PUDDLE_COLOUR := Color(0.36, 0.45, 0.58, 0.55)

var junctions := {}  # Vector2i -> Vector2, world position
var links := {}      # Vector2i -> Array[Vector2i], junctions joined by a road
var roads: Array[Array] = []  # [Vector2i, Vector2i]
var lawns: Array[Rect2] = []  # each block's grass
var ponds: Array[Vector3] = []  # x, y, radius
## Building footprints, so trees and walkers keep clear of them.
var footprints: Array[Rect2] = []
## Everything solid on the land, as boxes and circles (x, y, radius): buildings, crates, props.
var solid_boxes: Array[Rect2] = []
var solid_circles: Array[Vector3] = []
## Every named place: {id, name, door (Vector2), picture}.
var places: Array[Dictionary] = []
## The car wash's pad, where a car is washed (Rect2() if the town has none).
var wash_pad := Rect2()
## Islet outlines (§21.5): sand in the sea, walls to a boat.
var islets: Array[PackedVector2Array] = []
# Things to do (§23).
## Houses whose door opens onto a street: {id, door (Vector2), sprite}. Deliveries go here.
var houses: Array[Dictionary] = []
## Pads in front of the fire station, the school (the bus) and the paint shop.
var fire_pad := Rect2()
var bus_pad := Rect2()
var paint_pad := Rect2()
## The open world (§28). Race gates: {"track_id", "at", "facing", "kind" (&"car" or &"boat"),
## "area" (a car gate's paving, else Rect2())}. Doors: {"screen" (&"garage" or &"shelf"), "pad"}.
var gates: Array[Dictionary] = []
var doors: Array[Dictionary] = []
## The rocket pad: driving onto it opens the Hangar.
var rocket_pad := Rect2()
## Toy town's train (§36), going round its track.
var train: ToyTrain
## Sunny Beach (§37): its surf, its sandcastles and its crabs.
var surf: BeachSurf
var castles: Array[SandCastle] = []
var crabs: Array[BeachCrab] = []
## The rocket on it, which lifts off with the car inside (§31).
var rocket: Sprite2D
## Driveways (§29): cars parked on the lawn beside a house, nose to the street, free to borrow.
## Each {"at", "angle"}.
var parking: Array[Dictionary] = []
## The football pitch, and its two goal mouths (the ball is in when its middle is inside one).
var pitch := Rect2()
var goals: Array[Rect2] = []
## Where a beach ball lies, by a parasol.
var beach_balls: Array[Vector2] = []
## The park's fountain: where it is, and its spray (it shoots higher when a car splashes by).
var fountain_at := Vector2.ZERO
## The playgrounds (the park's and the school's): where each picture lies (§32).
var playgrounds: Array[Rect2] = []
var fountain_spray: CPUParticles2D
var flower_beds: Array[Sprite2D] = []
var tree_spots: Array[Vector2] = []
## Bus stops: {stop (the bus's spot in the lane), kerb (where passengers wait), along (the
## road's direction)}.
var bus_stops: Array[Dictionary] = []
## Jump ramps (§23): {at, throw (direction), runway (Rect2)}.
var ramps: Array[Dictionary] = []
## Puddles: x, y, radius. Wet (it is raining, or still drying) they are a surface.
var puddles: Array[Vector3] = []
var wet := false
## Grass that trees and flower beds keep off: the pitch, bus shelters, ramp run-ups.
var _keep_clear: Array[Rect2] = []
var _puddle_layer: Node2D

var _reserved := {}    # Vector2i -> the car crossing that junction
var _surface_of := {}  # car -> surface id
var _solid: StaticBody2D
var _rng := RandomNumberGenerator.new()
# The island's bands, for surface_at: inside the grass line is grass, then sand to the
# waterline, then the shallows out to their line, then deep water.
var _grass_line: PackedVector2Array
var _water_line: PackedVector2Array
var _shallows_line: PackedVector2Array

@onready var _ground := Node2D.new()
@onready var _things := Node2D.new()


func _ready() -> void:
	_rng.seed = 2026
	_ground.name = "Ground"
	_things.name = "Things"
	add_child(_ground)
	add_child(_things)
	_solid = StaticBody2D.new()
	_solid.name = "Solid"
	_solid.collision_layer = Car.LAYER_WORLD
	_solid.collision_mask = 0
	add_child(_solid)
	_grass_line = Island.outline(-Island.BEACH)
	_water_line = Island.outline(0.0)
	_shallows_line = Island.outline(Island.SHALLOWS)
	_build_graph()
	_plan_extras()
	_build_ground()
	_build_blocks()
	_build_coast()
	_build_harbour()
	_build_sea()
	_build_snow()
	_build_candy()
	_build_jungle()
	_build_toys()
	_build_beach()
	_build_extras()
	_plan_parking()


func _physics_process(_delta: float) -> void:
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		var surface := surface_at(car.global_position)
		if _surface_of.get(car) != surface:
			_surface_of[car] = surface
			car.surface_speed_mult = Track.SURFACES[surface]["speed_mult"]
			car.surface_grip_mult = Track.SURFACES[surface]["grip_mult"]
			EventSystem.CAR_surface_changed.emit(car, surface)


## The town's own square of land (the sky's balloons and clouds stay over it).
func world_rect() -> Rect2:
	return Rect2(Vector2.ZERO, TownLayout.world_size())


## The island and all its sea: the camera's limits.
func map_rect() -> Rect2:
	return Island.map_rect().merge(SnowIsland.map_rect()).merge(CandyIsland.map_rect()).merge(JungleIsland.map_rect()).merge(ToyIsland.map_rect()).merge(BeachIsland.map_rect())


## Everything inside the outer ring road's pavement: where the town is.
func streets_rect() -> Rect2:
	var edge := TownLayout.ROAD_HALF + TownLayout.SIDEWALK
	var a := TownLayout.junction(Vector2i.ZERO) - Vector2(edge, edge)
	var b := TownLayout.junction(Vector2i(TownLayout.COLS, TownLayout.ROWS)) + Vector2(edge, edge)
	return Rect2(a, b - a)


func surface_at(pos: Vector2) -> StringName:
	for pond in ponds:
		if pos.distance_to(Vector2(pond.x, pond.y)) < pond.z - 20.0:
			return &"water"
	for ramp in ramps:
		if ramp["runway"].has_point(pos):
			return &"asphalt"
	for gate in gates:
		if gate["area"].has_point(pos):
			return &"asphalt"
	if rocket_pad.has_point(pos):
		return &"asphalt"
	if not streets_rect().has_point(pos):
		return _coast_surface(pos)
	if wet:
		for puddle in puddles:
			if pos.distance_to(Vector2(puddle.x, puddle.y)) < puddle.z:
				return &"puddle"
	for lawn in lawns:
		if lawn.grow(-8.0).has_point(pos):
			return &"grass"
	return &"asphalt"


## Outside the streets: the harbour's paving, the grass, the beach, the sea.
func _coast_surface(pos: Vector2) -> StringName:
	if SnowIsland.contains(pos):
		return SnowIsland.surface(pos)
	if CandyIsland.contains(pos):
		return CandyIsland.surface(pos)
	if JungleIsland.contains(pos):
		return JungleIsland.surface(pos)
	if ToyIsland.contains(pos):
		return ToyIsland.surface(pos)
	if BeachIsland.contains(pos):
		return BeachIsland.surface(pos)
	if Island.QUAY.has_point(pos) or _drive_rect().has_point(pos) or SnowIsland.bridge_rect().has_point(pos) \
			or CandyIsland.bridge_rect().has_point(pos) or JungleIsland.bridge_rect().has_point(pos) \
			or ToyIsland.bridge_rect().has_point(pos) or BeachIsland.bridge_rect().has_point(pos):
		return &"asphalt"
	if Geometry2D.is_point_in_polygon(pos, _grass_line):
		return &"grass"
	if Geometry2D.is_point_in_polygon(pos, _water_line):
		return &"beach"
	for islet in islets:
		if Geometry2D.is_point_in_polygon(pos, islet):
			return &"sandbank"
	if Geometry2D.is_point_in_polygon(pos, _shallows_line):
		return &"lagoon_water"
	return &"deep_water"


# --- the traffic's map ----------------------------------------------------------------

## Direction of travel from junction a to junction b.
func heading(a: Vector2i, b: Vector2i) -> Vector2:
	return Vector2(b - a).normalized()


## The right-hand side of a car heading `d` (screen y points down).
static func right_of(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)


## A car's line along the road from junction a to junction b: from the edge of a's
## crossing to the edge of b's, in the right-hand lane, every `step` px.
func lane_points(a: Vector2i, b: Vector2i, step := 40.0) -> PackedVector2Array:
	var d := heading(a, b)
	var side := right_of(d) * LANE
	var start: Vector2 = junctions[a] + d * TownLayout.ROAD_HALF + side
	var end: Vector2 = junctions[b] - d * TownLayout.ROAD_HALF + side
	var out := PackedVector2Array()
	var count := maxi(1, int(start.distance_to(end) / step))
	for i in count + 1:
		out.append(start.lerp(end, float(i) / count))
	return out


## A car's line through junction b, arriving from a and leaving towards c: straight on, or a
## curve from one lane into the other (tight to the right, wide to the left).
func turn_points(a: Vector2i, b: Vector2i, c: Vector2i, step := 24.0) -> PackedVector2Array:
	var d1 := heading(a, b)
	var d2 := heading(b, c)
	var centre: Vector2 = junctions[b]
	var entry := centre - d1 * TownLayout.ROAD_HALF + right_of(d1) * LANE
	var leave := centre + d2 * TownLayout.ROAD_HALF + right_of(d2) * LANE
	var control := centre + right_of(d1) * LANE + right_of(d2) * LANE
	var straight := d1.dot(d2) > 0.5
	var out := PackedVector2Array()
	var count := maxi(2, int(entry.distance_to(leave) / step))
	for i in range(1, count):
		var t := float(i) / count
		out.append(entry.lerp(leave, t) if straight else
			entry.lerp(control, t).lerp(control.lerp(leave, t), t))
	return out


## Ask to drive across junction `j`. True when it is free or already this car's.
func try_reserve(j: Vector2i, car: Node) -> bool:
	var holder: Node = _reserved.get(j)
	if holder == null or holder == car or not is_instance_valid(holder):
		_reserved[j] = car
		return true
	return false


func release(j: Vector2i, car: Node) -> void:
	if _reserved.get(j) == car:
		_reserved.erase(j)


# --- building ---------------------------------------------------------------------------

func _build_graph() -> void:
	for y in TownLayout.ROWS + 1:
		for x in TownLayout.COLS + 1:
			junctions[Vector2i(x, y)] = TownLayout.junction(Vector2i(x, y))
			links[Vector2i(x, y)] = []
	for y in TownLayout.ROWS + 1:
		for x in TownLayout.COLS + 1:
			if x < TownLayout.COLS and not TownLayout.is_removed("h", x, y):
				_join(Vector2i(x, y), Vector2i(x + 1, y))
			if y < TownLayout.ROWS and not TownLayout.is_removed("v", x, y):
				_join(Vector2i(x, y), Vector2i(x, y + 1))


func _join(a: Vector2i, b: Vector2i) -> void:
	roads.append([a, b])
	links[a].append(b)
	links[b].append(a)


func _build_ground() -> void:
	_build_coast_ground()
	_ground.add_child(_textured(_rect_points(streets_rect(), 140.0), PAVEMENT))
	var half := TownLayout.ROAD_HALF
	# Kerbs first, all of them, then the asphalt over them, so junctions come out clean.
	for road in roads:
		_ground.add_child(_flat(_rect_points(_road_rect(road, half + 7.0)), KERB_COLOUR))
	for j: Vector2i in junctions:
		_ground.add_child(_flat(_rect_points(Rect2(junctions[j] - Vector2(half + 7.0, half + 7.0), Vector2.ONE * (2.0 * half + 14.0))), KERB_COLOUR))
	for road in roads:
		_ground.add_child(_textured(_rect_points(_road_rect(road, half)), ASPHALT))
	for j: Vector2i in junctions:
		_ground.add_child(_textured(_rect_points(Rect2(junctions[j] - Vector2(half, half), Vector2.ONE * 2.0 * half)), ASPHALT))
	var dash := _dash_texture()
	for road in roads:
		var a: Vector2 = junctions[road[0]]
		var b: Vector2 = junctions[road[1]]
		var d := (b - a).normalized()
		var line := Line2D.new()
		line.points = PackedVector2Array([a + d * (half + 150.0), b - d * (half + 150.0)])
		line.width = 10.0
		line.texture = dash
		line.texture_mode = Line2D.LINE_TEXTURE_TILE
		line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		line.default_color = DASH_COLOUR
		_ground.add_child(line)
		# A zebra crossing at each end that meets an inner junction.
		for end in [[road[0], d], [road[1], -d]]:
			var cell: Vector2i = end[0]
			if cell.x > 0 and cell.y > 0 and cell.x < TownLayout.COLS and cell.y < TownLayout.ROWS:
				_ground.add_child(_zebra(junctions[cell] + end[1] * (half + 62.0), end[1]))


func _road_rect(road: Array, half_width: float) -> Rect2:
	var a: Vector2 = junctions[road[0]]
	var b: Vector2 = junctions[road[1]]
	var r := Rect2(a, Vector2.ZERO).expand(b)
	return r.grow_individual(half_width, half_width, half_width, half_width) if r.size.x == 0.0 or r.size.y == 0.0 \
		else r


func _zebra(centre: Vector2, along: Vector2) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = ZEBRA
	sprite.position = centre
	sprite.rotation = along.angle()
	return sprite


## The blocks between the roads: their lawns, and what stands on them.
func _build_blocks() -> void:
	var edge := TownLayout.ROAD_HALF + TownLayout.SIDEWALK
	for cell: Vector2i in TownLayout.BLOCKS:
		var spec: Dictionary = TownLayout.BLOCKS[cell]
		var far := cell + Vector2i.ONE
		# A block runs on until a road closes it (the park spans two cells).
		while far.x <= TownLayout.COLS and TownLayout.is_removed("v", far.x, cell.y):
			far.x += 1
		var lawn := Rect2(TownLayout.junction(cell) + Vector2(edge, edge), Vector2.ZERO)
		lawn = lawn.expand(TownLayout.junction(far) - Vector2(edge, edge))
		lawns.append(lawn)
		_ground.add_child(_textured(_rect_points(lawn, BLOCK_CORNER), GRASS))
		var placed: Array[Rect2] = []
		for row in ["bottom", "top"]:
			if spec.has(row):
				placed.append_array(_row_of_buildings(spec[row], lawn, row == "bottom"))
		if spec.get("park", false):
			placed.append_array(_park(lawn))
		if spec.get("pond", false):
			placed.append(_pond(lawn.get_center(), 300.0))
		if spec.get("football", false):
			placed.append(_football_pitch(lawn))
		if spec.get("playground", false):
			var spot := Vector2(lawn.get_center().x, lawn.position.y + lawn.size.y * 0.42) if spec.has("bottom") \
				else lawn.get_center()
			placed.append(_prop(PLAYGROUND, spot, Vector2(300, 220)))
			playgrounds.append(placed[-1])
		_scatter_trees(lawn, spec.get("trees", 0), placed)
		_scatter_flowers(lawn, spec.get("flowers", 0), placed)


## Buildings spread evenly along the bottom (or top) edge of a lawn, fronts facing down.
func _row_of_buildings(ids: Array, lawn: Rect2, bottom: bool) -> Array[Rect2]:
	var pictures: Array[Texture2D] = []
	var width := 0.0
	for id: String in ids:
		var picture: Texture2D = load(BUILDING_ART % id)
		pictures.append(picture)
		width += picture.get_width()
	var gap := (lawn.size.x - width) / (ids.size() + 1)
	var x := lawn.position.x + gap
	var out: Array[Rect2] = []
	for i in ids.size():
		var picture := pictures[i]
		var size := Vector2(picture.get_size())
		var top := lawn.end.y - size.y - 10.0 if bottom else lawn.position.y + 10.0
		var rect := Rect2(Vector2(x, top), size)
		_building(ids[i], picture, rect, bottom)
		out.append(rect)
		x += size.x + gap
	return out


func _building(id: String, picture: Texture2D, rect: Rect2, on_street: bool, on_lawn := true) -> void:
	var sprite := Sprite2D.new()
	sprite.name = id.capitalize().replace(" ", "")
	sprite.texture = picture
	sprite.centered = false
	sprite.position = rect.position
	_things.add_child(sprite)
	var used := Rect2(picture.get_image().get_used_rect()) if picture.get_image() else Rect2(Vector2.ZERO, rect.size)
	var solid := Rect2(rect.position + used.position, used.size).grow(-WALL_INSET)
	_add_box(solid)
	if on_lawn:
		footprints.append(solid)
	if on_street and TownLayout.PLACE_NAMES.has(id):
		# The doorstep: the pavement in front of the door, and a little of the road.
		var door := Vector2(solid.get_center().x, rect.end.y + 10.0 + TownLayout.SIDEWALK * 0.5)
		places.append({"id": id, "name": TownLayout.PLACE_NAMES[id], "door": door, "picture": picture})
		var area := Area2D.new()
		area.position = door + Vector2(0, 40)
		area.collision_layer = 0
		area.collision_mask = Car.LAYER_CARS_GROUND
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(solid.size.x * 0.6, TownLayout.SIDEWALK + 140.0)
		shape.shape = box
		area.add_child(shape)
		_things.add_child(area)
		area.body_entered.connect(func(body: Node2D) -> void:
			if body is Car and body.has_node(^"PlayerInput"):
				place_reached.emit(id, TownLayout.PLACE_NAMES[id], picture))
	if on_street and id.begins_with("house_"):
		houses.append({"id": id, "door": Vector2(solid.get_center().x, rect.end.y + 10.0 + TownLayout.SIDEWALK * 0.5),
			"sprite": sprite})
	if on_street and id == "car_wash":
		_wash_pad(solid, rect)
	elif on_street and id == "fire_station":
		fire_pad = _front_pad(solid, rect, FIRE_PAD_COLOUR)
		_ghost(FIRE_ENGINE, fire_pad.get_center(), PI / 2.0)
	elif on_street and id == "school":
		bus_pad = _front_pad(solid, rect, BUS_PAD_COLOUR)
		_ghost(BUS, bus_pad.get_center(), PI / 2.0)
	elif on_street and id == "paint_shop":
		_paint_pad(solid, rect)
	elif on_street and TownLayout.DOORS.has(id):
		var screen: StringName = TownLayout.DOORS[id]
		var pad := _front_pad(solid, rect, DOOR_COLOURS[screen])
		_arrows_in(pad)
		doors.append({"screen": screen, "pad": pad, "id": id})


## The car wash's pad: a wet blue strip with soap bubbles and arrows pointing in, from the
## building's front across the pavement and a little way into the road. Driving the player's
## car onto it washes the car (CAR_washed): foam, then it sparkles. Steering in is needed —
## a car keeping to its lane passes by.
func _wash_pad(solid: Rect2, rect: Rect2) -> void:
	var pad := _front_pad(solid, rect, WASH_COLOUR, false)
	wash_pad = pad
	for i in 18:
		var bubble := Polygon2D.new()
		var at := Vector2(_rng.randf_range(pad.position.x + 20.0, pad.end.x - 20.0),
			_rng.randf_range(pad.position.y + 20.0, pad.end.y - 20.0))
		var r := _rng.randf_range(6.0, 15.0)
		var ring := PackedVector2Array()
		for k in 12:
			ring.append(at + Vector2.from_angle(TAU * k / 12.0) * r)
		bubble.polygon = ring
		bubble.color = Color(1, 1, 1, 0.75)
		_ground.add_child(bubble)
	_arrows_in(pad)
	var area := Area2D.new()
	area.name = "WashPad"
	area.position = pad.get_center()
	area.collision_layer = 0
	area.collision_mask = Car.LAYER_CARS_GROUND
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = pad.size
	shape.shape = box
	area.add_child(shape)
	_things.add_child(area)
	area.body_entered.connect(func(body: Node2D) -> void:
		if body is Car and body.has_node(^"PlayerInput"):
			EventSystem.CAR_washed.emit(body))


## Two white arrows on a pad in front of a building, pointing in at its door.
func _arrows_in(pad: Rect2) -> void:
	for side in [-1.0, 1.0]:
		var arrow := Line2D.new()
		var x: float = pad.get_center().x + side * pad.size.x * 0.22
		var tip := pad.position.y + pad.size.y * 0.35
		arrow.points = PackedVector2Array([Vector2(x - 26.0, tip + 30.0), Vector2(x, tip), Vector2(x + 26.0, tip + 30.0)])
		arrow.width = 12.0
		arrow.default_color = Color(1, 1, 1, 0.9)
		arrow.joint_mode = Line2D.LINE_JOINT_ROUND
		arrow.begin_cap_mode = Line2D.LINE_CAP_ROUND
		arrow.end_cap_mode = Line2D.LINE_CAP_ROUND
		_ground.add_child(arrow)


## A pad in front of a building, as the car wash's: from its front wall across the pavement
## and a little way into the road, so a car keeping to its lane passes it by.
func _front_pad(solid: Rect2, rect: Rect2, colour: Color, rim := true) -> Rect2:
	var width := solid.size.x * 0.7
	var top := rect.end.y - 14.0
	var bottom := rect.end.y + 10.0 + TownLayout.SIDEWALK + WASH_PAD_INTO_ROAD
	var pad := Rect2(solid.get_center().x - width / 2.0, top, width, bottom - top)
	_ground.add_child(_flat(_rect_points(pad, 26.0), colour))
	if rim:
		_outline_rect(pad, 26.0, Color(1, 1, 1, 0.85), 6.0)
	return pad


## What a pad turns you into, drawn faintly on it: the vehicle itself, pointing out.
func _ghost(picture: Texture2D, at: Vector2, angle: float) -> void:
	var ghost := Sprite2D.new()
	ghost.texture = picture
	ghost.position = at
	ghost.rotation = angle
	ghost.modulate = Color(1, 1, 1, 0.45)
	_ground.add_child(ghost)


## The paint shop's pad: stripes of every paint. Driving the player's car onto it paints the
## car its next colour (pad_reached &"paint").
func _paint_pad(solid: Rect2, rect: Rect2) -> void:
	var pad := _front_pad(solid, rect, Color(1, 1, 1, 0.9))
	paint_pad = pad
	var stripes: Array = Paint.SWATCHES.values()
	var each := pad.size.x / stripes.size()
	for i in stripes.size():
		var stripe := Rect2(pad.position.x + i * each + 6.0, pad.position.y + 16.0, each - 12.0, pad.size.y - 32.0)
		_ground.add_child(_flat(_rect_points(stripe, 14.0), Color(stripes[i], 0.85)))
	_pad_area(pad, &"paint")


func _pad_area(pad: Rect2, kind: StringName) -> void:
	var area := Area2D.new()
	area.name = String(kind).capitalize() + "Pad"
	area.position = pad.get_center()
	area.collision_layer = 0
	area.collision_mask = Car.LAYER_CARS_GROUND
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = pad.size
	shape.shape = box
	area.add_child(shape)
	_things.add_child(area)
	area.body_entered.connect(func(body: Node2D) -> void:
		if body is Car and body.has_node(^"PlayerInput"):
			pad_reached.emit(kind, body))


## The big park: a fountain in the middle, the pond and the playground either side, flower
## beds and benches round the fountain. Trees fill in later.
func _park(lawn: Rect2) -> Array[Rect2]:
	var centre := lawn.get_center()
	var out: Array[Rect2] = []
	var fountain := _prop(FOUNTAIN, centre, Vector2(280, 280), 120.0)
	out.append(fountain)
	fountain_at = centre
	fountain_spray = _spray(centre)
	_things.add_child(fountain_spray)
	out.append(_pond(centre + Vector2(lawn.size.x * 0.3, 0), 280.0))
	out.append(_prop(PLAYGROUND, centre - Vector2(lawn.size.x * 0.3, 0), Vector2(320, 240)))
	playgrounds.append(out[-1])
	for angle in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var spot := centre + Vector2.from_angle(angle) * 260.0
		out.append(_prop(FLOWER_BED, spot, Vector2(110, 110), 0.0))
		flower_beds.append(_things.get_child(-1))
	for side in [-1.0, 1.0]:
		var bench := _prop(BENCH, centre + Vector2(0, side * 230.0), Vector2(120, 60), 0.0)
		out.append(bench)
	# Paths: pale gravel from the fountain to each side of the park.
	for d: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		var reach := lawn.size.x * 0.5 if d.y == 0.0 else lawn.size.y * 0.5
		var path := Line2D.new()
		path.points = PackedVector2Array([centre + d * 150.0, centre + d * reach])
		path.width = 90.0
		path.default_color = Color(0.9, 0.84, 0.66)
		path.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_ground.add_child(path)
	return out


## The fountain's water: droplets thrown up from the middle, falling back into the bowl.
func _spray(at: Vector2) -> CPUParticles2D:
	var spray := CPUParticles2D.new()
	spray.position = at
	spray.z_index = TREE_Z
	spray.amount = 40
	spray.lifetime = 1.1
	spray.direction = Vector2.UP
	spray.spread = 180.0
	spray.initial_velocity_min = 40.0
	spray.initial_velocity_max = 90.0
	spray.gravity = Vector2.ZERO
	spray.damping_min = 40.0
	spray.damping_max = 60.0
	spray.scale_amount_min = 4.0
	spray.scale_amount_max = 8.0
	var fade := Gradient.new()
	fade.set_color(0, Color(0.92, 0.97, 1.0, 0.9))
	fade.set_color(1, Color(0.8, 0.92, 1.0, 0.0))
	spray.color_ramp = fade
	return spray


## A pond: drawn water you can drive through (slowly, splashing), with lily pads.
func _pond(centre: Vector2, radius: float) -> Rect2:
	ponds.append(Vector3(centre.x, centre.y, radius))
	var points := PackedVector2Array()
	for i in 48:
		var angle := TAU * i / 48.0
		var wobble := 1.0 + 0.06 * sin(angle * 3.0) + 0.04 * sin(angle * 5.0 + 1.0)
		points.append(centre + Vector2.from_angle(angle) * radius * wobble)
	var rim := Polygon2D.new()
	rim.polygon = points
	rim.color = WATER_EDGE
	rim.scale = Vector2.ONE * 1.06
	rim.position = centre * -0.06
	_ground.add_child(rim)
	var water := Polygon2D.new()
	water.polygon = points
	water.color = WATER
	_ground.add_child(water)
	for i in 5:
		var pad := Polygon2D.new()
		var at := centre + Vector2.from_angle(_rng.randf() * TAU) * radius * _rng.randf_range(0.3, 0.75)
		var leaf := PackedVector2Array()
		for k in 14:
			if k == 0:
				leaf.append(at)
			leaf.append(at + Vector2.from_angle(0.5 + TAU * k / 14.0 * 0.85) * 26.0)
		pad.polygon = leaf
		pad.color = Color(0.4, 0.7, 0.35)
		_ground.add_child(pad)
	return Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2.0)


## A prop sprite scaled to fit `box`, solid out to `solid_radius` (0: drive over it).
func _prop(texture: Texture2D, centre: Vector2, box: Vector2, solid_radius := -1.0) -> Rect2:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = centre
	var fit := minf(box.x / texture.get_width(), box.y / texture.get_height())
	sprite.scale = Vector2(fit, fit)
	_things.add_child(sprite)
	var size := Vector2(texture.get_size()) * fit
	var rect := Rect2(centre - size / 2.0, size)
	if solid_radius < 0.0:
		_add_box(rect.grow(-WALL_INSET))
	elif solid_radius > 0.0:
		_add_circle(centre, solid_radius)
	return rect


func _scatter_trees(lawn: Rect2, count: int, taken: Array[Rect2]) -> void:
	var inner := lawn.grow(-110.0)
	var trees: Array[Vector2] = []
	var tries := 0
	while trees.size() < count and tries < 400:
		tries += 1
		var spot := Vector2(_rng.randf_range(inner.position.x, inner.end.x), _rng.randf_range(inner.position.y, inner.end.y))
		if taken.any(func(r: Rect2) -> bool: return r.grow(100.0).has_point(spot)):
			continue
		if trees.any(func(t: Vector2) -> bool: return t.distance_to(spot) < TREE_SPACING):
			continue
		if _keep_clear.any(func(r: Rect2) -> bool: return r.grow(90.0).has_point(spot)):
			continue
		trees.append(spot)
		_tree(spot, _rng.randf_range(0.8, 1.05))
	for t in trees:
		taken.append(Rect2(t - Vector2(90, 90), Vector2(180, 180)))


## Flower beds in the gardens: decoration only, a car drives over them.
func _scatter_flowers(lawn: Rect2, count: int, taken: Array[Rect2]) -> void:
	var inner := lawn.grow(-80.0)
	var placed := 0
	for attempt in 200:
		if placed >= count:
			return
		var spot := Vector2(_rng.randf_range(inner.position.x, inner.end.x), _rng.randf_range(inner.position.y, inner.end.y))
		if taken.any(func(r: Rect2) -> bool: return r.grow(50.0).has_point(spot)):
			continue
		if _keep_clear.any(func(r: Rect2) -> bool: return r.has_point(spot)):
			continue
		var bed := _prop(FLOWER_BED, spot, Vector2(96, 96) * _rng.randf_range(0.85, 1.15), 0.0)
		flower_beds.append(_things.get_child(-1))
		taken.append(bed)
		placed += 1


func _tree(at: Vector2, size: float) -> void:
	tree_spots.append(at)
	var sprite := Sprite2D.new()
	sprite.texture = TREE
	sprite.position = at
	sprite.scale = Vector2(size, size)
	sprite.rotation = _rng.randf() * TAU
	sprite.z_index = TREE_Z
	_things.add_child(sprite)
	_add_circle(at, TREE_TRUNK * size)


## The island's ground (§21.1), from the outside in: open sea, the sea inside the outer
## limit, the shallows (in steps, paler towards the shore), foam where the waves meet the
## sand, wet sand, the beach, and the island's grass.
func _build_coast_ground() -> void:
	_ground.add_child(_textured(_rect_points(map_rect()), OPEN_SEA))
	_ground.add_child(_textured(Island.limit_outline(), SEA))
	for k in SHALLOWS_STEPS:
		var band := _textured(Island.outline(Island.SHALLOWS * (1.0 - 0.75 * float(k) / SHALLOWS_STEPS)), SHALLOWS)
		band.color = Color(1, 1, 1, 0.22)
		_ground.add_child(band)
	var foam := Line2D.new()
	foam.points = Island.outline(18.0)
	foam.closed = true
	foam.width = 26.0
	foam.default_color = FOAM
	_ground.add_child(foam)
	_ground.add_child(_textured(_water_line, WET_SAND))
	_ground.add_child(_textured(Island.outline(-Island.WET), BEACH))
	_ground.add_child(_textured(_grass_line, GRASS))
	_build_snow_ground()
	_build_candy_ground()
	_build_jungle_ground()
	_build_toy_ground()
	_build_beach_ground()


## Palms where the grass meets the sand, parasols and beach balls along the beach, a few
## trees on the grass round the town, and the waterline as a wall: cars stop at the wet
## sand, boats in the shallows.
func _build_coast() -> void:
	var palms := Island.outline(-Island.BEACH - 60.0)
	for i in range(0, palms.size(), 9):
		if not _near_harbour(palms[i], 300.0) and not _near_bridge(palms[i], 200.0):
			var palm := _sprite(PALM, palms[i], 220.0 * _rng.randf_range(0.85, 1.1), _rng.randf() * TAU)
			palm.z_index = TREE_Z
			_add_circle(palms[i], TREE_TRUNK)
	var sand := Island.outline(-Island.BEACH * 0.45)
	for i in range(5, sand.size(), 37):
		if not _near_harbour(sand[i], 500.0) and not _near_bridge(sand[i], 300.0):
			_sprite(PARASOL, sand[i], 190.0)
			beach_balls.append(sand[i] + Vector2(150, 60))  # a ball to kick about (§23): the screen puts it there
	# A few round trees on the grass between the ring road and the beach.
	var streets := streets_rect()
	var inner := Island.outline(-Island.BEACH - 200.0)
	for i in 60:
		var spot := Vector2(_rng.randf_range(-200.0, world_rect().end.x + 200.0), _rng.randf_range(-200.0, world_rect().end.y + 200.0))
		if streets.grow(160.0).has_point(spot) or not Geometry2D.is_point_in_polygon(spot, inner) or _near_harbour(spot, 500.0):
			continue
		if _keep_clear.any(func(r: Rect2) -> bool: return r.grow(120.0).has_point(spot)):
			continue
		_tree(spot, _rng.randf_range(0.8, 1.1))
	# Boats stop all round the island; cars too, except where the bridges to the districts
	# (§33–§37) leave it, and their rails keep them on the deck (boats sail under).
	_wall_line(_wall(Car.LAYER_LAND_EDGE, "Shore"), Island.shoreline())
	var shore := _wall(Car.LAYER_SEA_EDGE, "ShoreForCars")
	var main := _gaps(Island.shoreline())
	var districts: Array[Array] = [_gaps(SnowIsland.outline(0.0)), _gaps(CandyIsland.outline(0.0)), _gaps(JungleIsland.outline(0.0)),
		_gaps(ToyIsland.outline(0.0)), _gaps(BeachIsland.outline(0.0))]
	for run in main:
		_wall_open(shore, run)
	for far in districts:
		for run: PackedVector2Array in far:
			_wall_open(shore, run)
	for b in _bridges():
		for side in 2:  # each rail, along one side of the deck
			var from := _end_on(main, b, side)
			for far in districts:
				var to := _end_on(far, b, side)
				if to != Vector2.INF:
					_wall_open(shore, PackedVector2Array([from, to]))


## The harbour (§21.2): a road down from the ring road to a stone quay, the harbour master's
## boathouse facing onto it with the land pad in front, the pier out to the mooring, a
## slipway, and boats tied up.
func _build_harbour() -> void:
	var quay := Island.QUAY
	var drive := _drive_rect()
	_ground.add_child(_flat(_rect_points(Rect2(drive.position + Vector2(-7, 20), drive.size + Vector2(14, 20))), KERB_COLOUR))
	_ground.add_child(_textured(_rect_points(drive.grow_individual(0, 0, 0, 40)), ASPHALT))
	var y := drive.position.y + 160.0
	while y < drive.end.y - 80.0:
		_ground.add_child(_flat(_rect_points(Rect2(Island.DRIVE_X - 5.0, y, 10.0, 80.0)), DASH_COLOUR))
		y += 160.0
	_ground.add_child(_textured(_rect_points(quay), PAVEMENT))
	var edge := Color(0.59, 0.55, 0.49)
	for strip: Rect2 in [Rect2(quay.position.x, quay.end.y - 30.0, quay.size.x, 30.0),
			Rect2(quay.position.x, quay.position.y, 24.0, quay.size.y), Rect2(quay.end.x - 24.0, quay.position.y, 24.0, quay.size.y)]:
		_ground.add_child(_flat(_rect_points(strip), edge))
	var x := quay.position.x + 120.0
	while x < quay.end.x - 60.0:
		if _clear_of(x, Island.PIER) and _clear_of(x, Island.SLIPWAY):
			_ground.add_child(_disc(Vector2(x, quay.end.y - 28.0), 22.0, Color(0.24, 0.24, 0.26)))
		x += 220.0
	# Crates and a coil of rope on the quay; the crates are solid.
	for crate: Array in [[Vector2(5630, 8250), Color(0.77, 0.47, 0.24)], [Vector2(5700, 8250), Color(0.27, 0.55, 0.78)],
			[Vector2(5665, 8190), Color(0.86, 0.71, 0.24)]]:
		var box := Rect2(crate[0] - Vector2(34, 34), Vector2(68, 68))
		_things.add_child(_flat(_rect_points(box), crate[1]))
		var rim := Line2D.new()
		rim.points = _rect_points(box)
		rim.closed = true
		rim.width = 5.0
		rim.default_color = Color(0.24, 0.16, 0.08)
		_things.add_child(rim)
	_add_box(Rect2(5596, 8156, 138, 128))
	var rope := Line2D.new()
	for k in 25:
		rope.add_point(Vector2(5220, 8510) + Vector2.from_angle(TAU * k / 24.0) * 32.0)
	rope.width = 14.0
	rope.default_color = Color(0.75, 0.63, 0.43)
	_ground.add_child(rope)
	# The slipway: concrete fading into the water.
	var slip := Polygon2D.new()
	var s := Island.SLIPWAY
	slip.polygon = PackedVector2Array([s.position, Vector2(s.end.x, s.position.y), s.end, Vector2(s.position.x, s.end.y)])
	var concrete := Color(0.77, 0.75, 0.71)
	slip.vertex_colors = PackedColorArray([concrete, concrete, Color(concrete, 0.0), Color(concrete, 0.0)])
	_ground.add_child(slip)
	# The harbour master's boathouse, its front on the quay: a named place, like the shops.
	var picture: Texture2D = load(BUILDING_ART % "harbour")
	var size := Vector2(picture.get_size())
	_building("harbour", picture, Rect2(Vector2(Island.BUILDING_CENTRE_X - size.x / 2.0, quay.position.y - 10.0 - size.y), size),
		true, false)
	# The land pad: a boat drawn on it, for what you will become. (The screen swaps a vehicle
	# that stops on a pad: Island.LAND_PAD, Island.MOORING.)
	_ground.add_child(_flat(_rect_points(Island.LAND_PAD, 30.0), PAD_COLOUR))
	_outline_rect(Island.LAND_PAD, 30.0, Color.WHITE, 8.0)
	_icon(Island.LAND_PAD.get_center(), &"boat", Color.WHITE)
	# The pier: planks out to the mooring, posts down both sides; a wall to boats.
	var pier := Island.PIER
	_ground.add_child(_flat(_rect_points(Rect2(pier.position + Vector2(14, 14), pier.size)), Color(0, 0, 0, 0.18)))
	_ground.add_child(_textured(_rect_points(pier), PLANKS))
	y = pier.position.y + 60.0
	while y < pier.end.y + 40.0:
		for post_x in [pier.position.x - 6.0, pier.end.x + 6.0]:
			_sprite(MOORING_POST, Vector2(post_x, y), 56.0)
		y += 150.0
	var pier_shape := CollisionShape2D.new()
	var pier_box := RectangleShape2D.new()
	pier_box.size = pier.size + Vector2(24, 0)
	pier_shape.shape = pier_box
	pier_shape.position = pier.get_center()
	_wall(Car.LAYER_LAND_EDGE, "Pier").add_child(pier_shape)
	# The mooring: water in a ring of floating buoys, a car drawn on it.
	var mooring := Island.MOORING
	_ground.add_child(_flat(_rect_points(mooring, 60.0), Color(1, 1, 1, 0.27)))
	var ring := _rect_points(mooring, 60.0)
	for i in range(0, ring.size(), 3):
		if ring[i].y < mooring.position.y + 30.0 and absf(ring[i].x - mooring.get_center().x) < 100.0:
			continue  # the pier side stays open
		_ground.add_child(_buoy(ring[i], 17.0, Color(0.98, 0.78, 0.16) if i % 2 else Color.WHITE))
	_icon(mooring.get_center() + Vector2(0, 30), &"car", Color(1, 1, 1, 0.78))
	# Boats tied up beside the pier and the quay: bumpers to a boat sailing in.
	for moored: Array in [["res://art/boats/tugboat.png", Vector2(pier.position.x - 110.0, 8880), 150.0, PI / 2.0],
			["res://art/boats/duck.png", Vector2(pier.end.x + 100.0, 8820), 120.0, PI / 2.0],
			["res://art/boats/swan.png", Vector2(4120, 8780), 120.0, PI * 0.62]]:
		_sprite(load(moored[0]), moored[1], moored[2], moored[3])
		_add_circle(moored[1], moored[2] * 0.3)
	_sprite(SAILBOAT, Vector2(5840, 8800), 200.0)
	_add_circle(Vector2(5840, 8860), 50.0)


## The snowy hill's ground (§33), over the sea: its shallows and foam, an icy rim, the snow,
## the frozen lake, the hill shaded lighter towards its top, the sledging run's ice; and the
## road out to it from the ring road, over the bridge.
func _build_snow_ground() -> void:
	for k in 3:
		var band := _textured(SnowIsland.outline(SnowIsland.SHALLOWS * (1.0 - 0.3 * k)), SHALLOWS)
		band.color = Color(1, 1, 1, 0.25)
		_ground.add_child(band)
	var foam := Line2D.new()
	foam.points = SnowIsland.outline(18.0)
	foam.closed = true
	foam.width = 26.0
	foam.default_color = FOAM
	_ground.add_child(foam)
	_ground.add_child(_flat(SnowIsland.outline(0.0), ICE_RIM_COLOUR))
	_ground.add_child(_textured(SnowIsland.outline(-SnowIsland.ICE_RIM), SNOW))
	# The hill: a soft shadow down its south-east side, then rings ever lighter to the top,
	# each nudged towards the light in the north-west.
	var hill := SnowIsland.HILL
	var radius := SnowIsland.HILL_RADIUS
	_ground.add_child(_disc_fine(hill + Vector2(60, 80), radius * 1.02, Color(0.55, 0.62, 0.8, 0.28)))
	for k in 7:
		var t := float(k) / 7.0
		_ground.add_child(_disc_fine(hill - Vector2(1, 1) * 40.0 * t, radius * (1.0 - t * 0.92),
			Color(0.9, 0.93, 1.0).lerp(Color.WHITE, t) * Color(1, 1, 1, 0.55)))
	# The lake: a bank of snow, then the ice.
	var lake := PackedVector2Array()
	var bank := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		lake.append(SnowIsland.LAKE + Vector2(cos(a), sin(a)) * SnowIsland.LAKE_RADII)
		bank.append(SnowIsland.LAKE + Vector2(cos(a), sin(a)) * (SnowIsland.LAKE_RADII + Vector2(40, 40)))
	_ground.add_child(_flat(bank, Color(0.97, 0.98, 1.0)))
	_ground.add_child(_textured(lake, ICE))
	# The sledging run: a lane of ice from near the top down the hill.
	var along := (SnowIsland.SLED_TO - SnowIsland.SLED_FROM).normalized()
	var across := along.orthogonal() * SnowIsland.SLED_HALF
	var lane := PackedVector2Array([SnowIsland.SLED_FROM + across, SnowIsland.SLED_TO + across,
		SnowIsland.SLED_TO - across, SnowIsland.SLED_FROM - across])
	_ground.add_child(_textured(lane, ROAD_ICE))
	# The road out to it from the ring road, over the bridge.
	_bridge_road(SnowIsland.bridge_rect(), SnowIsland.shore_x())


## A road out over the water to a district (§33–§37): kerbs and asphalt from the ring road,
## a dashed line down the middle, and over the water the bridge's stone parapets (up to
## `shore`, the x (a road going east or west) or y (north or south) where it comes ashore) and the
## shadows of its piers.
func _bridge_road(road: Rect2, shore: float) -> void:
	# Worked out along the road (from the town outwards) and across it, then turned to the way
	# it goes.
	var way := _bridge_way(road)
	var side_way := way.orthogonal()
	var turn := func(along: float, across: float) -> Vector2:
		return way * along + side_way * across
	var span := func(along_from: float, along_to: float, across_from: float, across_to: float) -> Rect2:
		return Rect2(turn.call(along_from, across_from), Vector2.ZERO).expand(turn.call(along_to, across_to))
	var middle := road.get_center().dot(side_way)
	var half := absf(road.size.dot(side_way)) / 2.0
	var water_from := _coast_along(road).dot(way) - 120.0
	var reach := shore * (way.x + way.y)
	var at := water_from + 200.0
	while at < reach - 300.0:
		_ground.add_child(_flat(_rect_points(span.call(at - 70.0, at + 70.0, middle - half - 40.0, middle + half + 40.0)), Color(0.1, 0.2, 0.35, 0.35)))
		at += 700.0
	var kerb := Vector2(absf(side_way.x), absf(side_way.y)) * 7.0
	_ground.add_child(_flat(_rect_points(road.grow_individual(kerb.x, kerb.y, kerb.x, kerb.y)), KERB_COLOUR))
	_ground.add_child(_textured(_rect_points(road), ASPHALT))
	var dash := Line2D.new()
	var centre := road.get_center()
	var long := way * (absf(road.size.dot(way)) / 2.0 - 60.0)
	dash.points = PackedVector2Array([centre - long, centre + long])
	dash.width = 10.0
	dash.texture = _dash_texture()
	dash.texture_mode = Line2D.LINE_TEXTURE_TILE
	dash.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground.add_child(dash)
	for side in [-1.0, 1.0]:
		var edge: float = middle + side * (half + 4.0)
		_ground.add_child(_flat(_rect_points(span.call(water_from, reach, edge - 14.0, edge + 14.0)), PARAPET))
		var post := water_from
		while post < reach:
			_ground.add_child(_flat(_rect_points(span.call(post - 18.0, post + 18.0, edge - 20.0, edge + 20.0)), PARAPET.darkened(0.25)))
			post += 350.0


## Which way a bridge's road goes out from the town: east, west, north or south.
static func _bridge_way(road: Rect2) -> Vector2:
	if road.size.x > road.size.y:
		return Vector2.RIGHT if road.get_center().x > TownLayout.world_size().x / 2.0 else Vector2.LEFT
	return Vector2.UP if road.get_center().y < TownLayout.world_size().y / 2.0 else Vector2.DOWN


## Where the town's island's waterline crosses the middle of a bridge's road: the crossing
## furthest out the way the road goes.
static func _coast_along(road: Rect2) -> Vector2:
	var way := _bridge_way(road)
	var across := way.orthogonal()
	var middle := road.get_center().dot(across)
	var best := Vector2.INF
	var loop := Island.outline(0.0)
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var da := a.dot(across) - middle
		var db := b.dot(across) - middle
		if da * db > 0.0 or da == db:
			continue
		var p := a.lerp(b, da / (da - db))
		if best == Vector2.INF or p.dot(way) > best.dot(way):
			best = p
	return best


## A finer disc than _disc, for the big hill's rings.
func _disc_fine(at: Vector2, radius: float, colour: Color) -> Polygon2D:
	var points := PackedVector2Array()
	for k in 72:
		points.append(at + Vector2.from_angle(TAU * k / 72.0) * radius)
	return _flat(points, colour)


## The snowy hill's things (§33): pine woods round the edge, snowmen, the sledging run's flags,
## and a flag on the top of the hill.
func _build_snow() -> void:
	var keep_off: Array[Rect2] = [Rect2(SnowIsland.HILL - Vector2.ONE * 150.0, Vector2.ONE * 300.0)]
	for gate in gates:
		if gate["track_id"] == SnowIsland.SNOWY_PEAK:
			keep_off.append(gate["area"].grow(260.0))
			keep_off.append(Rect2(gate["at"] - Vector2(1100, 260), Vector2(560, 520)))  # its stopwatch
	var clear := func(spot: Vector2, gap: float) -> bool:
		if not Geometry2D.is_point_in_polygon(spot, SnowIsland.outline(-SnowIsland.ICE_RIM - 120.0)):
			return false
		if SnowIsland.surface(spot) == &"ice" or SnowIsland.bridge_rect().grow(gap).has_point(spot):
			return false
		if (spot - SnowIsland.LAKE).length() < SnowIsland.LAKE_RADII.x + gap:
			return false
		if Geometry2D.get_closest_point_to_segment(spot, SnowIsland.SLED_FROM, SnowIsland.SLED_TO).distance_to(spot) < SnowIsland.SLED_HALF + gap:
			return false
		return not keep_off.any(func(r: Rect2) -> bool: return r.grow(gap).has_point(spot))
	# Pine woods: clumps near the shore and a few on the hill's lower slopes.
	var placed: Array[Vector2] = []
	for i in 600:
		if placed.size() >= 70:
			break
		var a := _rng.randf() * TAU
		var reach := _rng.randf_range(0.55, 0.92)
		var spot := SnowIsland.CENTRE + Vector2(cos(a), sin(a)) * SnowIsland.RADII * reach
		if not clear.call(spot, 80.0) or placed.any(func(p: Vector2) -> bool: return p.distance_to(spot) < 210.0):
			continue
		if spot.distance_to(SnowIsland.HILL) < SnowIsland.HILL_RADIUS * 0.6:
			continue
		placed.append(spot)
		var pine := _sprite(PINE, spot, 230.0 * _rng.randf_range(0.8, 1.15), _rng.randf() * TAU)
		pine.z_index = TREE_Z
		_add_circle(spot, TREE_TRUNK)
	# Snowmen, here and there on the flat.
	var snowmen := 0
	for i in 300:
		if snowmen >= 9:
			break
		var spot := SnowIsland.CENTRE + Vector2(_rng.randf_range(-0.8, 0.8), _rng.randf_range(-0.75, 0.75)) * SnowIsland.RADII
		if not clear.call(spot, 140.0) or placed.any(func(p: Vector2) -> bool: return p.distance_to(spot) < 260.0):
			continue
		if spot.distance_to(SnowIsland.HILL) < SnowIsland.HILL_RADIUS + 100.0:
			continue
		placed.append(spot)
		var man := _sprite(SNOWMAN, spot, 130.0, _rng.randf_range(-0.3, 0.3))
		man.z_index = TREE_Z
		_add_circle(spot, 34.0)
		snowmen += 1
	# Flags down both sides of the sledging run, red and blue.
	var along := (SnowIsland.SLED_TO - SnowIsland.SLED_FROM).normalized()
	var length := SnowIsland.SLED_FROM.distance_to(SnowIsland.SLED_TO)
	var k := 0
	var d := 120.0
	while d < length:
		for side in [-1.0, 1.0]:
			var at: Vector2 = SnowIsland.SLED_FROM + along * d + along.orthogonal() * side * (SnowIsland.SLED_HALF + 30.0)
			_things.add_child(_flag(at, Color(0.9, 0.22, 0.27) if k % 2 == 0 else Color(0.23, 0.53, 1.0), 60.0))
		k += 1
		d += 230.0
	# The top of the hill: a cairn of snow and a big flag.
	_things.add_child(_disc(SnowIsland.HILL, 70.0, Color(0.85, 0.88, 0.95)))
	var top := _flag(SnowIsland.HILL, Color(0.9, 0.22, 0.27), 150.0)
	top.z_index = TREE_Z
	_things.add_child(top)
	_add_circle(SnowIsland.HILL, 40.0)


## A flag on a pole, seen from above and a little from the side: the pole's dot and a
## triangle of cloth blowing east.
func _flag(at: Vector2, colour: Color, size: float) -> Node2D:
	var flag := Node2D.new()
	flag.position = at
	var pole := Line2D.new()
	pole.points = PackedVector2Array([Vector2.ZERO, Vector2(0, -size)])
	pole.width = size * 0.08
	pole.default_color = Color(0.3, 0.3, 0.34)
	flag.add_child(pole)
	var cloth := Polygon2D.new()
	cloth.polygon = PackedVector2Array([Vector2(0, -size), Vector2(size * 0.7, -size * 0.82), Vector2(0, -size * 0.62)])
	cloth.color = colour
	flag.add_child(cloth)
	return flag


## Candy land's ground (§34): pale water and foam round it, a rim of white icing, the pink;
## the road over the bridge and on to Candy Lane, the lane itself with red-and-white kerbs and
## a dashed middle line, and the chocolate lake inside it.
func _build_candy_ground() -> void:
	for k in 3:
		var band := _textured(CandyIsland.outline(CandyIsland.SHALLOWS * (1.0 - 0.3 * k)), SHALLOWS)
		band.color = Color(1, 1, 1, 0.25)
		_ground.add_child(band)
	var foam := Line2D.new()
	foam.points = CandyIsland.outline(18.0)
	foam.closed = true
	foam.width = 26.0
	foam.default_color = FOAM
	_ground.add_child(foam)
	_ground.add_child(_flat(CandyIsland.outline(0.0), ICING_RIM_COLOUR))
	_ground.add_child(_textured(CandyIsland.outline(-CandyIsland.ICING_RIM), CANDY_GROUND))
	_bridge_road(CandyIsland.bridge_rect(), CandyIsland.shore_x())
	# Candy Lane: asphalt between two ovals, the pink again inside, kerbs along both edges.
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var middle := CandyIsland.lane_line()
	for p in middle:
		var out := (p - CandyIsland.CENTRE).normalized()
		outer.append(p + out * CandyIsland.LANE_HALF)
		inner.append(p - out * CandyIsland.LANE_HALF)
	_ground.add_child(_textured(outer, ASPHALT))
	_ground.add_child(_textured(inner, CANDY_GROUND))
	for edge in [outer, inner]:
		var kerb := Line2D.new()
		kerb.points = edge
		kerb.closed = true
		kerb.width = 26.0
		kerb.texture = CANDY_KERB
		kerb.texture_mode = Line2D.LINE_TEXTURE_TILE
		kerb.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_ground.add_child(kerb)
	var dash := Line2D.new()
	dash.points = middle
	dash.closed = true
	dash.width = 10.0
	dash.texture = _dash_texture()
	dash.texture_mode = Line2D.LINE_TEXTURE_TILE
	dash.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground.add_child(dash)
	# The chocolate lake: a darker bank, then the chocolate.
	var lake := PackedVector2Array()
	var bank := PackedVector2Array()
	for k in 48:
		var a := TAU * k / 48.0
		lake.append(CandyIsland.LAKE + Vector2(cos(a), sin(a)) * CandyIsland.LAKE_RADII)
		bank.append(CandyIsland.LAKE + Vector2(cos(a), sin(a)) * (CandyIsland.LAKE_RADII + Vector2(40, 40)))
	_ground.add_child(_flat(bank, Color(0.36, 0.2, 0.12)))
	_ground.add_child(_textured(lake, CHOCOLATE))


## Candy land's things (§34): jelly pads on Candy Lane that bounce a car into the air, candy
## canes either side of the way in, lollipop trees, giant cupcakes and donuts, and gumdrops.
## Their own random numbers, so the rest of the town stays where it was.
func _build_candy() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3434
	for i in CandyIsland.JELLY_ANGLES.size():
		var a: float = CandyIsland.JELLY_ANGLES[i]
		_jelly(CandyIsland.lane_at(a), CandyIsland.lane_along(a), JELLY_COLOURS[i % JELLY_COLOURS.size()])
	# Candy canes where the road meets Candy Lane (the one below the road stands further off,
	# so it does not lean over the road).
	var gate_x := CandyIsland.CENTRE.x - CandyIsland.LANE_RADII.x - CandyIsland.LANE_HALF - 90.0
	for side in [-1.0, 1.0]:
		var at := Vector2(gate_x, CandyIsland.BRIDGE_Y + side * CandyIsland.BRIDGE_HALF + (-50.0 if side < 0 else 230.0))
		var cane := _candy_cane(at, 190.0, side)
		cane.z_index = TREE_Z
		_things.add_child(cane)
		_add_circle(at, 22.0)
	var keep_off: Array[Rect2] = []
	for gate in gates:
		if gate["track_id"] == CandyIsland.CANDY_LANE:
			keep_off.append(gate["area"].grow(260.0))
			keep_off.append(Rect2(gate["at"] - Vector2(1100, 260), Vector2(560, 520)))  # its stopwatch
	var placed: Array[Vector2] = []
	var clear := func(spot: Vector2, gap: float) -> bool:
		if not Geometry2D.is_point_in_polygon(spot, CandyIsland.outline(-CandyIsland.ICING_RIM - 120.0)):
			return false
		if CandyIsland.surface(spot) != &"candy" or CandyIsland.bridge_rect().grow(gap).has_point(spot):
			return false
		if absf(((spot - CandyIsland.CENTRE) / CandyIsland.LANE_RADII).length() - 1.0) * CandyIsland.LANE_RADII.y < CandyIsland.LANE_HALF + gap:
			return false
		if ((spot - CandyIsland.LAKE) / (CandyIsland.LAKE_RADII + Vector2.ONE * gap)).length() < 1.0:
			return false
		if placed.any(func(p: Vector2) -> bool: return p.distance_to(spot) < gap + 120.0):
			return false
		return not keep_off.any(func(r: Rect2) -> bool: return r.grow(gap).has_point(spot))
	var scatter := func(count: int, texture: Texture2D, size: float, solid: float, gap: float, z: int) -> void:
		var made := 0
		for i in 800:
			if made >= count:
				break
			var spot := CandyIsland.CENTRE + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * CandyIsland.RADII
			if not clear.call(spot, gap):
				continue
			placed.append(spot)
			var sprite := _sprite(texture, spot, size * rng.randf_range(0.85, 1.1), rng.randf_range(-0.3, 0.3))
			sprite.z_index = z
			_add_circle(spot, solid)
			made += 1
	scatter.call(6, CUPCAKE, 240.0, 80.0, 120.0, 0)
	scatter.call(6, DONUT, 230.0, 75.0, 120.0, 0)
	scatter.call(45, LOLLIPOP, 210.0, 26.0, 80.0, TREE_Z)
	scatter.call(24, GUMDROP, 100.0, 30.0, 60.0, 0)


## A jelly pad on Candy Lane: a wobbly square of jelly across the road; a car driving over it
## goes up in the air with a boing (like a jump ramp's hop, either way along the lane).
func _jelly(at: Vector2, along: Vector2, colour: Color) -> void:
	var area := Area2D.new()
	area.name = "Jelly"
	area.position = at
	area.rotation = along.angle()
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = Car.LAYER_CARS_GROUND
	var trigger := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = CandyIsland.JELLY_SIZE
	trigger.shape = box
	area.add_child(trigger)
	var jelly := Node2D.new()
	jelly.name = "Picture"
	var half := CandyIsland.JELLY_SIZE / 2.0
	jelly.add_child(_flat(_rect_points(Rect2(-half + Vector2(8, 10), CandyIsland.JELLY_SIZE), 34.0), Color(0, 0, 0, 0.2)))
	jelly.add_child(_flat(_rect_points(Rect2(-half, CandyIsland.JELLY_SIZE), 34.0), colour))
	jelly.add_child(_flat(_rect_points(Rect2(-half + Vector2(16, 16), CandyIsland.JELLY_SIZE - Vector2(32, 32)), 24.0), colour.lightened(0.25)))
	jelly.add_child(_flat(_rect_points(Rect2(-half + Vector2(26, 24), Vector2(34, 60)), 14.0), Color(1, 1, 1, 0.55)))
	area.add_child(jelly)
	area.body_entered.connect(func(body: Node2D) -> void:
		if body is Car and not body is Boat and not body is Kid and body.velocity.length() > 150.0:
			CarHop.launch(body)
			var wobble := jelly.create_tween()
			wobble.tween_property(jelly, "scale", Vector2(1.25, 0.8), 0.08)
			wobble.tween_property(jelly, "scale", Vector2(0.88, 1.12), 0.12)
			wobble.tween_property(jelly, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT))
	_things.add_child(area)


## A candy cane stood on end, seen from above and a little from the side: a striped pole and
## its hook, curling `side` (-1 left, 1 right).
func _candy_cane(at: Vector2, size: float, side: float) -> Node2D:
	var cane := Node2D.new()
	cane.position = at
	var points := PackedVector2Array([Vector2.ZERO, Vector2(0, -size * 0.75)])
	for k in range(1, 9):
		var a := PI * k / 8.0
		points.append(Vector2(side * size * 0.16 * (1.0 - cos(a)), -size * 0.75 - sin(a) * size * 0.16))
	var line := Line2D.new()
	line.points = points
	line.width = size * 0.11
	line.texture = _cane_texture()
	line.texture_mode = Line2D.LINE_TEXTURE_TILE
	line.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	cane.add_child(line)
	return cane


## Red and white stripes for a candy cane.
static func _cane_texture() -> ImageTexture:
	var image := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 32:
			image.set_pixel(x, y, Color(0.9, 0.16, 0.22) if (x + y) % 32 < 16 else Color(1, 0.97, 0.97))
	return ImageTexture.create_from_image(image)


## The jungle's ground (§35): pale water and foam round it, a strip of sand, the jungle floor;
## the road over the bridge and on to the jungle trail, the trail with its kerbs and dashed
## middle line, the mud pools on it, and the temple's stone courtyard and stepped pyramid.
func _build_jungle_ground() -> void:
	for k in 3:
		var band := _textured(JungleIsland.outline(JungleIsland.SHALLOWS * (1.0 - 0.3 * k)), SHALLOWS)
		band.color = Color(1, 1, 1, 0.25)
		_ground.add_child(band)
	var foam := Line2D.new()
	foam.points = JungleIsland.outline(18.0)
	foam.closed = true
	foam.width = 26.0
	foam.default_color = FOAM
	_ground.add_child(foam)
	_ground.add_child(_textured(JungleIsland.outline(0.0), BEACH))
	_ground.add_child(_textured(JungleIsland.outline(-JungleIsland.SAND_RIM), JUNGLE_GROUND))
	_bridge_road(JungleIsland.bridge_rect(), JungleIsland.shore_y())
	# The trail: asphalt between two wobbly loops, the jungle again inside, kerbs on both edges.
	var outer := PackedVector2Array()
	var inner := PackedVector2Array()
	var middle := JungleIsland.trail_line()
	for i in middle.size():
		var out := JungleIsland.trail_along(TAU * i / middle.size()).orthogonal()  # outwards
		outer.append(middle[i] + out * JungleIsland.TRAIL_HALF)
		inner.append(middle[i] - out * JungleIsland.TRAIL_HALF)
	_ground.add_child(_textured(outer, ASPHALT))
	_ground.add_child(_textured(inner, JUNGLE_GROUND))
	for edge in [outer, inner]:
		var kerb := Line2D.new()
		kerb.points = edge
		kerb.closed = true
		kerb.width = 26.0
		kerb.texture = JUNGLE_KERB
		kerb.texture_mode = Line2D.LINE_TEXTURE_TILE
		kerb.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_ground.add_child(kerb)
	var dash := Line2D.new()
	dash.points = middle
	dash.closed = true
	dash.width = 10.0
	dash.texture = _dash_texture()
	dash.texture_mode = Line2D.LINE_TEXTURE_TILE
	dash.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground.add_child(dash)
	# The temple's courtyard: big stone slabs over the trail.
	var court := JungleIsland.courtyard()
	_ground.add_child(_flat(_rect_points(court.grow(14.0), 20.0), STONE.darkened(0.3)))
	_ground.add_child(_flat(_rect_points(court, 16.0), STONE))
	for k in range(1, 6):
		var x := court.position.x + court.size.x * k / 6.0
		_ground.add_child(_line(PackedVector2Array([Vector2(x, court.position.y), Vector2(x, court.end.y)]), STONE.darkened(0.18), 5.0))
	for k in range(1, 4):
		var y := court.position.y + court.size.y * k / 4.0
		_ground.add_child(_line(PackedVector2Array([Vector2(court.position.x, y), Vector2(court.end.x, y)]), STONE.darkened(0.18), 5.0))
	# Mud pools on the trail: a darker splash round each, then the mud.
	for a in JungleIsland.MUD_ANGLES:
		var along := JungleIsland.trail_along(a)
		var pool := PackedVector2Array()
		var splash := PackedVector2Array()
		for k in 40:
			var t := TAU * k / 40.0
			var wobble := 1.0 + 0.06 * sin(t * 5.0 + a)
			var r := JungleIsland.MUD_RADII * wobble
			pool.append(JungleIsland.trail_at(a) + along * cos(t) * r.x + along.orthogonal() * sin(t) * r.y)
			splash.append(JungleIsland.trail_at(a) + along * cos(t) * (r.x + 30.0) + along.orthogonal() * sin(t) * (r.y + 26.0))
		_ground.add_child(_flat(splash, Color(0.3, 0.2, 0.12, 0.5)))
		_ground.add_child(_textured(pool, MUD))


func _line(points: PackedVector2Array, colour: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = colour
	return line


## The jungle's things (§35): the stepped pyramid and the temple's pillars, thick jungle
## trees, boulders and flowers. Their own random numbers, so the rest of the town stays where
## it was.
func _build_jungle() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3535
	# The pyramid: steps of stone, each smaller and lighter, stairs up the front, moss.
	var pyramid := JungleIsland.pyramid()
	_things.add_child(_flat(_rect_points(pyramid.grow(10.0).grow_individual(0, 0, 30, 30), 10.0), Color(0, 0, 0, 0.22)))
	for k in 4:
		var step := pyramid.grow_individual(-48.0 * k, -40.0 * k, -48.0 * k, -16.0 * k)
		_things.add_child(_flat(_rect_points(step, 8.0), STONE.darkened(0.25 - 0.08 * k)))
	var stairs := Rect2(pyramid.get_center().x - 70.0, pyramid.position.y + 130.0, 140.0, pyramid.size.y - 130.0)
	_things.add_child(_flat(_rect_points(stairs), STONE.lightened(0.15)))
	for y in range(int(stairs.position.y) + 20, int(stairs.end.y), 26):
		_things.add_child(_line(PackedVector2Array([Vector2(stairs.position.x, y), Vector2(stairs.end.x, y)]), STONE.darkened(0.2), 4.0))
	var top := Rect2(pyramid.get_center().x - 90.0, pyramid.position.y + 110.0, 180.0, 70.0)
	_things.add_child(_flat(_rect_points(top, 6.0), STONE.darkened(0.45)))  # the dark doorway at the top
	for k in 7:
		var at := Vector2(pyramid.position.x + rng.randf() * pyramid.size.x, pyramid.position.y + rng.randf() * pyramid.size.y * 0.5)
		_things.add_child(_disc(at, rng.randf_range(16.0, 30.0), MOSS))
	_add_box(pyramid.grow(-10.0))
	# The courtyard's pillars, in two rows either side of the trail.
	var court := JungleIsland.courtyard()
	for row in [-220.0, 220.0]:
		for k in 4:
			var at := Vector2(court.position.x + 90.0 + (court.size.x - 180.0) * k / 3.0, court.get_center().y + row)
			_things.add_child(_disc(at + Vector2(6, 10), 46.0, Color(0, 0, 0, 0.22)))
			_things.add_child(_disc(at, 42.0, STONE.darkened(0.1)))
			_things.add_child(_disc(at - Vector2(6, 8), 30.0, STONE.lightened(0.1)))
			_things.add_child(_disc(at + Vector2(14, -14), 12.0, MOSS))
			_add_circle(at, 40.0)
	var keep_off: Array[Rect2] = [court.grow(80.0), pyramid.grow(120.0)]
	for gate in gates:
		if gate["track_id"] == JungleIsland.JUNGLE_RUN:
			keep_off.append(gate["area"].grow(260.0))
			keep_off.append(Rect2(gate["at"] - Vector2(1100, 260), Vector2(560, 520)))  # its stopwatch
	var placed: Array[Vector2] = []
	var clear := func(spot: Vector2, gap: float, room: float) -> bool:
		if not Geometry2D.is_point_in_polygon(spot, JungleIsland.outline(-JungleIsland.SAND_RIM - 60.0)):
			return false
		if JungleIsland.surface(spot) != &"jungle" or JungleIsland.bridge_rect().grow(gap).has_point(spot):
			return false
		var trail := JungleIsland.trail_line()
		for i in range(0, trail.size(), 2):
			if trail[i].distance_to(spot) < JungleIsland.TRAIL_HALF + gap + 40.0:
				return false
		if placed.any(func(p: Vector2) -> bool: return p.distance_to(spot) < room):
			return false
		return not keep_off.any(func(r: Rect2) -> bool: return r.grow(gap).has_point(spot))
	var scatter := func(count: int, texture: Texture2D, size: float, solid: float, gap: float, room: float, z: int) -> void:
		var made := 0
		for i in 2000:
			if made >= count:
				break
			var spot := JungleIsland.CENTRE + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * JungleIsland.RADII
			if not clear.call(spot, gap, room):
				continue
			placed.append(spot)
			var sprite := _sprite(texture, spot, size * rng.randf_range(0.85, 1.15), rng.randf() * TAU)
			sprite.z_index = z
			if solid > 0.0:
				_add_circle(spot, solid)
			made += 1
	scatter.call(14, BOULDER, 130.0, 46.0, 60.0, 200.0, 0)
	scatter.call(110, JUNGLE_TREE, 280.0, TREE_TRUNK, 70.0, 210.0, TREE_Z)
	scatter.call(40, JUNGLE_FLOWER, 110.0, 0.0, 30.0, 120.0, 0)


## Toy town's ground (§36): pale water and foam round it, a strip of sand, then the play mat in
## patchwork squares with stitched edges; the road over the bridge and on round the mat with
## kerbs, a dashed middle line and zebra crossings; and the toy train's track inside it.
func _build_toy_ground() -> void:
	for k in 3:
		var band := _textured(ToyIsland.outline(ToyIsland.SHALLOWS * (1.0 - 0.3 * k)), SHALLOWS)
		band.color = Color(1, 1, 1, 0.25)
		_ground.add_child(band)
	var foam := Line2D.new()
	foam.points = ToyIsland.outline(18.0)
	foam.closed = true
	foam.width = 26.0
	foam.default_color = FOAM
	_ground.add_child(foam)
	_ground.add_child(_textured(ToyIsland.outline(0.0), BEACH))
	var mat := ToyIsland.outline(-ToyIsland.SAND_RIM)
	_ground.add_child(_flat(mat, MAT_COLOURS[0]))
	var corner := ToyIsland.CENTRE - ToyIsland.RADII
	var patch := ToyIsland.PATCH
	var stitches := _stitch_texture()
	for row in int(ceilf(ToyIsland.RADII.y * 2.0 / patch)):
		for col in int(ceilf(ToyIsland.RADII.x * 2.0 / patch)):
			var square := _rect_points(Rect2(corner + Vector2(col, row) * patch, Vector2.ONE * patch))
			for piece in Geometry2D.intersect_polygons(square, mat):
				_ground.add_child(_flat(piece, MAT_COLOURS[(row * 2 + col * 3) % MAT_COLOURS.size()]))
				var seam := Line2D.new()
				seam.points = piece
				seam.closed = true
				seam.width = 6.0
				seam.texture = stitches
				seam.texture_mode = Line2D.LINE_TEXTURE_TILE
				seam.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
				_ground.add_child(seam)
	_bridge_road(ToyIsland.bridge_rect(), ToyIsland.shore_y())
	# The road: asphalt between two rounded rectangles, the mat again inside, kerbs on both.
	var outer := ToyIsland.rounded_line(ToyIsland.ROAD_HALF_SIZE, ToyIsland.ROAD_CORNER, ToyIsland.ROAD_HALF)
	var inner := ToyIsland.rounded_line(ToyIsland.ROAD_HALF_SIZE, ToyIsland.ROAD_CORNER, -ToyIsland.ROAD_HALF)
	_ground.add_child(_textured(outer, ASPHALT))
	var middle_mat := Geometry2D.intersect_polygons(inner, mat)
	for piece in middle_mat:
		_ground.add_child(_flat(piece, MAT_COLOURS[3]))
	for edge in [outer, inner]:
		var kerb := Line2D.new()
		kerb.points = edge
		kerb.closed = true
		kerb.width = 26.0
		kerb.texture = TOWN_KERB
		kerb.texture_mode = Line2D.LINE_TEXTURE_TILE
		kerb.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_ground.add_child(kerb)
	var dash := Line2D.new()
	dash.points = ToyIsland.road_line()
	dash.closed = true
	dash.width = 10.0
	dash.texture = _dash_texture()
	dash.texture_mode = Line2D.LINE_TEXTURE_TILE
	dash.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground.add_child(dash)
	# Zebra crossings half way along each side.
	var half := ToyIsland.ROAD_HALF_SIZE
	for crossing: Array in [[Vector2(0, half.y), 0.0], [Vector2(half.x, 0), PI / 2.0], [Vector2(-half.x, 0), PI / 2.0]]:
		var at: Vector2 = ToyIsland.CENTRE + crossing[0]
		for k in range(-3, 4):
			var stripe := Polygon2D.new()
			stripe.polygon = _rect_points(Rect2(-14.0 + k * 40.0, -ToyIsland.ROAD_HALF + 10.0, 24.0, ToyIsland.ROAD_HALF * 2.0 - 20.0))
			stripe.color = Color(1, 1, 1, 0.9)
			stripe.position = at
			stripe.rotation = crossing[1]
			_ground.add_child(stripe)
	# The train's track: a bed of wooden sleepers and two rails.
	var rails := ToyIsland.rails_line()
	var sleepers := Line2D.new()
	sleepers.points = rails
	sleepers.closed = true
	sleepers.width = 96.0
	sleepers.texture = _sleeper_texture()
	sleepers.texture_mode = Line2D.LINE_TEXTURE_TILE
	sleepers.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground.add_child(sleepers)
	for offset in [-26.0, 26.0]:
		var rail := Line2D.new()
		rail.points = ToyIsland.rounded_line(ToyIsland.RAILS_HALF_SIZE, ToyIsland.RAILS_CORNER, offset)
		rail.closed = true
		rail.width = 9.0
		rail.default_color = Color(0.6, 0.62, 0.68)
		_ground.add_child(rail)


## Little white stitches, for the seams of the play mat.
static func _stitch_texture() -> ImageTexture:
	var image := Image.create(24, 4, false, Image.FORMAT_RGBA8)
	for x in 24:
		for y in 4:
			image.set_pixel(x, y, Color(1, 1, 1, 0.8) if x < 12 else Color(1, 1, 1, 0))
	return ImageTexture.create_from_image(image)


## Wooden sleepers across the train's track.
static func _sleeper_texture() -> ImageTexture:
	var image := Image.create(20, 32, false, Image.FORMAT_RGBA8)
	for x in 20:
		for y in 32:
			image.set_pixel(x, y, RAIL_COLOUR if x < 8 else Color(0, 0, 0, 0))
	return ImageTexture.create_from_image(image)


## Toy town's things (§36): the train on its track, toy houses along the outside of the road,
## giant letter blocks (some stacked), and bouncy balls (the screen puts them there). Their
## own random numbers, so the rest of the town stays where it was.
func _build_toys() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3636
	train = ToyTrain.new()
	train.name = "ToyTrain"
	train.rails = ToyIsland.rails_line()
	_things.add_child(train)
	# Houses face the road from outside it, all the way round, with gaps for the bridge's road.
	var road := ToyIsland.rounded_line(ToyIsland.ROAD_HALF_SIZE, ToyIsland.ROAD_CORNER, ToyIsland.ROAD_HALF + 190.0)
	var houses: Array[Vector2] = []
	for i in range(0, road.size(), 4):
		var at := road[i]
		if ToyIsland.bridge_rect().grow(160.0).has_point(at) or houses.any(func(p: Vector2) -> bool: return p.distance_to(at) < 320.0):
			continue
		if not Geometry2D.is_point_in_polygon(at, ToyIsland.outline(-ToyIsland.SAND_RIM - 120.0)):
			continue
		houses.append(at)
		var house := _sprite(TOY_HOUSE, at, 220.0)
		house.z_index = TREE_Z
		_add_box(Rect2(at - Vector2(80, 70), Vector2(160, 140)))
	var keep_off: Array[Rect2] = []
	for gate in gates:
		if gate["track_id"] == ToyIsland.TOY_TOWN:
			keep_off.append(gate["area"].grow(200.0))
			keep_off.append(Rect2(gate["at"] - Vector2(1100, 260), Vector2(560, 520)))  # its stopwatch
	var placed: Array[Vector2] = houses.duplicate()
	var clear := func(spot: Vector2, room: float) -> bool:
		if ToyIsland.surface(spot) != &"playmat" or ToyIsland.bridge_rect().grow(room).has_point(spot):
			return false
		if absf(ToyIsland.rounded_distance(spot, ToyIsland.ROAD_HALF_SIZE, ToyIsland.ROAD_CORNER)) < ToyIsland.ROAD_HALF + room:
			return false
		if absf(ToyIsland.rounded_distance(spot, ToyIsland.RAILS_HALF_SIZE, ToyIsland.RAILS_CORNER)) < 140.0 + room:
			return false
		if not Geometry2D.is_point_in_polygon(spot, ToyIsland.outline(-ToyIsland.SAND_RIM - 100.0)):
			return false
		if placed.any(func(p: Vector2) -> bool: return p.distance_to(spot) < room + 160.0):
			return false
		return not keep_off.any(func(r: Rect2) -> bool: return r.grow(room).has_point(spot))
	var letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
	var made := 0
	for i in 2000:
		if made >= 16:
			break
		var spot := ToyIsland.CENTRE + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * ToyIsland.RADII
		if not clear.call(spot, 90.0):
			continue
		placed.append(spot)
		var stack := 2 if made % 4 == 0 else 1
		for k in stack:
			var block := ToyBlock.new()
			block.letter = letters[(made * 7 + k * 3) % letters.length()]
			block.colour = BLOCK_COLOURS[(made + k) % BLOCK_COLOURS.size()]
			block.position = spot + Vector2(18.0, -40.0) * k
			block.rotation = rng.randf_range(-0.25, 0.25)
			block.z_index = k
			_things.add_child(block)
		_add_box(Rect2(spot - Vector2.ONE * ToyBlock.SIZE / 2.0, Vector2.ONE * ToyBlock.SIZE))
		made += 1
	var balls := 0
	for i in 2000:
		if balls >= 5:
			break
		var spot := ToyIsland.CENTRE + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * ToyIsland.RADII
		if not clear.call(spot, 140.0):
			continue
		placed.append(spot)
		beach_balls.append(spot)  # a ball to kick about: the screen puts it there
		balls += 1


## Sunny Beach's ground (§37): pale water and foam round it, sand all over, wet sand where the
## surf comes up on its west side (the waves themselves are BeachSurf), the road over the bridge,
## and the boardwalk of planks round the island with blue and white kerbs.
func _build_beach_ground() -> void:
	for k in 3:
		var band := _textured(BeachIsland.outline(BeachIsland.SHALLOWS * (1.0 - 0.3 * k)), SHALLOWS)
		band.color = Color(1, 1, 1, 0.25)
		_ground.add_child(band)
	var foam := Line2D.new()
	foam.points = BeachIsland.outline(18.0)
	foam.closed = true
	foam.width = 26.0
	foam.default_color = FOAM
	_ground.add_child(foam)
	_ground.add_child(_textured(BeachIsland.outline(0.0), BEACH))
	var wet := PackedVector2Array()
	var steps := 60
	for k in steps + 1:
		var a := PI - BeachIsland.SURF_ARC + 2.0 * BeachIsland.SURF_ARC * k / steps
		wet.append(BeachIsland.shore_point(a, -20.0 - BeachIsland.SURF_DEPTH * BeachIsland.surf_taper(a)))
	for k in range(steps, -1, -1):
		wet.append(BeachIsland.shore_point(PI - BeachIsland.SURF_ARC + 2.0 * BeachIsland.SURF_ARC * k / steps, 0.0))
	_ground.add_child(_textured(wet, WET_SAND))
	surf = BeachSurf.new()
	surf.name = "Surf"
	_ground.add_child(surf)
	_bridge_road(BeachIsland.bridge_rect(), BeachIsland.shore_x())
	var walk := Line2D.new()
	walk.points = BeachIsland.walk_line()
	walk.closed = true
	walk.width = BeachIsland.WALK_HALF * 2.0
	walk.joint_mode = Line2D.LINE_JOINT_ROUND
	walk.texture = PLANKS
	walk.texture_mode = Line2D.LINE_TEXTURE_TILE
	walk.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_ground.add_child(walk)
	for offset in [-BeachIsland.WALK_HALF, BeachIsland.WALK_HALF]:
		var kerb := Line2D.new()
		kerb.points = BeachIsland.walk_line(offset)
		kerb.closed = true
		kerb.width = 24.0
		kerb.texture = BEACH_KERB
		kerb.texture_mode = Line2D.LINE_TEXTURE_TILE
		kerb.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		_ground.add_child(kerb)


## Sunny Beach's things (§37): beach huts round the outside of the boardwalk facing it, the
## lifeguard's tower above the surf, palms by the sea, parasols with towels, sandcastles, crabs,
## and beach balls (the screen puts them there). Their own random numbers, so the rest of the
## town stays where it was.
func _build_beach() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3737
	var placed: Array[Vector2] = []
	var keep_off: Array[Rect2] = [BeachIsland.bridge_rect().grow(160.0)]
	for gate in gates:
		if gate["track_id"] == BeachIsland.SUNNY_BEACH:
			keep_off.append(gate["area"].grow(200.0))
			keep_off.append(Rect2(gate["at"] - Vector2(1100, 260), Vector2(560, 520)))  # its stopwatch
	# Huts along the north and south of the boardwalk, outside it, their doors towards it.
	var half := BeachIsland.WALK_HALF_SIZE
	var hut_k := 0
	for side in [-1.0, 1.0]:
		for k in 5:
			var x := (k - 2) * 360.0
			var at := BeachIsland.CENTRE + Vector2(x, side * (half.y + BeachIsland.WALK_HALF + 120.0))
			if keep_off.any(func(r: Rect2) -> bool: return r.grow(100.0).has_point(at)):
				continue
			var hut := BeachHut.new()
			hut.colour = HUT_COLOURS[hut_k % HUT_COLOURS.size()]
			hut.position = at
			hut.rotation = 0.0 if side > 0.0 else PI  # the door's edge towards the boardwalk
			hut.z_index = TREE_Z
			_things.add_child(hut)
			_add_box(Rect2(at - BeachHut.SIZE / 2.0 + Vector2(8, 8), BeachHut.SIZE - Vector2(16, 16)))
			placed.append(at)
			hut_k += 1
	# The lifeguard's tower, up the beach from the surf.
	var tower_at := BeachIsland.shore_point(PI + 0.25, -BeachIsland.SURF_DEPTH - 220.0)
	var tower := LifeguardTower.new()
	tower.position = tower_at
	tower.z_index = TREE_Z
	_things.add_child(tower)
	_add_box(Rect2(tower_at - Vector2(66, 66), Vector2(132, 132)))
	placed.append(tower_at)
	# Palms round the island, back from the sea and off the surf, the walk and the bridge.
	var palms := BeachIsland.outline(-200.0)
	for i in range(0, palms.size(), 7):
		var at := palms[i]
		if BeachIsland.up_the_beach(at) != INF or BeachIsland.bridge_rect().grow(250.0).has_point(at):
			continue
		var palm := _sprite(PALM, at, 220.0 * rng.randf_range(0.85, 1.1), rng.randf() * TAU)
		palm.z_index = TREE_Z
		_add_circle(at, TREE_TRUNK)
		placed.append(at)
	var clear := func(spot: Vector2, room: float) -> bool:
		if not BeachIsland.contains(spot) or BeachIsland.on_walk(spot):
			return false
		if absf(ToyIsland.rounded_distance(spot, half, BeachIsland.WALK_CORNER, BeachIsland.CENTRE)) < BeachIsland.WALK_HALF + room:
			return false
		if not Geometry2D.is_point_in_polygon(spot, BeachIsland.outline(-room - 60.0)):
			return false
		var up := BeachIsland.up_the_beach(spot)
		if up != INF and up < BeachIsland.SURF_DEPTH + room:
			return false
		if placed.any(func(p: Vector2) -> bool: return p.distance_to(spot) < room + 170.0):
			return false
		return not keep_off.any(func(r: Rect2) -> bool: return r.grow(room).has_point(spot))
	var random_spot := func() -> Vector2:
		return BeachIsland.CENTRE + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * BeachIsland.RADII
	# Parasols, each with a towel beside it.
	var made := 0
	for i in 2000:
		if made >= 10:
			break
		var spot: Vector2 = random_spot.call()
		if not clear.call(spot, 120.0):
			continue
		placed.append(spot)
		var towel := _flat(_rect_points(Rect2(-45, -80, 90, 160)), TOWEL_COLOURS[made % TOWEL_COLOURS.size()])
		towel.position = spot + Vector2(110, 30)
		towel.rotation = rng.randf_range(-0.4, 0.4)
		_ground.add_child(towel)
		for k in 3:
			var stripe := _flat(_rect_points(Rect2(-45, -50 + k * 45.0, 90, 14)), Color(1, 1, 1, 0.75))
			stripe.position = towel.position
			stripe.rotation = towel.rotation
			_ground.add_child(stripe)
		var parasol := _sprite(PARASOL, spot, 190.0, rng.randf() * TAU)
		parasol.z_index = TREE_Z
		made += 1
	# Sandcastles: knocked flat by a car, they build themselves up again.
	made = 0
	for i in 3000:
		if made >= BeachIsland.CASTLES:
			break
		var spot: Vector2 = random_spot.call()
		if not clear.call(spot, 110.0):
			continue
		placed.append(spot)
		var castle := SandCastle.new()
		castle.name = "SandCastle%d" % made
		castle.position = spot
		castle.flag = HUT_COLOURS[made % HUT_COLOURS.size()]
		_things.add_child(castle)
		castles.append(castle)
		made += 1
	# Crabs, near the sea: on the sand between the waterline and the boardwalk.
	made = 0
	for i in 3000:
		if made >= BeachIsland.CRABS:
			break
		var a := rng.randf() * TAU
		var spot := BeachIsland.shore_point(a, -rng.randf_range(250.0, 450.0))
		if BeachIsland.up_the_beach(spot) != INF or not clear.call(spot, 60.0):
			continue
		placed.append(spot)
		var crab := BeachCrab.new()
		crab.name = "Crab%d" % made
		crab.home = spot
		crab.z_index = 1
		_things.add_child(crab)
		crabs.append(crab)
		made += 1
	made = 0
	for i in 2000:
		if made >= 5:
			break
		var spot: Vector2 = random_spot.call()
		if not clear.call(spot, 140.0):
			continue
		placed.append(spot)
		beach_balls.append(spot)  # a ball to kick about: the screen puts it there
		made += 1


## Out at sea (§21.5): the lighthouse's islet, the ramp islets, the slalom, the wreck, and
## the outer limit's ring of buoys and rocks.
func _build_sea() -> void:
	var islands := _wall(Car.LAYER_LAND_EDGE, "Islets")
	_islet(Island.LIGHTHOUSE, Island.LIGHTHOUSE_RADIUS, islands, 0)
	var light := _sprite(LIGHTHOUSE, Island.LIGHTHOUSE + Vector2(0, -80), 420.0)
	light.z_index = TREE_Z
	_sea_place("lighthouse", Island.LIGHTHOUSE, LIGHTHOUSE)
	for i in Island.RAMP_ISLETS.size():
		var centre: Vector2 = Island.RAMP_ISLETS[i][0]
		var throw: Vector2 = Island.RAMP_ISLETS[i][1]
		_islet(centre, Island.RAMP_ISLET_RADIUS, islands, 1, false)
		var ramp := Area2D.new()
		ramp.name = "Ramp%d" % (i + 1)
		ramp.position = Island.ramp_at(i)
		ramp.rotation = throw.angle()
		ramp.monitorable = false
		ramp.collision_layer = 0
		ramp.collision_mask = Car.LAYER_CARS_GROUND
		var trigger := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = RAMP_TRIGGER
		trigger.shape = box
		ramp.add_child(trigger)
		var picture := Sprite2D.new()
		picture.texture = RAMP
		ramp.add_child(picture)
		ramp.body_entered.connect(func(body: Node2D) -> void:
			if body is Boat:
				body.jump())
		_things.add_child(ramp)
	var gates := Island.slalom_buoys()
	for k in gates.size():
		_things.add_child(_buoy(gates[k], 30.0, Color(0.94, 0.59, 0.16) if k % 2 else Color(0.9, 0.27, 0.24)))
		_add_circle(gates[k], 30.0)
	_islet(Island.WRECK_SANDBAR, 170.0, islands, 0, false)
	_sprite(WRECK, Island.WRECK, 420.0, 0.4)
	_sprite(CHEST, Island.WRECK_SANDBAR + Vector2(40, -10), 110.0)
	var wreck_shape := CollisionShape2D.new()
	var hull := CircleShape2D.new()
	hull.radius = 150.0
	wreck_shape.shape = hull
	wreck_shape.position = Island.WRECK
	islands.add_child(wreck_shape)
	_sea_place("shipwreck", Island.WRECK, WRECK)
	# The outer limit: red buoys all round, clumps of rock, and a wall a boat bounces off.
	var limit := Island.limit_outline()
	for i in range(0, limit.size(), 15):
		if not _near_bridge(limit[i], 120.0):
			_things.add_child(_buoy(limit[i], 30.0, Color(0.9, 0.27, 0.24)))
	for i in range(7, limit.size(), 60):
		for k in 3:
			var rock := _sprite(ROCK, limit[i] + Vector2(_rng.randf_range(-120, 120), _rng.randf_range(-120, 120)), 150.0, _rng.randf() * TAU)
			rock.visible = not _near_bridge(limit[i], 400.0)  # none on a bridge's deck
	# The bridges to the districts cross the outer limit: a gap for cars, closed to boats.
	var outer := _gaps(limit)
	var wall := _wall(Car.LAYER_WORLD, "OuterLimit")
	for run in outer:
		_wall_open(wall, run)
	var under := _wall(Car.LAYER_LAND_EDGE, "OuterLimitUnderBridge")
	for b in _bridges():
		_wall_open(under, PackedVector2Array([_end_on(outer, b, 0), _end_on(outer, b, 1)]))


## An islet: pale water round it, sand, rocks and palms; solid to a boat.
func _islet(centre: Vector2, radius: float, body: StaticBody2D, palms: int, rocks := true) -> void:
	var shape := Island.islet(centre, radius)
	var halo := PackedVector2Array()
	for p in shape:
		halo.append(centre + (p - centre) * 1.35)
	var water := _textured(halo, SHALLOWS)
	water.color = Color(1, 1, 1, 0.8)
	_ground.add_child(water)
	_ground.add_child(_textured(shape, BEACH))
	if rocks:
		for k in 4:
			var a := _rng.randf() * TAU
			_sprite(ROCK, centre + Vector2(cos(a) * radius * 0.95, sin(a) * radius * 0.75), 110.0, a)
	for k in palms:
		var palm := _sprite(PALM, centre + Vector2((k - (palms - 1) / 2.0) * 140.0, -20.0), 200.0, _rng.randf() * TAU)
		palm.z_index = TREE_Z
	var solid := CollisionPolygon2D.new()
	solid.polygon = shape
	body.add_child(solid)
	islets.append(shape)


## A place out at sea (the lighthouse, the wreck): sailing near it counts as a visit.
func _sea_place(id: String, centre: Vector2, picture: Texture2D) -> void:
	places.append({"id": id, "name": TownLayout.PLACE_NAMES[id], "door": centre, "picture": picture})
	var area := Area2D.new()
	area.name = id.capitalize().replace(" ", "") + "Visit"
	area.position = centre
	area.collision_layer = 0
	area.collision_mask = Car.LAYER_CARS_GROUND | Car.LAYER_AIRBORNE
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = SEA_PLACE_REACH
	shape.shape = circle
	area.add_child(shape)
	_things.add_child(area)
	area.body_entered.connect(func(body: Node2D) -> void:
		if body is Car and body.has_node(^"PlayerInput"):
			place_reached.emit(id, TownLayout.PLACE_NAMES[id], picture))


## What a pad turns you into, drawn on it: a boat (a hull, a sail, a wave) or a car.
func _icon(at: Vector2, kind: StringName, colour: Color) -> void:
	if kind == &"boat":
		_ground.add_child(_flat(PackedVector2Array([at + Vector2(-110, -10), at + Vector2(110, -10), at + Vector2(70, 50),
			at + Vector2(-80, 50)]), colour))
		_ground.add_child(_flat(PackedVector2Array([at + Vector2(-10, -20), at + Vector2(-10, -120), at + Vector2(70, -20)]), colour))
		var wave := Line2D.new()
		for k in 6:
			wave.add_point(at + Vector2(-130 + 50 * k, 85 if k % 2 == 0 else 70))
		wave.width = 12.0
		wave.default_color = colour
		wave.joint_mode = Line2D.LINE_JOINT_ROUND
		_ground.add_child(wave)
	else:
		_ground.add_child(_flat(_rect_points(Rect2(at + Vector2(-110, -50), Vector2(220, 80)), 26.0), colour))
		_ground.add_child(_flat(_rect_points(Rect2(at + Vector2(-60, -100), Vector2(120, 70)), 20.0), colour))
		for wheel_x in [-60.0, 60.0]:
			_ground.add_child(_disc(at + Vector2(wheel_x, 40), 30.0, colour))


## A buoy seen from above: a coloured float with a white band and a yellow top.
func _buoy(at: Vector2, radius: float, colour: Color) -> Node2D:
	var buoy := Node2D.new()
	buoy.position = at
	buoy.add_child(_disc(Vector2(3, 6) * radius / 30.0, radius, Color(0, 0, 0, 0.22)))
	buoy.add_child(_disc(Vector2.ZERO, radius, Color(0.16, 0.16, 0.2)))
	buoy.add_child(_disc(Vector2.ZERO, radius * 0.9, colour))
	buoy.add_child(_flat(_rect_points(Rect2(-radius * 0.9, -radius * 0.2, radius * 1.8, radius * 0.4)), Color.WHITE))
	buoy.add_child(_disc(Vector2.ZERO, radius * 0.3, Color(0.98, 0.86, 0.31)))
	return buoy


func _near_harbour(at: Vector2, margin: float) -> bool:
	return at.y > world_rect().end.y - 400.0 and at.x > Island.HARBOUR_X.x - margin and at.x < Island.HARBOUR_X.y + margin


## Is `at` within `margin` of a bridge's road out to a district?
static func _near_bridge(at: Vector2, margin: float) -> bool:
	return _bridges().any(func(b: Rect2) -> bool: return b.grow(margin).has_point(at))


static func _clear_of(x: float, rect: Rect2) -> bool:
	return x < rect.position.x - 40.0 or x > rect.end.x + 40.0


## The harbour road, from the ring road's kerb to the quay.
func _drive_rect() -> Rect2:
	var top := streets_rect().end.y - TownLayout.SIDEWALK - 10.0
	return Rect2(Island.DRIVE_X - Island.DRIVE_HALF, top, Island.DRIVE_HALF * 2.0, Island.QUAY.position.y - top)


## A static body for one kind of wall, on `layers`.
func _wall(layers: int, wall_name: String) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = wall_name
	body.collision_layer = layers
	body.collision_mask = 0
	add_child(body)
	return body


## An open line as a wall: a segment between each point and the next, the ends left open.
func _wall_open(body: StaticBody2D, points: PackedVector2Array) -> void:
	for i in points.size() - 1:
		var piece := CollisionShape2D.new()
		var segment := SegmentShape2D.new()
		segment.a = points[i]
		segment.b = points[i + 1]
		piece.shape = segment
		body.add_child(piece)


## A closed line round an island opened where the bridges' roads cross it: what is left, as
## open lines, each end squared onto the edge of the road it stops at, so the rails meet it.
static func _gaps(loop: PackedVector2Array) -> Array[PackedVector2Array]:
	var out: Array[PackedVector2Array] = []
	var n := loop.size()
	for i in n:
		if not (_under_bridge(loop[i]) and not _under_bridge(loop[(i + 1) % n])):
			continue
		var run := PackedVector2Array()
		var k := (i + 1) % n  # the first point past this cut, up to the next one
		while not _under_bridge(loop[k]):
			run.append(loop[k])
			k = (k + 1) % n
		run.insert(0, _square(run[0]))
		run.append(_square(run[run.size() - 1]))
		out.append(run)
	return out


## `p` moved straight across onto the nearer edge of the nearest bridge's road.
static func _square(p: Vector2) -> Vector2:
	var road := Rect2()
	var best := INF
	for b in _bridges():
		var gap := p.distance_to(p.clamp(b.position, b.end))
		if gap < best:
			best = gap
			road = b
	if road.size.y > road.size.x:
		return Vector2(road.position.x if p.x < road.get_center().x else road.end.x, p.y)
	return Vector2(p.x, road.position.y if p.y < road.get_center().y else road.end.y)


## Of `runs`, the end lying on one edge of the bridge `road` (`side` 0: its north or west
## edge, 1: its south or east one).
static func _end_on(runs: Array, road: Rect2, side: int) -> Vector2:
	var north := road.size.y > road.size.x
	var edge := (road.end.x if side else road.position.x) if north else (road.end.y if side else road.position.y)
	for run: PackedVector2Array in runs:
		for p in [run[0], run[run.size() - 1]]:
			if road.grow(300.0).has_point(p) and absf((p.x if north else p.y) - edge) < 0.5:
				return p
	return Vector2.INF


## The roads out over the water to the districts (§33–§37), each from the ring road to the
## district's own roads.
static func _bridges() -> Array[Rect2]:
	return [SnowIsland.bridge_rect(), CandyIsland.bridge_rect(), JungleIsland.bridge_rect(), ToyIsland.bridge_rect(),
		BeachIsland.bridge_rect()]


static func _under_bridge(p: Vector2) -> bool:
	return _bridges().any(func(b: Rect2) -> bool: return b.has_point(p))


## A closed line as a wall: solid along its edges only, so it holds things on either side.
func _wall_line(body: StaticBody2D, points: PackedVector2Array) -> void:
	var line := CollisionPolygon2D.new()
	line.build_mode = CollisionPolygon2D.BUILD_SEGMENTS
	line.polygon = points
	body.add_child(line)


func _sprite(texture: Texture2D, at: Vector2, size: float, angle := 0.0) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.position = at
	sprite.rotation = angle
	sprite.scale = Vector2.ONE * size / maxf(texture.get_width(), texture.get_height())
	_things.add_child(sprite)
	return sprite


func _disc(at: Vector2, radius: float, colour: Color) -> Polygon2D:
	var points := PackedVector2Array()
	for k in 20:
		points.append(at + Vector2.from_angle(TAU * k / 20.0) * radius)
	return _flat(points, colour)


func _outline_rect(rect: Rect2, radius: float, colour: Color, width: float) -> void:
	var line := Line2D.new()
	line.points = _rect_points(rect, radius)
	line.closed = true
	line.width = width
	line.default_color = colour
	_ground.add_child(line)


func _add_box(rect: Rect2) -> void:
	solid_boxes.append(rect)
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	_solid.add_child(shape)


func _add_circle(centre: Vector2, radius: float) -> void:
	solid_circles.append(Vector3(centre.x, centre.y, radius))
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = radius
	shape.shape = circle
	shape.position = centre
	_solid.add_child(shape)


func _textured(points: PackedVector2Array, texture: Texture2D) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.texture = texture
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	if texture == GRASS:
		poly.material = LIVING_GROUND  # swaying tufts and daisies
	return poly


func _flat(points: PackedVector2Array, colour: Color) -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = colour
	return poly


## A rectangle's outline, its corners rounded by `radius`.
static func _rect_points(rect: Rect2, radius := 0.0) -> PackedVector2Array:
	if radius <= 0.0:
		return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)])
	var out := PackedVector2Array()
	var corners := [Vector2(rect.end.x - radius, rect.end.y - radius), Vector2(rect.position.x + radius, rect.end.y - radius),
		Vector2(rect.position.x + radius, rect.position.y + radius), Vector2(rect.end.x - radius, rect.position.y + radius)]
	for i in 4:
		for k in 9:
			out.append(corners[i] + Vector2.from_angle(PI * 0.5 * i + PI * 0.5 * k / 8.0) * radius)
	return out


static func _dash_texture() -> ImageTexture:
	var image := Image.create(160, 10, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0))
	image.fill_rect(Rect2i(0, 0, 80, 10), Color.WHITE)
	return ImageTexture.create_from_image(image)


# --- things to do (§23) -----------------------------------------------------------------

## Before anything grows: the grass the bus shelters and the ramps' run-ups need, so no tree
## or flower bed is planted there.
func _plan_extras() -> void:
	for entry: Array in TownLayout.BUS_STOPS:
		var a: Vector2i = entry[0]
		var b: Vector2i = entry[1]
		var along := heading(a, b)
		var side := right_of(along)
		var middle: Vector2 = junctions[a].lerp(junctions[b], entry[2])
		var shelter := middle + side * (TownLayout.ROAD_HALF + TownLayout.SIDEWALK + 50.0)
		bus_stops.append({"stop": middle + side * LANE, "kerb": middle + side * (TownLayout.ROAD_HALF + TownLayout.SIDEWALK * 0.5),
			"shelter": shelter, "along": along, "side": side})
		_keep_clear.append(_box_along(shelter, along, 260.0, 110.0))
	for entry: Array in TownLayout.RAMPS:
		var at: Vector2 = entry[0]
		var throw: Vector2 = entry[1]
		var start := at - throw * TownLayout.RUNWAY_BEFORE
		var end := at + throw * TownLayout.RUNWAY_AFTER
		var runway := Rect2(start, Vector2.ZERO).expand(end).grow_individual(
			absf(throw.y) * TownLayout.RUNWAY_WIDTH / 2.0, absf(throw.x) * TownLayout.RUNWAY_WIDTH / 2.0,
			absf(throw.y) * TownLayout.RUNWAY_WIDTH / 2.0, absf(throw.x) * TownLayout.RUNWAY_WIDTH / 2.0)
		ramps.append({"at": at, "throw": throw, "runway": runway})
		_keep_clear.append(runway.grow(40.0))
		_keep_clear.append(Rect2(end - Vector2(260, 260), Vector2(520, 520)))  # the cones beyond it
	for entry: Array in TownLayout.GATES:
		var id: StringName = entry[0]
		var at: Vector2 = entry[1]
		var facing: Vector2 = entry[2]
		var kind := &"boat" if String(id).begins_with("boat") else &"car"
		var area := _box_along(at, facing, GATE_AREA.x, GATE_AREA.y) if kind == &"car" else Rect2()
		gates.append({"track_id": id, "at": at, "facing": facing, "kind": kind, "area": area})
		if kind == &"car":
			_keep_clear.append(area.grow(80.0))
	rocket_pad = Rect2(TownLayout.ROCKET_PAD - Vector2.ONE * ROCKET_PAD_RADIUS, Vector2.ONE * ROCKET_PAD_RADIUS * 2.0)
	_keep_clear.append(rocket_pad.grow(120.0))
	_keep_clear.append(SnowIsland.bridge_rect().grow(150.0))
	_keep_clear.append(CandyIsland.bridge_rect().grow(150.0))
	_keep_clear.append(JungleIsland.bridge_rect().grow(150.0))
	_keep_clear.append(ToyIsland.bridge_rect().grow(150.0))
	_keep_clear.append(BeachIsland.bridge_rect().grow(150.0))


## A rectangle round `centre`, `length` along `along` and `depth` across it.
static func _box_along(centre: Vector2, along: Vector2, length: float, depth: float) -> Rect2:
	var size := Vector2(absf(along.x) * length + absf(along.y) * depth, absf(along.y) * length + absf(along.x) * depth)
	return Rect2(centre - size / 2.0, size)


## The football pitch in the middle of its block: mown stripes, white lines, a goal at each
## end. The goals' frames are solid; the ball counts as in when its middle is in a mouth.
func _football_pitch(lawn: Rect2) -> Rect2:
	pitch = Rect2(lawn.get_center() - PITCH_SIZE / 2.0, PITCH_SIZE)
	var stripes := 10
	for i in stripes:
		if i % 2 == 0:
			var stripe := Rect2(pitch.position.x + i * pitch.size.x / stripes, pitch.position.y, pitch.size.x / stripes, pitch.size.y)
			_ground.add_child(_flat(_rect_points(stripe), Color(0.1, 0.3, 0.05, 0.12)))
	var white := Color(1, 1, 1, 0.9)
	_outline_rect(pitch, 0.0, white, 8.0)
	var halfway := Line2D.new()
	halfway.points = PackedVector2Array([Vector2(pitch.get_center().x, pitch.position.y), Vector2(pitch.get_center().x, pitch.end.y)])
	halfway.width = 8.0
	halfway.default_color = white
	_ground.add_child(halfway)
	var circle := Line2D.new()
	for k in 33:
		circle.add_point(pitch.get_center() + Vector2.from_angle(TAU * k / 32.0) * 110.0)
	circle.width = 8.0
	circle.default_color = white
	_ground.add_child(circle)
	_ground.add_child(_disc(pitch.get_center(), 10.0, white))
	for side in [-1.0, 1.0]:
		var line_x: float = pitch.position.x if side < 0.0 else pitch.end.x
		var box := Rect2(Vector2(line_x - (0.0 if side < 0.0 else 170.0), pitch.get_center().y - 210.0), Vector2(170, 420))
		_outline_rect(box, 0.0, white, 8.0)
		# The goal: a net behind the line, a white frame round it, posts at the mouth.
		var mouth := Rect2(Vector2(line_x - (GOAL_DEPTH if side < 0.0 else 0.0), pitch.get_center().y - GOAL_MOUTH / 2.0),
			Vector2(GOAL_DEPTH, GOAL_MOUTH))
		goals.append(mouth)
		_things.add_child(_flat(_rect_points(mouth), Color(1, 1, 1, 0.35)))
		for k in range(1, 9):
			var y := mouth.position.y + k * GOAL_MOUTH / 9.0
			var strand := Line2D.new()
			strand.points = PackedVector2Array([Vector2(mouth.position.x, y), Vector2(mouth.end.x, y)])
			strand.width = 2.0
			strand.default_color = Color(1, 1, 1, 0.7)
			_things.add_child(strand)
		var back_x := mouth.position.x if side < 0.0 else mouth.end.x
		var frame := Line2D.new()
		frame.points = PackedVector2Array([Vector2(line_x, mouth.position.y), Vector2(back_x, mouth.position.y),
			Vector2(back_x, mouth.end.y), Vector2(line_x, mouth.end.y)])
		frame.width = 10.0
		frame.default_color = Color.WHITE
		frame.joint_mode = Line2D.LINE_JOINT_ROUND
		_things.add_child(frame)
		for post_y in [mouth.position.y, mouth.end.y]:
			_things.add_child(_disc(Vector2(line_x, post_y), POST_RADIUS, Color.WHITE))
			_add_circle(Vector2(line_x, post_y), POST_RADIUS)
		_add_box(Rect2(Vector2(minf(line_x, back_x), mouth.position.y - 6.0), Vector2(GOAL_DEPTH, 12.0)))
		_add_box(Rect2(Vector2(minf(line_x, back_x), mouth.end.y - 6.0), Vector2(GOAL_DEPTH, 12.0)))
		_add_box(Rect2(Vector2(back_x - 6.0, mouth.position.y), Vector2(12.0, GOAL_MOUTH)))
	return pitch.grow(GOAL_DEPTH + 40.0)


## After the rest: the bus stops, the ramps with their run-ups, and the puddles.
## A driveway beside houses, on the lawn just above the pavement, where a parked car is clear of
## the buildings, the trees, the pads and every other driveway.
const PARKING_SPOTS := 6
const PARKED_SIZE := Vector2(70.0, 120.0)  # a car facing the street, with a little room


func _plan_parking() -> void:
	var taken: Array[Rect2] = []
	taken.append_array(footprints)
	taken.append_array(_keep_clear)
	for pad in [wash_pad, fire_pad, bus_pad, paint_pad, rocket_pad]:
		taken.append(pad)
	for door: Dictionary in doors:
		taken.append(door["pad"])
	var houses_left := houses.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 29
	while parking.size() < PARKING_SPOTS and not houses_left.is_empty():
		var house: Dictionary = houses_left.pop_at(rng.randi() % houses_left.size())
		var sprite: Sprite2D = house["sprite"]
		var width: float = sprite.texture.get_width()
		var y: float = house["door"].y - TownLayout.SIDEWALK * 0.5 - 10.0 - PARKED_SIZE.y * 0.5 - 6.0
		for x in [sprite.position.x + width + PARKED_SIZE.x * 0.5 + 6.0, sprite.position.x - PARKED_SIZE.x * 0.5 - 6.0]:
			var at := Vector2(x, y)
			var box := Rect2(at - PARKED_SIZE / 2.0, PARKED_SIZE)
			if surface_at(at) != &"grass" or taken.any(func(r: Rect2) -> bool: return r.intersects(box.grow(20.0))):
				continue
			if tree_spots.any(func(t: Vector2) -> bool: return box.grow(TREE_TRUNK + 30.0).has_point(t)):
				continue
			if parking.any(func(p: Dictionary) -> bool: return p["at"].distance_to(at) < 1200.0):
				continue
			parking.append({"at": at, "angle": PI / 2.0})
			taken.append(box)
			break


func _build_extras() -> void:
	for stop in bus_stops:
		_bus_shelter(stop)
	for ramp in ramps:
		_ramp(ramp)
	for gate in gates:
		if gate["kind"] == &"car":
			_gate_paving(gate["area"])
	_rocket_pad()
	_puddle_layer = Node2D.new()
	_puddle_layer.name = "Puddles"
	_puddle_layer.modulate.a = 0.0
	_ground.add_child(_puddle_layer)
	for i in PUDDLES:
		var road: Array = roads[_rng.randi() % roads.size()]
		var a: Vector2 = junctions[road[0]]
		var b: Vector2 = junctions[road[1]]
		var d := (b - a).normalized()
		var at := a.lerp(b, _rng.randf_range(0.28, 0.72)) + right_of(d) * _rng.randf_range(-1.1, 1.1) * LANE
		var radius := _rng.randf_range(60.0, 100.0)
		puddles.append(Vector3(at.x, at.y, radius))
		var points := PackedVector2Array()
		var stretch := _rng.randf_range(1.2, 1.6)
		for k in 24:
			var angle := TAU * k / 24.0
			var wobble := 1.0 + 0.1 * sin(angle * 3.0 + i)
			points.append(at + (Vector2(cos(angle) * stretch, sin(angle)) * radius * wobble).rotated(d.angle()))
		_puddle_layer.add_child(_flat(points, PUDDLE_COLOUR))
		var shine := _flat(points, Color(1, 1, 1, 0.18))
		shine.scale = Vector2.ONE * 0.5
		shine.position = at * 0.5 + Vector2(-12, -10)
		_puddle_layer.add_child(shine)


## A car gate's start area (§28): asphalt with a kerb, on the grass. The grid, the arch and the
## racers waiting on it are the gate's own (RaceGate).
func _gate_paving(area: Rect2) -> void:
	_ground.add_child(_flat(_rect_points(area.grow(8.0), 44.0), KERB_COLOUR))
	_ground.add_child(_textured(_rect_points(area, 40.0), ASPHALT))


## The rocket pad (§28): a round concrete pad with yellow and black hazard stripes round its
## edge and the cardboard rocket standing on it, nose to the sky. Driving onto it opens the
## Hangar (the screen's pads).
func _rocket_pad() -> void:
	var at := rocket_pad.get_center()
	_ground.add_child(_disc(at, ROCKET_PAD_RADIUS + 10.0, KERB_COLOUR))
	for k in 16:
		var a0 := TAU * k / 16.0
		var a1 := TAU * (k + 1) / 16.0
		var band := PackedVector2Array()
		for step in 5:
			band.append(at + Vector2.from_angle(lerpf(a0, a1, step / 4.0)) * ROCKET_PAD_RADIUS)
		for step in 5:
			band.append(at + Vector2.from_angle(lerpf(a1, a0, step / 4.0)) * (ROCKET_PAD_RADIUS - 34.0))
		_ground.add_child(_flat(band, Color(0.98, 0.8, 0.15) if k % 2 == 0 else Color(0.12, 0.12, 0.14)))
	_ground.add_child(_disc(at, ROCKET_PAD_RADIUS - 34.0, Color(0.62, 0.64, 0.68)))
	_ground.add_child(_disc(at, 70.0, Color(0.5, 0.52, 0.56)))
	rocket = _sprite(ROCKET, at, 230.0, -PI / 2.0)
	rocket.z_index = TREE_Z


## How wet the roads are, 0 (dry) to 1 (pouring): the puddles show, and are slippery while
## they are more than a shine.
func set_wet(amount: float) -> void:
	_puddle_layer.modulate.a = amount
	wet = amount > 0.35


## A bus stop: a shelter on the grass behind the pavement, with a roof and a bench, and a
## sign with a bus on it at the kerb.
func _bus_shelter(stop: Dictionary) -> void:
	var along: Vector2 = stop["along"]
	var side: Vector2 = stop["side"]
	var at: Vector2 = stop["shelter"]
	_things.add_child(_flat(_rect_points(_box_along(at + Vector2(8, 10), along, 240.0, 90.0), 14.0), Color(0, 0, 0, 0.18)))
	_things.add_child(_flat(_rect_points(_box_along(at, along, 240.0, 90.0), 14.0), Color(0.24, 0.55, 0.85)))
	_things.add_child(_flat(_rect_points(_box_along(at - side * 6.0, along, 210.0, 56.0), 10.0), Color(0.55, 0.78, 0.95)))
	var bench := _box_along(at + side * 0.0 - side * 40.0, along, 160.0, 16.0)
	_things.add_child(_flat(_rect_points(bench, 6.0), Color(0.6, 0.4, 0.25)))
	var sign_at: Vector2 = stop["kerb"] + along * 150.0 - side * 20.0
	var pole := Line2D.new()
	pole.points = PackedVector2Array([sign_at, sign_at + Vector2(0, -60)])
	pole.width = 6.0
	pole.default_color = Color(0.4, 0.4, 0.42)
	_things.add_child(pole)
	_things.add_child(_disc(sign_at + Vector2(0, -70), 30.0, Color(0.98, 0.76, 0.18)))
	_things.add_child(_disc(sign_at + Vector2(0, -70), 24.0, Color.WHITE))
	var icon := Sprite2D.new()
	icon.texture = BUS
	icon.position = sign_at + Vector2(0, -70)
	icon.scale = Vector2.ONE * 40.0 / BUS.get_width()
	_things.add_child(icon)


## A jump ramp on the grass: a paved run-up with arrows, the ramp, and paving on beyond it
## to land on. Driving over the ramp the way it points throws a car into the air (CarHop).
func _ramp(ramp: Dictionary) -> void:
	var runway: Rect2 = ramp["runway"]
	var throw: Vector2 = ramp["throw"]
	var at: Vector2 = ramp["at"]
	_ground.add_child(_flat(_rect_points(runway.grow(7.0), 30.0), KERB_COLOUR))
	_ground.add_child(_textured(_rect_points(runway, 26.0), ASPHALT))
	for k in 4:
		var tip := at - throw * (620.0 - k * 130.0)
		var arrow := Line2D.new()
		var across := right_of(throw) * 40.0
		arrow.points = PackedVector2Array([tip - throw * 34.0 - across, tip, tip - throw * 34.0 + across])
		arrow.width = 12.0
		arrow.default_color = Color(1, 1, 1, 0.8)
		arrow.joint_mode = Line2D.LINE_JOINT_ROUND
		arrow.begin_cap_mode = Line2D.LINE_CAP_ROUND
		arrow.end_cap_mode = Line2D.LINE_CAP_ROUND
		_ground.add_child(arrow)
	var area := Area2D.new()
	area.name = "LandRamp"
	area.position = at
	area.rotation = throw.angle()
	area.monitorable = false
	area.collision_layer = 0
	area.collision_mask = Car.LAYER_CARS_GROUND
	var trigger := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = RAMP_TRIGGER
	trigger.shape = box
	area.add_child(trigger)
	var picture := Sprite2D.new()
	picture.texture = RAMP
	area.add_child(picture)
	area.body_entered.connect(func(body: Node2D) -> void:
		if body is Car and not body is Boat and not body is Kid and body.velocity.dot(throw) > 150.0:
			CarHop.launch(body))
	_things.add_child(area)

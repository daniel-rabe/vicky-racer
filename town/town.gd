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
## It is also the traffic's map. Junctions are grid cells (Vector2i); lane_points() and
## turn_points() give the line a car follows along a road and through a junction, on the
## right-hand side, and a car asks to reserve a junction before it drives into it, so two
## cars never cross it at once.

signal place_reached(place_id: String, display_name: String, picture: Texture2D)
## The player's car drove onto a pad that does something to it at once (&"paint").
signal pad_reached(kind: StringName, car: Car)

const GRASS := preload("res://art/tiles/grass.png")
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
const BUS := preload("res://art/town/vehicles/bus.png")
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
## The football pitch, and its two goal mouths (the ball is in when its middle is inside one).
var pitch := Rect2()
var goals: Array[Rect2] = []
## Where a beach ball lies, by a parasol.
var beach_balls: Array[Vector2] = []
## The park's fountain: where it is, and its spray (it shoots higher when a car splashes by).
var fountain_at := Vector2.ZERO
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
	_build_extras()


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
	return Island.map_rect()


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
	if Island.QUAY.has_point(pos) or _drive_rect().has_point(pos):
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


## The car wash's pad: a wet blue strip with soap bubbles and arrows pointing in, from the
## building's front across the pavement and a little way into the road. Driving the player's
## car onto it washes the car (CAR_washed): foam, then it sparkles. Steering in is needed —
## a car keeping to its lane passes by.
func _wash_pad(solid: Rect2, rect: Rect2) -> void:
	var pad := _front_pad(solid, rect, WASH_COLOUR, false)
	var width := pad.size.x
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
	for side in [-1.0, 1.0]:
		var arrow := Line2D.new()
		var x: float = pad.get_center().x + side * width * 0.22
		var tip := pad.position.y + pad.size.y * 0.35
		arrow.points = PackedVector2Array([Vector2(x - 26.0, tip + 30.0), Vector2(x, tip), Vector2(x + 26.0, tip + 30.0)])
		arrow.width = 12.0
		arrow.default_color = Color(1, 1, 1, 0.9)
		arrow.joint_mode = Line2D.LINE_JOINT_ROUND
		arrow.begin_cap_mode = Line2D.LINE_CAP_ROUND
		arrow.end_cap_mode = Line2D.LINE_CAP_ROUND
		_ground.add_child(arrow)
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


## Palms where the grass meets the sand, parasols and beach balls along the beach, a few
## trees on the grass round the town, and the waterline as a wall: cars stop at the wet
## sand, boats in the shallows.
func _build_coast() -> void:
	var palms := Island.outline(-Island.BEACH - 60.0)
	for i in range(0, palms.size(), 9):
		if not _near_harbour(palms[i], 300.0):
			var palm := _sprite(PALM, palms[i], 220.0 * _rng.randf_range(0.85, 1.1), _rng.randf() * TAU)
			palm.z_index = TREE_Z
			_add_circle(palms[i], TREE_TRUNK)
	var sand := Island.outline(-Island.BEACH * 0.45)
	for i in range(5, sand.size(), 37):
		if not _near_harbour(sand[i], 500.0):
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
	_wall_line(_wall(Car.LAYER_SEA_EDGE | Car.LAYER_LAND_EDGE, "Shore"), Island.shoreline())


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
		_things.add_child(_buoy(limit[i], 30.0, Color(0.9, 0.27, 0.24)))
	for i in range(7, limit.size(), 60):
		for k in 3:
			_sprite(ROCK, limit[i] + Vector2(_rng.randf_range(-120, 120), _rng.randf_range(-120, 120)), 150.0, _rng.randf() * TAU)
	_wall_line(_wall(Car.LAYER_WORLD, "OuterLimit"), limit)


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
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = rect.size
	shape.shape = box
	shape.position = rect.get_center()
	_solid.add_child(shape)


func _add_circle(centre: Vector2, radius: float) -> void:
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
func _build_extras() -> void:
	for stop in bus_stops:
		_bus_shelter(stop)
	for ramp in ramps:
		_ramp(ramp)
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
		if body is Car and not body is Boat and body.velocity.dot(throw) > 150.0:
			CarHop.launch(body))
	_things.add_child(area)

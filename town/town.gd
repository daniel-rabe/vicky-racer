class_name Town
extends Node2D
## Free Drive's town (docs/DESIGN.md §19), built in _ready from TownLayout: grass, pavements
## and two-lane streets on a grid, the buildings along the blocks with solid walls, a park
## with a fountain and a pond, trees, and an edge to the world.
##
## Like a race track it owns surfaces: every physics frame it tells each car in the "cars"
## group what it drives on — the road and the pavements are asphalt, a block's lawn is
## grass, the pond is water.
##
## It is also the traffic's map. Junctions are grid cells (Vector2i); lane_points() and
## turn_points() give the line a car follows along a road and through a junction, on the
## right-hand side, and a car asks to reserve a junction before it drives into it, so two
## cars never cross it at once.

signal place_reached(place_id: String, display_name: String, picture: Texture2D)

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

var junctions := {}  # Vector2i -> Vector2, world position
var links := {}      # Vector2i -> Array[Vector2i], junctions joined by a road
var roads: Array[Array] = []  # [Vector2i, Vector2i]
var lawns: Array[Rect2] = []  # each block's grass
var ponds: Array[Vector3] = []  # x, y, radius
## Building footprints, so trees and walkers keep clear of them.
var footprints: Array[Rect2] = []
## Every named place: {id, name, door (Vector2), picture}.
var places: Array[Dictionary] = []

var _reserved := {}    # Vector2i -> the car crossing that junction
var _surface_of := {}  # car -> surface id
var _solid: StaticBody2D
var _rng := RandomNumberGenerator.new()

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
	_build_graph()
	_build_ground()
	_build_blocks()
	_build_edge()


func _physics_process(_delta: float) -> void:
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		var surface := surface_at(car.global_position)
		if _surface_of.get(car) != surface:
			_surface_of[car] = surface
			car.surface_speed_mult = Track.SURFACES[surface]["speed_mult"]
			car.surface_grip_mult = Track.SURFACES[surface]["grip_mult"]
			EventSystem.CAR_surface_changed.emit(car, surface)


func world_rect() -> Rect2:
	return Rect2(Vector2.ZERO, TownLayout.world_size())


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
	if not streets_rect().has_point(pos):
		return &"grass"
	for lawn in lawns:
		if lawn.grow(-8.0).has_point(pos):
			return &"grass"
	return &"asphalt"


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
	var world := world_rect()
	_ground.add_child(_textured(_rect_points(world), GRASS))
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


func _building(id: String, picture: Texture2D, rect: Rect2, on_street: bool) -> void:
	var sprite := Sprite2D.new()
	sprite.name = id.capitalize().replace(" ", "")
	sprite.texture = picture
	sprite.centered = false
	sprite.position = rect.position
	_things.add_child(sprite)
	var used := Rect2(picture.get_image().get_used_rect()) if picture.get_image() else Rect2(Vector2.ZERO, rect.size)
	var solid := Rect2(rect.position + used.position, used.size).grow(-WALL_INSET)
	_add_box(solid)
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


## The big park: a fountain in the middle, the pond and the playground either side, flower
## beds and benches round the fountain. Trees fill in later.
func _park(lawn: Rect2) -> Array[Rect2]:
	var centre := lawn.get_center()
	var out: Array[Rect2] = []
	var fountain := _prop(FOUNTAIN, centre, Vector2(280, 280), 120.0)
	out.append(fountain)
	_things.add_child(_spray(centre))
	out.append(_pond(centre + Vector2(lawn.size.x * 0.3, 0), 280.0))
	out.append(_prop(PLAYGROUND, centre - Vector2(lawn.size.x * 0.3, 0), Vector2(320, 240)))
	for angle in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var spot := centre + Vector2.from_angle(angle) * 260.0
		out.append(_prop(FLOWER_BED, spot, Vector2(110, 110), 0.0))
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
		var bed := _prop(FLOWER_BED, spot, Vector2(96, 96) * _rng.randf_range(0.85, 1.15), 0.0)
		taken.append(bed)
		placed += 1


func _tree(at: Vector2, size: float) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = TREE
	sprite.position = at
	sprite.scale = Vector2(size, size)
	sprite.rotation = _rng.randf() * TAU
	sprite.z_index = TREE_Z
	_things.add_child(sprite)
	_add_circle(at, TREE_TRUNK * size)


## The edge of the world: a wall round the map, hidden in a ring of trees.
func _build_edge() -> void:
	var world := world_rect()
	var t := 200.0
	for rect: Rect2 in [Rect2(-t, -t, world.size.x + 2 * t, t + 40), Rect2(-t, world.size.y - 40, world.size.x + 2 * t, t + 40),
			Rect2(-t, 0, t + 40, world.size.y), Rect2(world.size.x - 40, 0, t + 40, world.size.y)]:
		_add_box(rect)
	var streets := streets_rect()
	var step := 170.0
	var x := 80.0
	while x < world.size.x:
		for y in [80.0, world.size.y - 80.0]:
			_tree(Vector2(x, y), 1.0)
		x += step
	var y := 80.0 + step
	while y < world.size.y - step:
		for edge_x in [80.0, world.size.x - 80.0]:
			_tree(Vector2(edge_x, y), 1.0)
		y += step
	# A few more scattered on the grass between the ring road and the edge.
	var grass: Array[Rect2] = [Rect2(world.position, Vector2(world.size.x, streets.position.y)),
		Rect2(Vector2(0, streets.end.y), Vector2(world.size.x, world.size.y - streets.end.y)),
		Rect2(Vector2(0, streets.position.y), Vector2(streets.position.x, streets.size.y)),
		Rect2(Vector2(streets.end.x, streets.position.y), Vector2(world.size.x - streets.end.x, streets.size.y))]
	for band in grass:
		var inner := band.grow(-260.0)
		if inner.size.x <= 0.0 or inner.size.y <= 0.0:
			continue
		for i in int(band.get_area() / 900000.0):
			_tree(Vector2(_rng.randf_range(inner.position.x, inner.end.x), _rng.randf_range(inner.position.y, inner.end.y)),
				_rng.randf_range(0.8, 1.1))


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

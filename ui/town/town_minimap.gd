class_name TownMinimap
extends Control
## Free Drive's map: the island squeezed into a corner — its sand and grass, the streets,
## lawns and ponds, the harbour — a grey dot per vehicle and the player as a big red one.
## On land it shows the town; while sailing it zooms out to the whole sea (§21), with the
## islets, the lighthouse and the wreck. The shapes are converted to map space when the
## view changes; each frame only the dots move.

const STREET := Color(0.93, 0.92, 0.88)
const LAWN := Color(0.48, 0.7, 0.3)
const POND := Color(0.42, 0.72, 0.9)
const SEA := Color(0.16, 0.55, 0.8)
const SAND := Color(0.93, 0.84, 0.57)
const HARBOUR := Color(1, 0.824, 0.247)
const TRAFFIC := Color(0.3, 0.33, 0.38)
const PLAYER := Color(0.902, 0.224, 0.275)
const PADDING := 14.0

var _town: Town
var _player: Car
var _sailing := false
var _traffic: Array[Car] = []
## Things to point out (§23): [world position, colour] — where a delivery goes, fires.
var marks: Array = []
var _scale := 1.0
var _origin := Vector2.ZERO
var _sand := PackedVector2Array()
var _grass := PackedVector2Array()
var _islets: Array[PackedVector2Array] = []
## The districts over the bridges: the snowy hill (§33) and candy land (§34), and which one
## the map is showing (&"" in town; the player is out over there).
var _snow := PackedVector2Array()
var _candy := PackedVector2Array()
var _jungle := PackedVector2Array()
var _district := &""
const SNOW := Color(0.95, 0.97, 1.0)
const ICE := Color(0.7, 0.85, 0.97)
const CANDY := Color(0.98, 0.76, 0.86)
const CHOCOLATE := Color(0.45, 0.27, 0.17)
const JUNGLE := Color(0.27, 0.55, 0.24)
const MUD := Color(0.42, 0.3, 0.18)
const STONE := Color(0.7, 0.66, 0.56)


func _ready() -> void:
	clip_contents = true  # on land the coast runs off the map's edges


func setup(town: Town, player: Car, traffic: Array[Car]) -> void:
	_town = town
	_player = player
	_traffic = traffic
	_fit()


func set_player(player: Car, sailing: bool) -> void:
	_player = player
	_sailing = sailing
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _town:
		_fit()


func _fit() -> void:
	_district = _out_in_district()
	var area := Island.map_rect().grow(-600.0) if _sailing else _town.streets_rect().grow(400.0)
	if _district == &"snow" and not _sailing:
		area = Rect2(SnowIsland.CENTRE - SnowIsland.RADII, SnowIsland.RADII * 2.0).grow(300.0)
	elif _district == &"candy" and not _sailing:
		area = Rect2(CandyIsland.CENTRE - CandyIsland.RADII, CandyIsland.RADII * 2.0).grow(300.0)
	elif _district == &"jungle" and not _sailing:
		area = Rect2(JungleIsland.CENTRE - JungleIsland.RADII, JungleIsland.RADII * 2.0).grow(300.0)
	var room := size - Vector2(PADDING, PADDING) * 2.0
	_scale = minf(room.x / area.size.x, room.y / area.size.y)
	_origin = Vector2(PADDING, PADDING) + (room - area.size * _scale) / 2.0 - area.position * _scale
	_sand = _mapped(Island.outline(0.0))
	_grass = _mapped(Island.outline(-Island.BEACH))
	_islets.clear()
	for islet in _town.islets:
		_islets.append(_mapped(islet))
	_snow = _mapped(SnowIsland.outline(0.0))
	_candy = _mapped(CandyIsland.outline(0.0))
	_jungle = _mapped(JungleIsland.outline(0.0))


## Which district the player is out over the water in or near: &"snow", &"candy", &"jungle"
## or &"".
func _out_in_district() -> StringName:
	if not is_instance_valid(_player):
		return &""
	if _player.global_position.y < JungleIsland.shore_y() + 1200.0:
		return &"jungle"
	if _player.global_position.x < SnowIsland.shore_x() - 1200.0:
		return &""
	return &"candy" if CandyIsland.this_side(_player.global_position) else &"snow"


func _process(_delta: float) -> void:
	if _town and _out_in_district() != _district:
		_fit()
	queue_redraw()


func _map(world: Vector2) -> Vector2:
	return _origin + world * _scale


func _mapped(points: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in points:
		out.append(_map(p))
	return out


func _draw() -> void:
	if _town == null:
		return
	draw_rect(Rect2(Vector2.ZERO, size), SEA)
	draw_colored_polygon(_sand, SAND)
	draw_colored_polygon(_grass, LAWN)
	for islet in _islets:
		draw_colored_polygon(islet, SAND)
	draw_colored_polygon(_snow, SNOW)
	var hill := _map(SnowIsland.HILL)
	draw_circle(hill, SnowIsland.HILL_RADIUS * _scale, Color(0.86, 0.9, 0.98))
	draw_circle(hill, SnowIsland.HILL_RADIUS * _scale * 0.4, Color.WHITE)
	draw_line(_map(SnowIsland.SLED_FROM), _map(SnowIsland.SLED_TO), ICE, SnowIsland.SLED_HALF * 2.0 * _scale)
	var lake := SnowIsland.LAKE_RADII * _scale
	draw_set_transform(_map(SnowIsland.LAKE), 0.0, Vector2(1.0, lake.y / lake.x))
	draw_circle(Vector2.ZERO, lake.x, ICE)
	draw_set_transform(Vector2.ZERO)
	draw_colored_polygon(_candy, CANDY)
	var lane := CandyIsland.lane_line()
	var lane_on_map := PackedVector2Array()
	for p in lane:
		lane_on_map.append(_map(p))
	lane_on_map.append(lane_on_map[0])
	draw_polyline(lane_on_map, STREET, CandyIsland.LANE_HALF * 2.0 * _scale)
	var choc := CandyIsland.LAKE_RADII * _scale
	draw_set_transform(_map(CandyIsland.LAKE), 0.0, Vector2(1.0, choc.y / choc.x))
	draw_circle(Vector2.ZERO, choc.x, CHOCOLATE)
	draw_set_transform(Vector2.ZERO)
	draw_colored_polygon(_jungle, JUNGLE)
	var trail := PackedVector2Array()
	for p in JungleIsland.trail_line():
		trail.append(_map(p))
	trail.append(trail[0])
	draw_polyline(trail, STREET, JungleIsland.TRAIL_HALF * 2.0 * _scale)
	for a in JungleIsland.MUD_ANGLES:
		draw_circle(_map(JungleIsland.trail_at(a)), JungleIsland.MUD_RADII.x * _scale, MUD)
	var court := JungleIsland.courtyard().merge(JungleIsland.pyramid())
	draw_rect(Rect2(_map(court.position), court.size * _scale), STONE)
	for bridge in [SnowIsland.bridge_rect(), CandyIsland.bridge_rect(), JungleIsland.bridge_rect()]:
		draw_rect(Rect2(_map(bridge.position), bridge.size * _scale), STREET)
	var streets := _town.streets_rect()
	draw_rect(Rect2(_map(streets.position), streets.size * _scale), STREET)
	for lawn in _town.lawns:
		draw_rect(Rect2(_map(lawn.position), lawn.size * _scale), LAWN)
	for pond in _town.ponds:
		draw_circle(_map(Vector2(pond.x, pond.y)), pond.z * _scale, POND)
	draw_rect(Rect2(_map(Island.QUAY.position), Island.QUAY.size * _scale), STREET)
	# The harbour, where the car and the boat swap: a yellow ring.
	var harbour := _map(Island.MOORING.get_center())
	draw_arc(harbour, 9.0, 0.0, TAU, 20, HARBOUR, 4.0)
	draw_circle(_map(Island.LIGHTHOUSE), 5.0, Color.WHITE)
	for car in _traffic:
		if is_instance_valid(car):
			draw_circle(_map(car.global_position), 4.0, TRAFFIC)
	for mark: Array in marks:
		var spot := _map(mark[0]).clamp(Vector2(6, 6), size - Vector2(6, 6))
		draw_circle(spot, 9.0, Color.WHITE)
		draw_circle(spot, 6.5, mark[1])
	if is_instance_valid(_player):
		var at := _map(_player.global_position).clamp(Vector2.ZERO, size)
		draw_circle(at, 10.0, Color.WHITE)
		draw_circle(at, 7.0, PLAYER)

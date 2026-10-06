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
var _scale := 1.0
var _origin := Vector2.ZERO
var _sand := PackedVector2Array()
var _grass := PackedVector2Array()
var _islets: Array[PackedVector2Array] = []


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
	var area := Island.map_rect().grow(-600.0) if _sailing else _town.streets_rect().grow(400.0)
	var room := size - Vector2(PADDING, PADDING) * 2.0
	_scale = minf(room.x / area.size.x, room.y / area.size.y)
	_origin = Vector2(PADDING, PADDING) + (room - area.size * _scale) / 2.0 - area.position * _scale
	_sand = _mapped(Island.outline(0.0))
	_grass = _mapped(Island.outline(-Island.BEACH))
	_islets.clear()
	for islet in _town.islets:
		_islets.append(_mapped(islet))


func _process(_delta: float) -> void:
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
	if is_instance_valid(_player):
		var at := _map(_player.global_position).clamp(Vector2.ZERO, size)
		draw_circle(at, 10.0, Color.WHITE)
		draw_circle(at, 7.0, PLAYER)

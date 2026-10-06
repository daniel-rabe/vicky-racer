class_name TownMinimap
extends Control
## Free Drive's map: the streets, lawns and ponds squeezed into a corner, a grey dot per
## vehicle and the player's car as a big red one. The streets are converted to map space
## once; each frame only the dots move.

const STREET := Color(0.93, 0.92, 0.88)
const LAWN := Color(0.48, 0.7, 0.3)
const POND := Color(0.42, 0.72, 0.9)
const TRAFFIC := Color(0.3, 0.33, 0.38)
const PLAYER := Color(0.902, 0.224, 0.275)
const PADDING := 14.0

var _town: Town
var _player: Car
var _traffic: Array[Car] = []
var _scale := 1.0
var _origin := Vector2.ZERO


func setup(town: Town, player: Car, traffic: Array[Car]) -> void:
	_town = town
	_player = player
	_traffic = traffic
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED and _town:
		_fit()


func _fit() -> void:
	var area := _town.streets_rect().grow(200.0)
	var room := size - Vector2(PADDING, PADDING) * 2.0
	_scale = minf(room.x / area.size.x, room.y / area.size.y)
	_origin = Vector2(PADDING, PADDING) + (room - area.size * _scale) / 2.0 - area.position * _scale


func _process(_delta: float) -> void:
	queue_redraw()


func _map(world: Vector2) -> Vector2:
	return _origin + world * _scale


func _draw() -> void:
	if _town == null:
		return
	var streets := _town.streets_rect()
	draw_rect(Rect2(_map(streets.position), streets.size * _scale), STREET)
	for lawn in _town.lawns:
		draw_rect(Rect2(_map(lawn.position), lawn.size * _scale), LAWN)
	for pond in _town.ponds:
		draw_circle(_map(Vector2(pond.x, pond.y)), pond.z * _scale, POND)
	for car in _traffic:
		if is_instance_valid(car):
			draw_circle(_map(car.global_position), 4.0, TRAFFIC)
	if is_instance_valid(_player):
		var at := _map(_player.global_position)
		draw_circle(at, 10.0, Color.WHITE)
		draw_circle(at, 7.0, PLAYER)

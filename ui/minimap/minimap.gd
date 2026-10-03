class_name Minimap
extends Control
## The track's racing line squeezed into a corner, with a dot per car (docs/DESIGN.md §10).
## Drawn with _draw rather than a second viewport: cheaper, and crisper at this size.
##
## Only the dots move, so the line is converted to map space once (again on resize) and
## each frame's _draw just strokes it and places four dots. Converting all 200 points every
## frame was the most expensive script in the race (perf_probe: 71 of ~270 us a frame).

const PADDING := 24.0
const LINE_WIDTH := 8.0
const DOT_RADIUS := 10.0
const PLAYER_DOT_RADIUS := 13.0
const LINE_POINTS := 200

var _line: PackedVector2Array = []   # racing line, world coordinates
var _map_line: PackedVector2Array = []  # the same, in this control's coordinates, closed
## Opponents first and the player last, so the player's dot is drawn on top.
var _draw_order: Array[Dictionary] = []
var _bounds := Rect2()
var _origin := Vector2.ZERO
var _scale := 1.0


func setup(track: Track, racers: Array[Dictionary]) -> void:
	_draw_order.assign(racers.filter(func(r: Dictionary) -> bool: return not r["is_player"]) \
		+ racers.filter(func(r: Dictionary) -> bool: return r["is_player"]))
	var curve := track.racing_line.curve
	var length := curve.get_baked_length()
	_line.clear()
	for i in LINE_POINTS:
		_line.append(track.racing_line.to_global(curve.sample_baked(length * i / LINE_POINTS)))
	_bounds = Rect2(_line[0], Vector2.ZERO)
	for p in _line:
		_bounds = _bounds.expand(p)
	_fit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_fit()


func _process(_delta: float) -> void:
	queue_redraw()


## Recompute the world-to-map transform and the map-space line for the current size.
func _fit() -> void:
	if _line.is_empty():
		return
	var inner := size - Vector2(PADDING, PADDING) * 2.0
	_scale = minf(inner.x / _bounds.size.x, inner.y / _bounds.size.y)
	_origin = (size - _bounds.size * _scale) / 2.0
	_map_line.resize(_line.size() + 1)
	for i in _line.size():
		_map_line[i] = _to_map(_line[i])
	_map_line[_line.size()] = _map_line[0]


func _to_map(world: Vector2) -> Vector2:
	return _origin + (world - _bounds.position) * _scale


func _draw() -> void:
	if _map_line.is_empty():
		return
	draw_polyline(_map_line, Color.WHITE, LINE_WIDTH, true)
	for r in _draw_order:
		var at := _to_map(r["car"].global_position)
		if r["is_player"]:
			draw_circle(at, PLAYER_DOT_RADIUS + 3.0, Color.WHITE)
			draw_circle(at, PLAYER_DOT_RADIUS, r["colour"])
		else:
			draw_circle(at, DOT_RADIUS, r["colour"])

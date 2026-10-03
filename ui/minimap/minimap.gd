class_name Minimap
extends Control
## The track's racing line squeezed into a corner, with a dot per car (docs/DESIGN.md §10).
## Drawn with _draw rather than a second viewport: cheaper, and crisper at this size.

const PADDING := 24.0
const LINE_WIDTH := 8.0
const DOT_RADIUS := 10.0
const PLAYER_DOT_RADIUS := 13.0

var _line: PackedVector2Array = []   # racing line, world coordinates
var _racers: Array[Dictionary] = []
var _bounds := Rect2()


func setup(track: Track, racers: Array[Dictionary]) -> void:
	_racers = racers
	var curve := track.racing_line.curve
	var length := curve.get_baked_length()
	_line.clear()
	for i in 200:
		_line.append(track.racing_line.to_global(curve.sample_baked(length * i / 200.0)))
	_bounds = Rect2(_line[0], Vector2.ZERO)
	for p in _line:
		_bounds = _bounds.expand(p)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _line.is_empty():
		return
	var inner := size - Vector2(PADDING, PADDING) * 2.0
	var scale_to_fit := minf(inner.x / _bounds.size.x, inner.y / _bounds.size.y)
	var origin := (size - _bounds.size * scale_to_fit) / 2.0
	var to_map := func(world: Vector2) -> Vector2:
		return origin + (world - _bounds.position) * scale_to_fit
	var points := PackedVector2Array()
	for p in _line:
		points.append(to_map.call(p))
	points.append(points[0])
	draw_polyline(points, Color.WHITE, LINE_WIDTH, true)
	# The player last, so their dot is on top.
	for r in _racers.filter(func(x: Dictionary) -> bool: return not x["is_player"]) \
			+ _racers.filter(func(x: Dictionary) -> bool: return x["is_player"]):
		var at: Vector2 = to_map.call(r["car"].global_position)
		if r["is_player"]:
			draw_circle(at, PLAYER_DOT_RADIUS + 3.0, Color.WHITE)
			draw_circle(at, PLAYER_DOT_RADIUS, r["colour"])
		else:
			draw_circle(at, DOT_RADIUS, r["colour"])

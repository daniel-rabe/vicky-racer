class_name DriverRider
extends Node2D
## The driver drawn in a vehicle (docs/DESIGN.md §22). It is a child of the body sprite, so it
## turns with the car and bobs, tilts and jumps with a boat's hull. It sits where DriverSeats
## says: on top (an open seat), rising out of a sunroof cut in a closed roof, or behind glass.
## It leans a little into the turns.
##
## Built by `build`; rebuilt whenever the body or the driver changes (Car._update_rider).
## Only the driver picture is new art: the glass is drawn here.

## How far the driver leans at full steer: px sideways, and radians.
const LEAN_PX := 1.5
const LEAN_RADIANS := 0.15
const LEAN_RATE := 8.0
const GLASS_COLOUR := Color(0.157, 0.235, 0.353, 0.78)
const GLASS_TINT := Color(0.157, 0.235, 0.353, 0.27)
const SHEEN_COLOUR := Color(1, 1, 1, 0.3)

## The car whose steering it leans with; null (a ghost) leans not at all.
var car: Car
var mode := &""

var _driver: Sprite2D
var _seat_pos := Vector2.ZERO
var _lean := 0.0


## Seat a driver in `body` (its picture's seat, DriverSeats). Returns null, and seats
## nobody, if the picture has no seat or there is no driver picture.
static func build(body: Sprite2D, driver: Texture2D, leaning_with: Car = null) -> DriverRider:
	var seat := DriverSeats.seat_for(body.texture)
	if seat.is_empty() or driver == null:
		return null
	var rider := DriverRider.new()
	rider.name = "Driver"
	rider.car = leaning_with
	rider._seat(seat, driver)
	body.add_child(rider)
	return rider


func _seat(seat: Dictionary, driver: Texture2D) -> void:
	mode = seat["mode"]
	_seat_pos = seat["pos"]
	_driver = Sprite2D.new()
	_driver.name = "Figure"
	_driver.texture = driver
	_driver.scale = Vector2.ONE * seat.get("scale", 1.0) * 0.75
	_driver.position = _seat_pos
	match mode:
		DriverSeats.GLASS:
			var window: Rect2 = seat["window"]
			var glass := _rounded(window, minf(6.0, minf(window.size.x, window.size.y) / 2.0), GLASS_COLOUR)
			glass.name = "Glass"
			glass.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
			add_child(glass)
			glass.add_child(_driver)
			glass.add_child(_rounded(window, 0.0, GLASS_TINT))
			var sheen := Polygon2D.new()
			var p := window.position
			var s := window.size
			sheen.polygon = PackedVector2Array([p + Vector2(s.x * 0.15, s.y), p + Vector2(s.x * 0.55, 0),
				p + Vector2(s.x * 0.75, 0), p + Vector2(s.x * 0.35, s.y)])
			sheen.color = SHEEN_COLOUR
			glass.add_child(sheen)
		_:
			add_child(_driver)


func _process(delta: float) -> void:
	if car == null or _driver == null:
		return
	var target := 0.0 if car.frozen else car.steer_input
	_lean = lerpf(_lean, target, 1.0 - exp(-LEAN_RATE * delta))
	_driver.position = _seat_pos + Vector2(0, _lean * LEAN_PX)
	_driver.rotation = _lean * LEAN_RADIANS


static func _rounded(rect: Rect2, radius: float, colour: Color) -> Polygon2D:
	var points := PackedVector2Array()
	if radius <= 0.0:
		points = PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
			Vector2(rect.position.x, rect.end.y)])
	else:
		var corners := [Vector2(rect.end.x - radius, rect.position.y + radius), Vector2(rect.end.x - radius, rect.end.y - radius),
			Vector2(rect.position.x + radius, rect.end.y - radius), Vector2(rect.position.x + radius, rect.position.y + radius)]
		for c in 4:
			for i in 7:
				var a := -PI / 2.0 + (c + i / 6.0) * PI / 2.0
				points.append(corners[c] + Vector2(cos(a), sin(a)) * radius)
	var poly := Polygon2D.new()
	poly.polygon = points
	poly.color = colour
	return poly

class_name CarLights
extends Node2D
## A vehicle's lights at night (docs/DESIGN.md §27), on its Body so they turn and bob with
## it: two warm headlight beams spreading out ahead over the road, and two red tail lights
## that glow brighter while the car brakes. The lamps themselves are little lenses on the
## body's front and back corners. Night adds these with fit() and takes them off with remove().

const HEAD_COLOUR := Color(1.0, 0.93, 0.72)
const TAIL_COLOUR := Color(1.0, 0.16, 0.12)
const HEAD_ENERGY := 1.5
const TAIL_ENERGY := 0.9
## A soft light round the car itself, so a child can always find theirs in the dark.
const GLOW_COLOUR := Color(0.85, 0.88, 1.0)
const GLOW_ENERGY := 0.55
const BRAKE_ENERGY := 2.2
## How far the beams reach ahead and how wide they spread, px.
const BEAM_LENGTH := 420.0
const BEAM_SPREAD := 0.36
## The lamps sit this far in from the body's corners, as a share of its size.
const LAMP_INSET := Vector2(0.06, 0.3)

static var _beams := {}  # lamp spacing (px) -> beam texture
static var _glows := {}  # lamp spacing (px) -> tail glow texture
static var _drawn := {}  # body picture -> the part of it with the vehicle on

var car: Car
var _tail: PointLight2D


## Lights on `car`, unless it has them already.
static func fit(car: Node) -> void:
	if not is_instance_valid(car) or not car is Car:
		return
	var body: Sprite2D = car.get_node_or_null(^"Body")
	if body and car is Kid and not body.has_node(^"Lights"):
		# Vicky on foot (§29): no lamps, just the soft light round him so he is easy to find.
		var glow := PointLight2D.new()
		glow.name = "Lights"
		glow.texture = _glow_texture(0)
		glow.texture_scale = 4.0
		glow.color = GLOW_COLOUR
		glow.energy = GLOW_ENERGY * 1.4
		body.add_child(glow)
		return
	if body == null or body.texture == null or body.has_node(^"Lights"):
		return
	var lights := CarLights.new()
	lights.name = "Lights"
	lights.car = car
	body.add_child(lights)


static func remove(car: Node) -> void:
	var lights := car.get_node_or_null(^"Body/Lights")
	if lights:
		lights.queue_free()


func _ready() -> void:
	# The picture may have empty space round the vehicle (the bus has): the lamps go on the
	# vehicle itself.
	var picture: Texture2D = (get_parent() as Sprite2D).texture
	if not _drawn.has(picture):
		var image := picture.get_image()
		_drawn[picture] = Rect2(image.get_used_rect()) if image else Rect2(Vector2.ZERO, picture.get_size())
	var drawn: Rect2 = _drawn[picture]
	position = drawn.get_center() - picture.get_size() * 0.5
	var size := drawn.size
	var front := size.x * (0.5 - LAMP_INSET.x)
	var side := roundf(size.y * (0.5 - LAMP_INSET.y))
	var head := PointLight2D.new()
	head.name = "Headlights"
	head.texture = _beam_texture(int(side))
	head.texture_scale = 2.0
	head.position = Vector2(front, 0.0)
	head.color = HEAD_COLOUR
	head.energy = HEAD_ENERGY
	add_child(head)
	_tail = PointLight2D.new()
	_tail.name = "TailLights"
	_tail.texture = _glow_texture(int(side))
	_tail.position = Vector2(-size.x * (0.5 - LAMP_INSET.x * 0.5), 0.0)
	_tail.color = TAIL_COLOUR
	_tail.energy = TAIL_ENERGY
	add_child(_tail)
	var glow := PointLight2D.new()
	glow.name = "Glow"
	glow.texture = _glow_texture(0)
	glow.texture_scale = size.x / 40.0
	glow.color = GLOW_COLOUR
	glow.energy = GLOW_ENERGY
	add_child(glow)
	for y in [-side, side]:
		_lens(Vector2(front + 2.0, y), Color(1.0, 0.97, 0.85), 5.0)
		_lens(Vector2(_tail.position.x, y), Color(1.0, 0.25, 0.2), 4.0)


func _process(_delta: float) -> void:
	var braking := car.throttle_input < -0.1 and car.forward_speed() > 20.0
	_tail.energy = move_toward(_tail.energy, BRAKE_ENERGY if braking else TAIL_ENERGY, 0.25)


## A lamp's glass: a small bright dot, lit by its own light.
func _lens(at: Vector2, colour: Color, radius: float) -> void:
	var dot := Polygon2D.new()
	var points := PackedVector2Array()
	for k in 12:
		points.append(at + Vector2.from_angle(TAU * k / 12.0) * radius)
	dot.polygon = points
	dot.color = colour
	add_child(dot)


## Two beams from lamps `side` px either side of the middle, spreading out ahead. The lamps
## sit at the texture's centre (the half behind them stays dark but for their glow); it is
## drawn at half size and scaled up.
static func _beam_texture(side: int) -> Texture2D:
	if _beams.has(side):
		return _beams[side]
	var w := int(BEAM_LENGTH / 2.0)
	var h := int((BEAM_LENGTH * tan(BEAM_SPREAD) + side) / 2.0) * 2 + 8
	var image := Image.create(w * 2, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w * 2:
			var p := Vector2(x - w, y - h * 0.5) * 2.0
			var light := 0.0
			if p.x > -6.0:
				for lamp in [-side, side]:
					var d := p - Vector2(0.0, lamp)
					var r := d.length() / BEAM_LENGTH
					var angle := absf(atan2(d.y, maxf(d.x, 0.001)))
					var beam := smoothstep(BEAM_SPREAD, BEAM_SPREAD * 0.45, angle) * pow(maxf(1.0 - r, 0.0), 1.4)
					var spot := exp(-pow(d.length() / 14.0, 2.0))
					light = maxf(light, maxf(beam * 0.85, spot))
			image.set_pixel(x, y, Color(1, 1, 1, clampf(light, 0.0, 1.0)))
	var texture := ImageTexture.create_from_image(image)
	_beams[side] = texture
	return texture


## A soft glow round each of two lamps `side` px apart (the tail lights), or round one
## (side 0: the glow round the whole car).
static func _glow_texture(side: int) -> Texture2D:
	if _glows.has(side):
		return _glows[side]
	var radius := 30.0
	var w := int(radius * 2.0)
	var h := int(side * 2.0 + radius * 2.0)
	var image := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var light := 0.0
			for lamp in ([-side, side] if side > 0 else [0]):
				var d := Vector2(x - w * 0.5, y - h * 0.5 - lamp).length() / radius
				light = maxf(light, pow(maxf(1.0 - d, 0.0), 1.6))
			image.set_pixel(x, y, Color(1, 1, 1, light))
	var texture := ImageTexture.create_from_image(image)
	_glows[side] = texture
	return texture

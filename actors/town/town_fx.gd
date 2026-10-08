class_name TownFx
extends RefCounted
## Little one-off bursts for Free Drive's things to do (docs/DESIGN.md §23), left in the
## world where they happen and freed when they are done: hearts for a thank-you, confetti
## for a goal, steam from a fire put out, drops from the fountain, a cloud of paint. All drawn
## in code, like the car's own puffs and stars, so they need no art.

const CarEffects := preload("res://actors/car/car_effects.gd")
const CONFETTI := [Color(0.9, 0.22, 0.27), Color(1, 0.82, 0.25), Color(0.23, 0.53, 1.0), Color(0.18, 0.77, 0.42),
	Color(0.62, 0.36, 0.95), Color(1, 0.45, 0.72)]

static var _heart: ImageTexture


## A few hearts floating up from `at`.
static func hearts(parent: Node, at: Vector2, count := 6) -> void:
	var burst := _burst(parent, at, _heart_texture(), count, 1.4)
	burst.direction = Vector2.UP
	burst.spread = 50.0
	burst.initial_velocity_min = 90.0
	burst.initial_velocity_max = 170.0
	burst.scale_amount_min = 0.7
	burst.scale_amount_max = 1.2
	burst.color = Color(1.0, 0.36, 0.52)
	_fade(burst)
	burst.emitting = true


## Confetti in every paint colour, thrown out all round `at`.
static func confetti(parent: Node, at: Vector2) -> void:
	for colour: Color in CONFETTI:
		var burst := _burst(parent, at, null, 14, 1.6)
		burst.spread = 180.0
		burst.initial_velocity_min = 200.0
		burst.initial_velocity_max = 520.0
		burst.damping_min = 260.0
		burst.damping_max = 340.0
		burst.angular_velocity_min = -400.0
		burst.angular_velocity_max = 400.0
		burst.scale_amount_min = 10.0
		burst.scale_amount_max = 16.0
		burst.color = colour
		_fade(burst)
		burst.emitting = true


## A puff of white steam rising from `at` (a fire put out).
static func steam(parent: Node, at: Vector2) -> void:
	var burst := _burst(parent, at, CarEffects._puff_texture(), 18, 1.6)
	burst.spread = 180.0
	burst.initial_velocity_min = 40.0
	burst.initial_velocity_max = 110.0
	burst.scale_amount_min = 1.0
	burst.scale_amount_max = 2.2
	burst.color = Color(0.95, 0.96, 1.0)
	_fade(burst)
	burst.emitting = true


## Water drops splashing out round `at` (the fountain, a puddle).
static func drops(parent: Node, at: Vector2, count := 24) -> void:
	var burst := _burst(parent, at, CarEffects._puff_texture(), count, 0.7)
	burst.spread = 180.0
	burst.initial_velocity_min = 120.0
	burst.initial_velocity_max = 300.0
	burst.damping_min = 200.0
	burst.damping_max = 300.0
	burst.scale_amount_min = 0.2
	burst.scale_amount_max = 0.45
	burst.color = Color(0.8, 0.93, 1.0)
	_fade(burst)
	burst.emitting = true


## A cloud of `colour` all round `at` (the paint shop).
static func paint_cloud(parent: Node, at: Vector2, colour: Color) -> void:
	var burst := _burst(parent, at, CarEffects._puff_texture(), 30, 1.1)
	burst.spread = 180.0
	burst.initial_velocity_min = 60.0
	burst.initial_velocity_max = 220.0
	burst.damping_min = 120.0
	burst.damping_max = 180.0
	burst.scale_amount_min = 1.0
	burst.scale_amount_max = 2.0
	burst.color = colour
	_fade(burst)
	burst.emitting = true


static func _burst(parent: Node, at: Vector2, texture: Texture2D, amount: int, lifetime: float) -> CPUParticles2D:
	var burst := CPUParticles2D.new()
	burst.texture = texture
	burst.amount = amount
	burst.lifetime = lifetime
	burst.one_shot = true
	burst.explosiveness = 0.9
	burst.gravity = Vector2.ZERO
	burst.z_index = 4
	burst.emitting = false
	parent.add_child(burst)
	burst.global_position = at
	burst.finished.connect(burst.queue_free)
	return burst


static func _fade(burst: CPUParticles2D) -> void:
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0.9), Color(1, 1, 1, 0)])
	burst.color_ramp = fade


## A round-topped heart, white (tinted by the burst), 32 px.
static func _heart_texture() -> ImageTexture:
	if _heart:
		return _heart
	var size := 32
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			# The classic heart curve, (x² + y² - 1)³ - x² y³ <= 0, scaled into the square.
			var u := (x - 15.5) / 13.0
			var v := (15.0 - y) / 13.0 + 0.25
			var f := pow(u * u + v * v - 1.0, 3.0) - u * u * v * v * v
			image.set_pixel(x, y, Color(1, 1, 1, 1) if f <= 0.0 else Color(1, 1, 1, 0))
	_heart = ImageTexture.create_from_image(image)
	return _heart

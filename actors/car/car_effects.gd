extends Node2D
## Puffs from the rear wheels of its parent car: dust when it drives on grass or sand
## (from CAR_surface_changed), white tyre smoke when it drifts on the road. Particles are
## left behind in the world rather than dragged along with the car, and draw beneath it.
##
## Out of Free Drive's car wash (CAR_washed) the car is covered in foam for a moment, then
## sparkles — little stars twinkling all over it — for SPARKLE_SECONDS, fading at the end.
##
## The puff and star textures are built here, so the effects need no art file and stay in
## the flat picture-book look of the rest of the game.

## Grass throws up earth rather than green, which would vanish against the grass itself.
const DUST_COLOURS := {
	&"grass": Color(0.7, 0.58, 0.36),
	&"sand": Color(0.87, 0.76, 0.5),
	&"beach": Color(0.9, 0.8, 0.55),
	&"snow": Color(0.97, 0.98, 1.0),
	&"ice": Color(0.8, 0.93, 1.0),
	&"jungle": Color(0.55, 0.42, 0.26),
	&"mud": Color(0.45, 0.3, 0.18),
	&"candy": Color(1.0, 0.85, 0.92),
	&"chocolate": Color(0.42, 0.26, 0.17),
	&"moondust": Color(0.88, 0.86, 0.94),
	&"crater": Color(0.74, 0.7, 0.84),
	&"water": Color(0.85, 0.95, 1.0),
}
const SMOKE_COLOUR := Color(0.93, 0.93, 0.91)
## Slower than this, px/s, and there is nothing to throw up.
const DUST_MIN_SPEED := 120.0
## Behind the rear axle in the car's own frame.
const EMIT_FROM := Vector2(-40.0, 0.0)
## How long a washed car sparkles, and over how much of the end it fades away, s.
const SPARKLE_SECONDS := 25.0
const SPARKLE_FADE := 6.0
const FOAM_COLOUR := Color(1.0, 1.0, 1.0)

var _surface := &"asphalt"
var _dust: GPUParticles2D
var _smoke: GPUParticles2D
var _siren: Node2D
var _siren_time := 0.0
var _foam: GPUParticles2D
var _sparkle: GPUParticles2D
## Seconds of sparkle left; 0 = not sparkling.
var sparkle_time := 0.0

@onready var car: Car = get_parent()


func _enter_tree() -> void:
	EventSystem.CAR_surface_changed.connect(_on_surface_changed)
	EventSystem.CAR_washed.connect(func(washed: Node) -> void:
		if washed == car:
			wash())


func _ready() -> void:
	show_behind_parent = true
	var puff := _puff_texture()
	_dust = _emitter(puff, 32, 0.8, Vector2(0.6, 1.5), 80.0)
	_smoke = _emitter(puff, 30, 0.9, Vector2(0.6, 1.4), 40.0)
	_smoke.modulate = SMOKE_COLOUR
	_siren = _siren_lights()
	_foam = _foam_burst(puff)
	_sparkle = _sparkles()


## Foam all over, then sparkles. Washing a car that is still sparkling starts it afresh.
func wash() -> void:
	_foam.restart()
	sparkle_time = SPARKLE_SECONDS
	_sparkle.emitting = true
	# Out of the foam, the paint gleams: a bright flash on the body that settles back.
	var body: CanvasItem = car.get_node(^"Body")
	var shine := create_tween()
	shine.tween_interval(0.9)
	shine.tween_property(body, "self_modulate", Color(1.6, 1.6, 1.6), 0.15)
	shine.tween_property(body, "self_modulate", Color.WHITE, 0.6).set_trans(Tween.TRANS_SINE)


func _on_surface_changed(changed: Node, surface: StringName) -> void:
	if changed == car:
		_surface = surface
		if DUST_COLOURS.has(surface):
			_dust.modulate = DUST_COLOURS[surface]


func _physics_process(delta: float) -> void:
	var speed := car.velocity.length()
	var fraction := clampf(speed / car.config.max_speed, 0.0, 1.0)
	_dust.emitting = not car.frozen and DUST_COLOURS.has(_surface) and speed > DUST_MIN_SPEED
	_dust.amount_ratio = 0.35 + 0.65 * fraction
	_smoke.emitting = not car.frozen and car.is_drifting and _surface == &"asphalt"
	if car.setup:
		_smoke.modulate = car.setup.smoke_colour
	# The Police Car's roof lights flash while it drifts.
	_siren.visible = car.setup != null and car.setup.siren and car.is_drifting
	if _siren.visible:
		_siren_time += delta
		var red_on := fmod(_siren_time, 0.3) < 0.15
		_siren.get_child(0).modulate.a = 1.0 if red_on else 0.25
		_siren.get_child(1).modulate.a = 0.25 if red_on else 1.0
	_smoke.amount_ratio = clampf(car.lateral_speed / (car.config.drift_threshold * 2.5), 0.3, 1.0)
	if sparkle_time > 0.0:
		sparkle_time = maxf(sparkle_time - delta, 0.0)
		_sparkle.amount_ratio = clampf(sparkle_time / SPARKLE_FADE, 0.15, 1.0)
		_sparkle.emitting = sparkle_time > 0.0


## A burst of foam bubbles round the whole car, left behind where it was washed.
func _foam_burst(puff: Texture2D) -> GPUParticles2D:
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(1.0, 0.0, 0.0)
	material.spread = 180.0
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 90.0
	material.gravity = Vector3.ZERO
	material.damping_min = 30.0
	material.damping_max = 50.0
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(60.0, 34.0, 0.0)
	material.scale_min = 0.35
	material.scale_max = 0.9
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.95))
	fade.add_point(0.7, Color(0.92, 0.97, 1.0, 0.85))
	fade.set_color(fade.get_point_count() - 1, Color(0.85, 0.95, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	material.color_ramp = ramp
	var foam := GPUParticles2D.new()
	foam.name = "Foam"
	foam.process_material = material
	foam.texture = puff
	foam.amount = 60
	foam.lifetime = 1.6
	foam.one_shot = true
	foam.explosiveness = 0.85
	foam.local_coords = false
	foam.z_index = 2  # this node draws behind the car; the foam covers it
	foam.modulate = FOAM_COLOUR
	foam.emitting = false
	add_child(foam)
	return foam


## Little four-pointed stars that pop up all over the car, grow, twinkle and shrink. They
## ride with the car (local coordinates) and draw on top of it.
func _sparkles() -> GPUParticles2D:
	var material := ParticleProcessMaterial.new()
	material.gravity = Vector3.ZERO
	material.initial_velocity_min = 0.0
	material.initial_velocity_max = 6.0
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(62.0, 36.0, 0.0)  # over the body and just past it
	material.angle_min = -20.0
	material.angle_max = 20.0
	material.angular_velocity_min = -90.0
	material.angular_velocity_max = 90.0
	material.scale_min = 0.8
	material.scale_max = 1.5
	var pulse := Curve.new()
	pulse.add_point(Vector2(0.0, 0.0))
	pulse.add_point(Vector2(0.35, 1.0))
	pulse.add_point(Vector2(1.0, 0.0))
	material.scale_curve = _curve_texture(pulse)
	var tint := Gradient.new()
	tint.set_color(0, Color(1.0, 1.0, 1.0, 1.0))
	tint.set_color(1, Color(1.0, 0.92, 0.55, 1.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = tint
	material.color_initial_ramp = ramp  # each star white to pale gold
	var sparkle := GPUParticles2D.new()
	sparkle.name = "Sparkle"
	sparkle.process_material = material
	sparkle.texture = _star_texture()
	sparkle.amount = 18
	sparkle.lifetime = 0.8
	sparkle.randomness = 0.5
	sparkle.local_coords = true
	sparkle.z_index = 2
	sparkle.emitting = false
	add_child(sparkle)
	return sparkle


## Two glowing discs on the roof, red and blue, flashed by _physics_process. This node draws
## behind the car, so the lights get a z_index of their own to sit on top of it.
func _siren_lights() -> Node2D:
	var lights := Node2D.new()
	lights.z_index = 1
	lights.visible = false
	add_child(lights)
	var glow := _puff_texture()
	for i in 2:
		var light := Sprite2D.new()
		light.texture = glow
		light.scale = Vector2(0.55, 0.55)
		light.position = Vector2(4.0, -14.0 if i == 0 else 14.0)
		light.self_modulate = Color(1.0, 0.2, 0.2) if i == 0 else Color(0.25, 0.45, 1.0)
		lights.add_child(light)
	return lights


func _emitter(texture: Texture2D, amount: int, lifetime: float, size: Vector2, spread_speed: float) -> GPUParticles2D:
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(-1.0, 0.0, 0.0)
	material.spread = 40.0
	material.initial_velocity_min = spread_speed * 0.5
	material.initial_velocity_max = spread_speed
	material.gravity = Vector3.ZERO
	material.damping_min = 40.0
	material.damping_max = 60.0
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(6.0, 26.0, 0.0)  # across both rear wheels
	# Born at size.x (x 1-1.3), each puff swells to size.y over its life.
	material.scale_min = size.x
	material.scale_max = size.x * 1.3
	var grow := Curve.new()
	grow.max_value = size.y / size.x
	grow.add_point(Vector2(0.0, 1.0))
	grow.add_point(Vector2(1.0, size.y / size.x))
	material.scale_curve = _curve_texture(grow)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	material.color_ramp = ramp

	var particles := GPUParticles2D.new()
	particles.process_material = material
	particles.texture = texture
	particles.amount = amount
	particles.lifetime = lifetime
	particles.randomness = 0.3
	particles.local_coords = false  # puffs stay where they were made
	particles.position = EMIT_FROM
	particles.emitting = false
	add_child(particles)
	return particles


static func _curve_texture(curve: Curve) -> CurveTexture:
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


## A four-pointed star with a soft glow: two thin rays crossing over a bright core.
static func _star_texture() -> ImageTexture:
	var size := 40
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) / 2.0
	for y in size:
		for x in size:
			var dx := absf(x - c) / c
			var dy := absf(y - c) / c
			# Rays thin out towards their tips; the core is a soft round glow.
			var ray := maxf(clampf(1.0 - dx - 6.0 * dy, 0.0, 1.0), clampf(1.0 - dy - 6.0 * dx, 0.0, 1.0))
			var core := clampf(1.0 - Vector2(dx, dy).length() * 2.2, 0.0, 1.0)
			var a := clampf(maxf(ray * 1.6, core * 1.4), 0.0, 1.0)
			image.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(image)


static func _puff_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1, 1, 1, 1))
	gradient.set_color(1, Color(1, 1, 1, 0))
	gradient.add_point(0.65, Color(1, 1, 1, 1))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 48
	texture.height = 48
	return texture

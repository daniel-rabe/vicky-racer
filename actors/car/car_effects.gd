extends Node2D
## Puffs from the rear wheels of its parent car: dust when it drives on grass or sand
## (from CAR_surface_changed), white tyre smoke when it drifts on the road. Particles are
## left behind in the world rather than dragged along with the car, and draw beneath it.
##
## The puff texture is built here (a soft-edged disc), so the effect needs no art file and
## stays in the flat picture-book look of the rest of the game.

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

var _surface := &"asphalt"
var _dust: GPUParticles2D
var _smoke: GPUParticles2D
var _siren: Node2D
var _siren_time := 0.0

@onready var car: Car = get_parent()


func _enter_tree() -> void:
	EventSystem.CAR_surface_changed.connect(_on_surface_changed)


func _ready() -> void:
	show_behind_parent = true
	var puff := _puff_texture()
	_dust = _emitter(puff, 32, 0.8, Vector2(0.6, 1.5), 80.0)
	_smoke = _emitter(puff, 30, 0.9, Vector2(0.6, 1.4), 40.0)
	_smoke.modulate = SMOKE_COLOUR
	_siren = _siren_lights()


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

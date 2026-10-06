extends Node2D
## What a boat leaves on the water (docs/DESIGN.md §20.6), all drawn in code in the flat
## picture-book look, like the cars' puffs:
##   - the wake: a V of white foam spreading from the stern, and a churned strip right behind
##     it, longer and thicker at speed;
##   - spray off the outside of the hull when it glides wide;
##   - a ring of splash where it lands off a ramp, and a puff where it bumps the shore.
## Everything is left behind in the world and drawn beneath the boats.

const CarEffects := preload("res://actors/car/car_effects.gd")
const FOAM := Color(1.0, 1.0, 1.0)
## The stern, and the two corners the V of the wake spreads from, in the boat's own frame.
const STERN := Vector2(-52.0, 0.0)
const SIDES := Vector2(-30.0, 26.0)
## Slower than this, px/s, and the water stays calm.
const WAKE_MIN_SPEED := 60.0

var _churn: GPUParticles2D
var _vee: Array[GPUParticles2D] = []
var _spray: GPUParticles2D
var _splash: GPUParticles2D

@onready var boat: Car = get_parent()


func _enter_tree() -> void:
	EventSystem.CAR_landed.connect(func(lander: Node) -> void:
		if lander == boat:
			_splash.restart())
	EventSystem.CAR_wall_hit.connect(func(hit: Node, impact: float) -> void:
		if hit == boat and impact > 250.0:
			_splash.restart())


func _ready() -> void:
	show_behind_parent = true
	var puff := CarEffects._puff_texture()
	_churn = _emitter(puff, 32, 0.9, Vector2(0.35, 1.0), Vector3(-1, 0, 0), 12.0, 30.0)
	_churn.position = STERN
	for side in [-1.0, 1.0]:
		var vee := _emitter(puff, 22, 1.2, Vector2(0.22, 0.6), Vector3(-0.6, side, 0), 8.0, 70.0)
		vee.position = Vector2(SIDES.x, SIDES.y * side)
		_vee.append(vee)
	_spray = _emitter(puff, 24, 0.5, Vector2(0.35, 0.8), Vector3(0, 1, 0), 30.0, 160.0)
	_splash = _ring(puff)


func _physics_process(_delta: float) -> void:
	var speed := boat.velocity.length()
	var fraction := clampf(speed / boat.config.max_speed, 0.0, 1.0)
	var airborne: bool = boat is Boat and boat.is_airborne()
	var on := not boat.frozen and not airborne and speed > WAKE_MIN_SPEED
	_churn.emitting = on
	_churn.amount_ratio = 0.3 + 0.7 * fraction
	for vee in _vee:
		vee.emitting = on and fraction > 0.15
		vee.amount_ratio = fraction
	# Spray flies off the outside of the turn: the side the boat is sliding towards.
	var sideways := boat.velocity.dot(Vector2.RIGHT.rotated(boat.rotation).orthogonal())
	_spray.emitting = on and boat.is_drifting
	_spray.position = Vector2(-6.0, 30.0 * signf(sideways))
	var material: ParticleProcessMaterial = _spray.process_material
	material.direction = Vector3(-0.3, signf(sideways), 0)


func _emitter(texture: Texture2D, amount: int, lifetime: float, size: Vector2, direction: Vector3,
		spread: float, speed: float) -> GPUParticles2D:
	var material := ParticleProcessMaterial.new()
	material.direction = direction
	material.spread = spread
	material.initial_velocity_min = speed * 0.5
	material.initial_velocity_max = speed
	material.gravity = Vector3.ZERO
	material.damping_min = 30.0
	material.damping_max = 60.0
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(4.0, 10.0, 0.0)
	material.scale_min = size.x
	material.scale_max = size.x * 1.3
	var grow := Curve.new()
	grow.max_value = size.y / size.x
	grow.add_point(Vector2(0.0, 1.0))
	grow.add_point(Vector2(1.0, size.y / size.x))
	material.scale_curve = CarEffects._curve_texture(grow)
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.75))
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
	particles.local_coords = false  # foam stays on the water where it was made
	particles.modulate = FOAM
	particles.emitting = false
	add_child(particles)
	return particles


## A ring of white water thrown out all round, left where the boat came down.
func _ring(texture: Texture2D) -> GPUParticles2D:
	var material := ParticleProcessMaterial.new()
	material.direction = Vector3(1, 0, 0)
	material.spread = 180.0
	material.initial_velocity_min = 140.0
	material.initial_velocity_max = 260.0
	material.gravity = Vector3.ZERO
	material.damping_min = 280.0
	material.damping_max = 380.0
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 30.0
	material.scale_min = 0.5
	material.scale_max = 1.0
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.95))
	fade.set_color(1, Color(0.9, 0.97, 1.0, 0.0))
	var ramp := GradientTexture1D.new()
	ramp.gradient = fade
	material.color_ramp = ramp
	var splash := GPUParticles2D.new()
	splash.name = "Splash"
	splash.process_material = material
	splash.texture = texture
	splash.amount = 36
	splash.lifetime = 0.8
	splash.one_shot = true
	splash.explosiveness = 0.95
	splash.local_coords = false
	splash.z_index = 2  # over the boat as it comes down
	splash.emitting = false
	add_child(splash)
	return splash

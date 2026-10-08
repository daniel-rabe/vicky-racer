extends "res://actors/boat/boat_effects.gd"
## What a spaceship leaves in space (docs/DESIGN.md §24.1), drawn in code like the boats' wake
## and the cars' puffs:
##   - the exhaust: a fading glow ribbon from the engine, longer at speed;
##   - stardust puffing off the outside when the ship slides wide, in place of spray;
##   - a burst of sparkles when it bumps an asteroid, the edge, or is nudged by a comet.

## The engine, in the ship's own frame, and the exhaust's warm glow.
const ENGINE := Vector2(-56.0, 0.0)
const EXHAUST := Color(1.0, 0.78, 0.4)
const STARDUST := Color(0.85, 0.9, 1.0)
const SPARKLE := Color(1.0, 0.95, 0.7)
## Slower than this, px/s, and the engine only idles.
const EXHAUST_MIN_SPEED := 40.0

var _exhaust: GPUParticles2D


func _enter_tree() -> void:
	super()
	EventSystem.CAR_comet_nudged.connect(func(nudged: Node) -> void:
		if nudged == boat:
			_splash.restart())


func _ready() -> void:
	show_behind_parent = true
	var puff := CarEffects._puff_texture()
	_exhaust = _emitter(puff, 40, 0.55, Vector2(0.4, 0.12), Vector3(-1, 0, 0), 6.0, 90.0)
	_exhaust.position = ENGINE
	_exhaust.modulate = EXHAUST
	_spray = _emitter(puff, 24, 0.7, Vector2(0.3, 0.9), Vector3(0, 1, 0), 35.0, 120.0)
	_spray.modulate = STARDUST
	_splash = _ring(puff)
	_splash.modulate = SPARKLE


func _physics_process(_delta: float) -> void:
	var speed := boat.velocity.length()
	var fraction := clampf(speed / boat.config.max_speed, 0.0, 1.0)
	var flying := not boat.frozen
	_exhaust.emitting = flying
	_exhaust.amount_ratio = 0.25 + 0.75 * fraction if speed > EXHAUST_MIN_SPEED else 0.2
	# Stardust off the outside of the slide: the side the ship is sliding towards.
	var sideways := boat.velocity.dot(Vector2.RIGHT.rotated(boat.rotation).orthogonal())
	_spray.emitting = flying and boat.is_drifting
	_spray.position = Vector2(-6.0, 30.0 * signf(sideways))
	var material: ParticleProcessMaterial = _spray.process_material
	material.direction = Vector3(-0.3, signf(sideways), 0)

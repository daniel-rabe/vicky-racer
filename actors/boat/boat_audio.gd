extends "res://actors/car/car_audio.gd"
## A boat's sounds (docs/DESIGN.md §20.6): its motor (the setup's engine_sound: an outboard,
## a jet, a hovercraft's fan) pitched by speed as a car's engine is; in place of the tyre
## squeal, water rushing past the hull — always there at speed, louder when gliding wide;
## a rubbery bonk on a buoy or the shore; and off a ramp a wet whoosh, then a splash.

const WAKE := preload("res://art/sfx/wake_loop.wav")
const BOAT_BUMP := preload("res://art/sfx/boat_bump.wav")
const WHOOSH := preload("res://art/sfx/ramp_whoosh.wav")
const SPLASH := preload("res://art/sfx/splash.wav")
const WAKE_DB := -12.0

var _splash: AudioStreamPlayer2D


func _enter_tree() -> void:
	super()
	EventSystem.CAR_jumped.connect(func(jumper: Node) -> void: _one_shot(jumper, WHOOSH, -3.0))
	EventSystem.CAR_landed.connect(func(lander: Node) -> void: _one_shot(lander, SPLASH, -2.0))


func _ready() -> void:
	super()
	_splash = _player(null, -3.0)


func _physics_process(delta: float) -> void:
	super(delta)
	# The wake: heard as soon as the boat moves, swelling with speed and with the glide.
	var fraction := clampf(car.velocity.length() / car.config.max_speed, 0.0, 1.0)
	var glide := clampf(car.lateral_speed / (car.config.drift_threshold * 2.0), 0.0, 1.0)
	var level := clampf(0.55 * fraction + 0.45 * glide, 0.0, 1.0)
	if car is Boat and car.is_airborne():
		level = 0.0
	_skid.volume_db = lerpf(SILENT_DB, WAKE_DB, sqrt(level)) if level > 0.02 else SILENT_DB - 20.0
	_skid.pitch_scale = 0.85 + 0.3 * fraction


func _skid_stream() -> AudioStream:
	return WAKE


func _bump_stream() -> AudioStream:
	return BOAT_BUMP


func _one_shot(who: Node, stream: AudioStream, volume_db: float) -> void:
	if who != car or not SoundManager.audible() or _splash == null:
		return
	_splash.stream = stream
	_splash.volume_db = volume_db
	_splash.pitch_scale = randf_range(0.95, 1.05)
	_splash.play()

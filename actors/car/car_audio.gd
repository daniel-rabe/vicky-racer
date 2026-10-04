extends Node2D
## Engine, tyre squeal and wall bump for its parent car. Positional (AudioStreamPlayer2D),
## so opponents are heard when they are near the camera and fade out when far away.
##
## The engine is one steady loop whose pitch follows speed; the squeal loop fades in with
## sideways speed while the car drifts. Sounds are art/sfx/, made by
## tools/comfy/generate_sfx.py.

const ENGINE := preload("res://art/sfx/engine_loop.wav")
const SKID := preload("res://art/sfx/skid_loop.wav")
const BUMP := preload("res://art/sfx/wall_bump.wav")
const HORN := preload("res://art/sfx/horn.wav")
const BOOST := preload("res://art/sfx/boost.wav")
## Engine pitch at a standstill and at top speed.
const PITCH_IDLE := 0.6
const PITCH_TOP := 1.5
const ENGINE_DB := -10.0
const SKID_DB := -9.0
## Quieter than this is treated as silent, dB.
const SILENT_DB := -40.0
const HEARING_DISTANCE := 1800.0

var _engine: AudioStreamPlayer2D
var _skid: AudioStreamPlayer2D
var _bump: AudioStreamPlayer2D
var _horn: AudioStreamPlayer2D
var _skid_level := 0.0

@onready var car: Car = get_parent()


func _enter_tree() -> void:
	EventSystem.CAR_wall_hit.connect(_on_wall_hit)
	EventSystem.CAR_horn.connect(_on_horn)
	EventSystem.CAR_boosted.connect(func(boosted: Node) -> void:
		if boosted == car and SoundManager.audible():
			_bump.stream = BOOST
			_bump.volume_db = -4.0
			_bump.pitch_scale = 1.0
			_bump.play())


func _ready() -> void:
	_engine = _player(ENGINE, ENGINE_DB)
	_skid = _player(SKID, SILENT_DB)
	_bump = _player(BUMP, -4.0)
	_horn = _player(HORN, -2.0)
	if not SoundManager.audible():
		set_physics_process(false)
		return
	_engine.play()
	_skid.play()


func _physics_process(delta: float) -> void:
	var fraction := clampf(car.velocity.length() / car.config.max_speed, 0.0, 1.0)
	var throttle := maxf(car.throttle_input, 0.0)
	# A little extra pitch under throttle, so pressing the pedal is heard straight away.
	var pitch := car.setup.engine_pitch if car.setup else 1.0
	_engine.pitch_scale = (lerpf(PITCH_IDLE, PITCH_TOP, fraction) + 0.08 * throttle) * pitch
	_engine.volume_db = ENGINE_DB - 4.0 * (1.0 - maxf(fraction, throttle))
	var target := 0.0
	if car.is_drifting:
		target = clampf(car.lateral_speed / (car.config.drift_threshold * 2.0), 0.4, 1.0)
	_skid_level = move_toward(_skid_level, target, delta * 6.0)
	_skid.volume_db = lerpf(SILENT_DB, SKID_DB, _skid_level) if _skid_level > 0.0 else SILENT_DB - 20.0
	_skid.pitch_scale = 0.9 + 0.2 * fraction


func _on_wall_hit(hit_car: Node, impact_speed: float) -> void:
	if hit_car == car and SoundManager.audible():
		_bump.stream = BUMP
		_bump.volume_db = lerpf(-14.0, -3.0, clampf(impact_speed / 800.0, 0.0, 1.0))
		_bump.pitch_scale = randf_range(0.9, 1.1)
		_bump.play()


func _on_horn(honking: Node) -> void:
	if honking != car or not SoundManager.audible():
		return
	_horn.stream = car.setup.horn if car.setup and car.setup.horn else HORN
	_horn.play()


func _player(stream: AudioStream, volume_db: float) -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.max_distance = HEARING_DISTANCE
	player.attenuation = 1.6
	player.bus = &"SFX"
	add_child(player)
	return player

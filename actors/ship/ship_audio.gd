extends "res://actors/car/car_audio.gd"
## A spaceship's sounds (docs/DESIGN.md §23.6): its engine (the setup's engine_sound: a
## thruster, a saucer's warble, a homemade rocket's fizz) pitched by speed as a car's is; no
## tyres, so nothing squeals in a slide; a soft rubbery bonk on an asteroid, the edge or
## another ship; and a twinkle when a comet brushes past.

const BONK := preload("res://art/sfx/asteroid_bonk.wav")
const NUDGED := preload("res://art/sfx/sparkle.wav")


func _enter_tree() -> void:
	super()
	EventSystem.CAR_comet_nudged.connect(func(nudged: Node) -> void:
		if nudged == car and SoundManager.audible():
			_bump.stream = NUDGED
			_bump.volume_db = -4.0
			_bump.pitch_scale = 1.0
			_bump.play())


func _skid_stream() -> AudioStream:
	return null


func _bump_stream() -> AudioStream:
	return BONK

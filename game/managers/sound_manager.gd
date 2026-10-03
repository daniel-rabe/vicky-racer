class_name SoundManager
extends Node
## Sounds that belong to the game rather than to one car: the 3-2-1-GO beeps, the finish
## fanfare, the coin chime when a setup is bought, and a soft click whenever menu focus
## moves. Lives in the main.tscn shell next to GarageManager, so it survives screen swaps
## and needs no autoload; listens to the event bus only. Runs while the game is paused, so
## the pause menu still clicks. Everything plays on the SFX bus (the SOUND setting).

const BEEP := preload("res://art/sfx/countdown_beep.wav")
const GO := preload("res://art/sfx/go_beep.wav")
const FANFARE := preload("res://art/sfx/finish_fanfare.wav")
const COIN := preload("res://art/sfx/coin.wav")
const CLICK := preload("res://art/sfx/ui_click.wav")

var _players: Array[AudioStreamPlayer] = []


func _enter_tree() -> void:
	EventSystem.RAC_countdown_tick.connect(func(n: int) -> void: play(GO if n == 0 else BEEP))
	EventSystem.RAC_race_finished.connect(func(_results: Array, _id: StringName) -> void: play(FANFARE, -2.0))
	EventSystem.PRO_setup_purchased.connect(func(_id: StringName) -> void: play(COIN))


func _ready() -> void:
	get_viewport().gui_focus_changed.connect(func(_control: Control) -> void: play(CLICK, -4.0))


## False under the dummy audio driver (headless runs): it never mixes, so a played sound
## never finishes and Godot reports it as leaked at exit. Tests and headless boots stay quiet.
static func audible() -> bool:
	return AudioServer.get_driver_name() != "Dummy"


## Play a one-shot. A small pool, so sounds can overlap without cutting each other off.
func play(stream: AudioStream, volume_db := 0.0) -> void:
	if not audible():
		return
	var player: AudioStreamPlayer = null
	for p in _players:
		if not p.playing:
			player = p
			break
	if player == null:
		player = AudioStreamPlayer.new()
		player.bus = &"SFX"
		add_child(player)
		_players.append(player)
	player.stream = stream
	player.volume_db = volume_db
	player.play()

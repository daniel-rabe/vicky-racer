class_name MusicManager
extends Node
## The music (docs/DESIGN.md §13). Lives in the main.tscn shell next to SoundManager, so a
## piece carries on across screens that share it (title -> garage -> pick a race) instead of
## starting over. Listens to the event bus only:
##   - a screen change picks the screen's piece (SCREEN_MUSIC) and cross-fades to it; the
##     race asks for its track theme's piece itself (UI_music_requested);
##   - the standings play a short sting, then the menu theme;
##   - the 3-2-1 countdown ducks the music under the beeps, GO brings it back;
##   - the last lap nudges it a little faster and brighter;
##   - the finish fades it out, so the fanfare plays alone;
##   - the pause menu ducks it.
## Everything plays on the Music bus (the MUSIC setting). Under the dummy audio driver
## (headless runs) nothing plays at all, but `current` still follows, so tests can check it.

const MENU := preload("res://game/configs/music/menu.tres")
const PODIUM := preload("res://game/configs/music/podium.tres")
const STANDINGS := preload("res://game/configs/music/standings.tres")
## Screens not listed (the race, dev screens) leave the music to themselves.
const SCREEN_MUSIC := {
	&"title": MENU,
	&"garage": MENU,
	&"tracks": MENU,
	&"results": MENU,
	&"shelf": MENU,
	&"join": MENU,
	&"standings": STANDINGS,
	&"podium": PODIUM,
}
const CROSS_FADE := 1.0
const FADE_OUT := 1.5
## Under the countdown beeps, and while paused.
const DUCK_DB := -10.0
const PAUSE_DB := -8.0
## The last lap: a touch faster and higher (pitch and tempo together), about a semitone.
const FINAL_LAP_PITCH := 1.06

## The piece playing (or that would be, headless); null when silent.
var current: MusicPiece
var final_lap := false
## The player of `current`; others in _players are fading out.
var _player: AudioStreamPlayer
var _players: Array[AudioStreamPlayer] = []
var _duck_db := 0.0
var _duck_tween: Tween


func _enter_tree() -> void:
	EventSystem.UI_screen_requested.connect(_on_screen_requested)
	EventSystem.UI_music_requested.connect(play)
	EventSystem.RAC_countdown_tick.connect(_on_countdown_tick)
	EventSystem.RAC_final_lap_started.connect(_on_final_lap)
	EventSystem.RAC_race_finished.connect(func(_results: Array, _id: StringName) -> void: stop(FADE_OUT))


func _process(_delta: float) -> void:
	var duck := _duck_db + (PAUSE_DB if get_tree().paused else 0.0)
	for player in _players:
		player.volume_db = linear_to_db(maxf(player.get_meta(&"fade"), 0.0001)) + duck


## Cross-fade to `piece`; the same piece again carries on where it is.
func play(piece: MusicPiece) -> void:
	if piece == current:
		return
	# A sting starts on its first note, so it cuts in instead of fading.
	var seconds := CROSS_FADE if piece == null or piece.loops else 0.3
	_fade(_player, 0.0, seconds)
	_player = null
	current = piece
	final_lap = false
	if piece == null or not SoundManager.audible():
		return
	var stream := piece.stream
	if stream is AudioStreamOggVorbis:
		stream.loop = piece.loops
		stream.loop_offset = piece.loop_offset
	_player = AudioStreamPlayer.new()
	_player.stream = stream
	_player.bus = &"Music"
	_player.set_meta(&"fade", 0.0)
	add_child(_player)
	_players.append(_player)
	_player.play()
	_fade(_player, 1.0, seconds if piece.loops else 0.01)
	if not piece.loops:
		_player.finished.connect(_on_sting_finished.bind(piece))


func stop(seconds := CROSS_FADE) -> void:
	_fade(_player, 0.0, seconds)
	_player = null
	current = null
	final_lap = false


func _on_screen_requested(screen_name: StringName) -> void:
	if SCREEN_MUSIC.has(screen_name):
		play(SCREEN_MUSIC[screen_name])


## After a sting, the menu theme — unless something else has started since.
func _on_sting_finished(piece: MusicPiece) -> void:
	if current == piece:
		play(MENU)


func _on_countdown_tick(seconds_left: int) -> void:
	if _duck_tween:
		_duck_tween.kill()
	if seconds_left > 0:
		_duck_db = DUCK_DB
		# A new race (RESTART keeps the same piece playing): back to normal speed.
		final_lap = false
		if _player:
			_player.pitch_scale = 1.0
		return
	_duck_tween = create_tween()
	_duck_tween.tween_property(self, "_duck_db", 0.0, 0.8)


func _on_final_lap() -> void:
	final_lap = true
	if _player:
		create_tween().tween_property(_player, "pitch_scale", FINAL_LAP_PITCH, 1.5)


## Fade a player to `to` (0-1); faded out to silence, it is freed.
func _fade(player: AudioStreamPlayer, to: float, seconds: float) -> void:
	if player == null:
		return
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void: player.set_meta(&"fade", v), player.get_meta(&"fade"), to, seconds)
	if to <= 0.0:
		tween.tween_callback(func() -> void:
			_players.erase(player)
			player.queue_free())

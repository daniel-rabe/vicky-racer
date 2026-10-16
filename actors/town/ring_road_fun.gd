class_name RingRoadFun
extends Node
## What happens along the ring road (docs/DESIGN.md §38; RingRoad has where things are, Town
## builds them):
##   - the tunnel's hill fades while the player is inside, so the car can be seen; going in
##     says TUNNEL! (once in a while), and a horn in there echoes back;
##   - standing still at the fuel station's pump fills the tank: the gauge goes round, then
##     FULL TANK! (again once the car has driven off and come back);
##   - the speed sign shows how fast the player goes by, WOW! when very fast.

const FADE := 0.3
const FADE_SPEED := 3.0
const TUNNEL_BANNER_EVERY := 20.0
## Seconds to fill a tank, standing still (slower than this, px/s).
const FILL_SECONDS := 2.5
const STILL := 40.0
## The echo: how long after the horn each comes back, and how much quieter (dB).
const ECHOES: Array[Vector2] = [Vector2(0.28, -9.0), Vector2(0.56, -16.0)]
## The speed sign shows px/s times this (a car at top speed reads about 110); WOW! from this.
const SPEED_SCALE := 0.1
const WOW := 100
const CHIME := "res://art/sfx/sparkle.wav"
const HORN := preload("res://art/sfx/horn.wav")

## The town screen (TownScreen): the player, the HUD, the town.
var screen: Node
var in_tunnel := false
var echoes := 0
var fills := 0
## The tank at each pad: 0 to 1, and whether it has been filled since the car came.
var _tank: Array[float] = [0.0, 0.0]
var _full: Array[bool] = [false, false]
var _since_banner := INF


func _enter_tree() -> void:
	EventSystem.CAR_horn.connect(_on_horn)


func _physics_process(delta: float) -> void:
	_since_banner += delta
	var player: Car = screen.player
	var town: Town = screen.town
	if player == null or town == null:
		return
	var at := player.global_position
	# The tunnel.
	var inside := RingRoad.in_tunnel(at)
	if inside and not in_tunnel and _since_banner > TUNNEL_BANNER_EVERY:
		_since_banner = 0.0
		screen.hud.show_banner("TUNNEL!")
	in_tunnel = inside
	if town.tunnel:
		town.tunnel.fade = move_toward(town.tunnel.fade, FADE if inside else 1.0, FADE_SPEED * delta)
	# The fuel station.
	var pad := RingRoad.on_fill_pad(at)
	for k in _tank.size():
		if k != pad:
			if not RingRoad.FILL_PADS[k].grow(250.0).has_point(at):
				_tank[k] = 0.0
				_full[k] = false
			continue
		if _full[k] or player.velocity.length() > STILL:
			continue
		_tank[k] = minf(_tank[k] + delta / FILL_SECONDS, 1.0)
		if _tank[k] >= 1.0:
			_full[k] = true
			fills += 1
			screen.hud.show_banner("FULL TANK!")
			_play(load(CHIME) if ResourceLoader.exists(CHIME) else null, 0.0)
	if town.pump:
		town.pump.fill = _tank.duplicate()
	# The speed sign.
	if town.speed_sign:
		if RingRoad.SPEED_READS.has_point(at):
			var shown := roundi(player.velocity.length() * SPEED_SCALE)
			town.speed_sign.speed = shown
			town.speed_sign.wow = shown >= WOW
		elif not RingRoad.SPEED_READS.grow(600.0).has_point(at):
			town.speed_sign.speed = -1
			town.speed_sign.wow = false


func _on_horn(honking: Node) -> void:
	if not in_tunnel or honking != screen.player:
		return
	echoes += 1
	var car: Car = honking
	var horn: AudioStream = car.setup.horn if car.setup and car.setup.horn else HORN
	for echo in ECHOES:
		get_tree().create_timer(echo.x).timeout.connect(_play.bind(horn, echo.y))


func _play(stream: AudioStream, volume: float) -> void:
	if stream == null or not SoundManager.audible() or not is_inside_tree():
		return
	var voice := AudioStreamPlayer.new()
	voice.stream = stream
	voice.volume_db = volume
	voice.bus = &"SFX"
	add_child(voice)
	voice.finished.connect(voice.queue_free)
	voice.play()

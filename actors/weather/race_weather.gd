class_name RaceWeather
extends Weather
## Weather in a race (docs/DESIGN.md §25). The track's theme says what its sky may do: rain
## (Meadow, Sunny Beach, Toy Town, Jungle Run) or snow (Snowy Peak). Some races stay dry; in
## the others one shower passes over during the race — the road gets puddles, full speed but
## slippery, and a rainbow shows when it stops — or, at Snowy Peak, it snows from the start.
## Time trials stay dry, so a ghost's lap is always fair to race against.
##
## Dev flags, after `--`: --rain (a shower straight away), --snow, --dry.

## The share of races with weather.
const RAIN_CHANCE := 0.4
const SNOW_CHANCE := 0.6
## Puddles along a lap.
const PUDDLES := 9
const SPLASH := "res://art/sfx/splash.wav"
## Raindrops landing in the puddles: rings, this many a second over all of them at full rain.
const RIPPLES_PER_SECOND := 40.0
const RIPPLE_COLOUR := Color(0.9, 0.95, 1.0, 0.7)

var track: Track
## The players' cars: their splashes are heard.
var players: Array[Node] = []
var _splash: AudioStreamPlayer
var _ripple_due := 0.0


## The weather for this race on `track`, or null for a dry one.
static func pick(on: Track, time_trial: bool) -> RaceWeather:
	var args := OS.get_cmdline_user_args()
	var sky: StringName = on.theme.weather if on.theme else &""
	if "--snow" in args:
		sky = &"snow"
	elif "--rain" in args:
		sky = &"rain"
	elif sky == &"" or time_trial or "--dry" in args:
		return null
	elif randf() >= (SNOW_CHANCE if sky == &"snow" else RAIN_CHANCE):
		return null
	var weather := RaceWeather.new()
	weather.name = "Weather"
	weather.kind = sky
	weather.track = on
	weather.repeat = false
	weather.wipers = false
	if sky == &"snow":
		weather.intensity = 1.0  # snowing as the race starts, all race long
		weather.rain_now(3600.0)
	elif "--rain" in args:
		weather.rain_seconds = Vector2(40.0, 50.0)
		weather.rain_now()
	else:
		# A shower comes some time in the first lap and lasts about a lap.
		weather.first_rain = Vector2(12.0, 30.0)
		weather.rain_seconds = Vector2(30.0, 45.0)
	return weather


func _ready() -> void:
	if kind == &"rain":
		ground = track
		track.add_puddles(PUDDLES)
		EventSystem.CAR_surface_changed.connect(_on_surface_changed)
		if ResourceLoader.exists(SPLASH):
			_splash = AudioStreamPlayer.new()
			_splash.stream = load(SPLASH)
			_splash.bus = &"SFX"
			_splash.volume_db = -12.0
			add_child(_splash)
	super._ready()


func _process(delta: float) -> void:
	super._process(delta)
	if kind != &"rain" or track.puddles.is_empty() or wetness < 0.3:
		return
	_ripple_due += delta * RIPPLES_PER_SECOND * intensity
	while _ripple_due >= 1.0:
		_ripple_due -= 1.0
		var puddle: Vector3 = track.puddles.pick_random()
		var at := Vector2(puddle.x, puddle.y) + Vector2.from_angle(randf() * TAU) * puddle.z * sqrt(randf()) * 0.8
		_ripple(track.to_local(at))


## A ring spreading out where a drop lands, on the road under the cars.
func _ripple(at: Vector2) -> void:
	var ring := Line2D.new()
	for k in 17:
		ring.add_point(Vector2.from_angle(TAU * k / 16.0) * Vector2(1.0, 0.8) * 10.0)
	ring.width = 2.5
	ring.default_color = RIPPLE_COLOUR
	ring.antialiased = true
	ring.position = at
	ring.scale = Vector2.ONE * 0.3
	track.add_child(ring)
	var tween := ring.create_tween().set_parallel()
	tween.tween_property(ring, "scale", Vector2.ONE * 2.2, 0.7).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(ring, "modulate:a", 0.0, 0.7)
	tween.chain().tween_callback(ring.queue_free)


## Into a puddle: a splash of drops, and a splash to hear for a player's car.
func _on_surface_changed(car: Node, surface: StringName) -> void:
	if surface != &"puddle" or not car is Car or (car as Car).velocity.length() < 150.0:
		return
	TownFx.drops(track.get_parent(), car.global_position, 18)
	if _splash and car in players:
		_splash.play()

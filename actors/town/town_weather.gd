class_name TownWeather
extends Node
## Rain in Free Drive (docs/DESIGN.md §23). Now and then a shower passes over the town: the
## light dims, rain streaks down the screen, wipers sweep across its bottom corners, and
## puddles fill on the roads. A puddle is a surface (Town.surface_at: &"puddle"): full speed
## but slippery, with a splash. When the rain stops a rainbow shows for a while, and the
## puddles dry up. Nothing has to be done about it; it is just weather.

## Seconds until the first shower, how long a shower lasts, and the dry spell after one.
const FIRST_RAIN := Vector2(150.0, 240.0)
const RAIN_SECONDS := Vector2(50.0, 70.0)
const DRY_SECONDS := Vector2(240.0, 420.0)
## Seconds for the roads to get fully wet, and to dry again.
const WET_IN := 6.0
const DRY_OUT := 20.0
## How dark it gets under the clouds.
const GLOOM := Color(0.76, 0.79, 0.88)
const RAINBOW_SECONDS := 9.0
const RAINBOW := [Color(0.9, 0.22, 0.27), Color(1.0, 0.6, 0.2), Color(1.0, 0.85, 0.25), Color(0.2, 0.75, 0.4),
	Color(0.25, 0.55, 1.0), Color(0.6, 0.35, 0.95)]
const RAIN_SOUND := "res://art/sfx/rain_loop.wav"

var town: Town
var raining := false
## 0 dry .. 1 soaked: how much the puddles show.
var wetness := 0.0
## 0 .. 1: how heavy the rain is now (it swells in and dies away).
var intensity := 0.0

var _next := 0.0
var _layer: CanvasLayer
var _rain: GPUParticles2D
var _gloom: CanvasModulate
var _wipers: Array[Node2D] = []
var _rainbow: Node2D
var _sound: AudioStreamPlayer
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_next = _rng.randf_range(FIRST_RAIN.x, FIRST_RAIN.y)
	_gloom = CanvasModulate.new()
	_gloom.name = "Gloom"
	_gloom.color = Color.WHITE
	add_child(_gloom)
	_layer = CanvasLayer.new()
	_layer.name = "Weather"
	add_child(_layer)
	_rain = _make_rain()
	_layer.add_child(_rain)
	for side in [-1.0, 1.0]:
		var wiper := _make_wiper(side)
		_layer.add_child(wiper)
		_wipers.append(wiper)
	_rainbow = _make_rainbow()
	_layer.add_child(_rainbow)
	if ResourceLoader.exists(RAIN_SOUND) and SoundManager.audible():
		_sound = AudioStreamPlayer.new()
		_sound.stream = load(RAIN_SOUND)
		_sound.bus = &"SFX"
		_sound.volume_db = -60.0
		add_child(_sound)
		_sound.finished.connect(_sound.play)


## Start a shower now (dev: --rain, and the tests).
func rain_now(seconds := 0.0) -> void:
	raining = true
	_next = seconds if seconds > 0.0 else _rng.randf_range(RAIN_SECONDS.x, RAIN_SECONDS.y)


func _process(delta: float) -> void:
	_time += delta
	_next -= delta
	if _next <= 0.0:
		if raining:
			raining = false
			_next = _rng.randf_range(DRY_SECONDS.x, DRY_SECONDS.y)
			_show_rainbow()
		else:
			rain_now()
	intensity = move_toward(intensity, 1.0 if raining else 0.0, delta / 3.0)
	wetness = move_toward(wetness, 1.0 if raining else 0.0, delta / (WET_IN if raining else DRY_OUT))
	if town:
		town.set_wet(wetness)
	_gloom.color = Color.WHITE.lerp(GLOOM, intensity)
	_rain.emitting = intensity > 0.02
	_rain.amount_ratio = clampf(intensity, 0.05, 1.0)
	_layer.offset = Vector2.ZERO
	var size := _screen_size()
	_rain.position = Vector2(size.x * 0.5, -40.0)
	(_rain.process_material as ParticleProcessMaterial).emission_box_extents = Vector3(size.x * 0.65, 10.0, 0.0)
	for i in _wipers.size():
		var wiper := _wipers[i]
		wiper.visible = intensity > 0.3
		wiper.position = Vector2(size.x * (0.1 if i == 0 else 0.9), size.y + 30.0)
		var swing := (sin(_time * 3.2) * 0.5 + 0.5) * 0.9
		wiper.rotation = (-1.0 if i == 0 else 1.0) * (0.15 + swing)
		wiper.modulate.a = clampf((intensity - 0.3) * 2.0, 0.0, 0.5)
	_rainbow.position = Vector2(size.x * 0.5, size.y * 0.62)
	if _sound:
		if intensity > 0.0 and not _sound.playing:
			_sound.play()
		_sound.volume_db = linear_to_db(maxf(intensity, 0.001)) - 12.0
		if intensity <= 0.0 and _sound.playing:
			_sound.stop()


func _screen_size() -> Vector2:
	return get_viewport().get_visible_rect().size


func _show_rainbow() -> void:
	var tween := _rainbow.create_tween()
	tween.tween_interval(2.5)
	tween.tween_property(_rainbow, "modulate:a", 0.55, 2.0)
	tween.tween_interval(RAINBOW_SECONDS)
	tween.tween_property(_rainbow, "modulate:a", 0.0, 3.0)


## Streaks falling across the whole screen, a little slanted.
func _make_rain() -> GPUParticles2D:
	var image := Image.create(4, 48, false, Image.FORMAT_RGBA8)
	for y in 48:
		var a := 0.15 + 0.55 * float(y) / 47.0
		for x in 4:
			image.set_pixel(x, y, Color(0.9, 0.95, 1.0, a * (1.0 if x in [1, 2] else 0.4)))
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(1200.0, 10.0, 0.0)
	material.direction = Vector3(-0.25, 1.0, 0.0)
	material.spread = 2.0
	material.initial_velocity_min = 1500.0
	material.initial_velocity_max = 1900.0
	material.gravity = Vector3.ZERO
	material.particle_flag_align_y = true
	var rain := GPUParticles2D.new()
	rain.name = "Rain"
	rain.process_material = material
	rain.texture = ImageTexture.create_from_image(image)
	rain.amount = 260
	rain.lifetime = 0.8
	rain.visibility_rect = Rect2(-3000, -200, 6000, 2400)
	rain.emitting = false
	return rain


## A wiper blade from a bottom corner of the screen: a dark arm with a rubber edge.
func _make_wiper(side: float) -> Node2D:
	var wiper := Node2D.new()
	wiper.name = "Wiper"
	var arm := Line2D.new()
	arm.points = PackedVector2Array([Vector2.ZERO, Vector2(side * -60.0, -560.0)])
	arm.width = 18.0
	arm.default_color = Color(0.12, 0.12, 0.14)
	arm.begin_cap_mode = Line2D.LINE_CAP_ROUND
	arm.end_cap_mode = Line2D.LINE_CAP_ROUND
	wiper.add_child(arm)
	wiper.visible = false
	return wiper


## A rainbow arc across the middle of the sky, hidden until a shower ends.
func _make_rainbow() -> Node2D:
	var bow := Node2D.new()
	bow.name = "Rainbow"
	for i in RAINBOW.size():
		var band := Line2D.new()
		var radius := 820.0 - i * 26.0
		for k in 41:
			band.add_point(Vector2.from_angle(PI + PI * k / 40.0) * radius)
		band.width = 28.0
		band.default_color = RAINBOW[i]
		bow.add_child(band)
	bow.modulate.a = 0.0
	return bow

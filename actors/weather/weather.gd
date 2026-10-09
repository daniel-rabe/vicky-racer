class_name Weather
extends Node
## Weather over a screen (docs/DESIGN.md §23, §25): now and then a shower passes over. The
## light dims, rain streaks down the screen, wipers sweep across its bottom corners, and the
## ground gets wet — `ground` (Town or Track) is told how wet with set_wet(0..1), and shows
## its puddles: full speed but slippery, with a splash. When the rain stops a rainbow shows
## for a while, and the puddles dry up. Nothing has to be done about it; it is just weather.
##
## With `kind` snow, flakes drift down instead: no wipers, no puddles and no rainbow.
##
## The owner sets the schedule before adding it: when the first shower comes, how long one
## lasts, the dry spell after it (Free Drive), or `repeat` false for one shower only (a race).

## Seconds for the ground to get fully wet, and to dry again.
const WET_IN := 6.0
const DRY_OUT := 20.0
## How dark it gets under the clouds; snow is brighter and cooler.
const GLOOM := Color(0.76, 0.79, 0.88)
const SNOW_GLOOM := Color(0.86, 0.9, 1.0)
const RAINBOW_SECONDS := 9.0
const RAINBOW := [Color(0.9, 0.22, 0.27), Color(1.0, 0.6, 0.2), Color(1.0, 0.85, 0.25), Color(0.2, 0.75, 0.4),
	Color(0.25, 0.55, 1.0), Color(0.6, 0.35, 0.95)]
const RAIN_SOUND := "res://art/sfx/rain_loop.wav"

## &"rain" or &"snow".
var kind := &"rain"
## Told how wet it is (set_wet), if it has puddles.
var ground: Object
## Seconds until the first shower, how long a shower lasts, and the dry spell after one.
var first_rain := Vector2(150.0, 240.0)
var rain_seconds := Vector2(50.0, 70.0)
var dry_seconds := Vector2(240.0, 420.0)
## Where the gloom goes, if not here: the split screen's world, drawn in its own viewports.
var world: Node
## Wipers sweep the bottom corners in the rain (not in a race, where the HUD is there).
var wipers := true
## False: one shower, then it stays dry.
var repeat := true
var raining := false
## 0 dry .. 1 soaked: how much the puddles show.
var wetness := 0.0
## 0 .. 1: how heavy the rain is now (it swells in and dies away).
var intensity := 0.0

var _next := 0.0
var _done := false
var _layer: CanvasLayer
var _rain: GPUParticles2D
var _gloom: CanvasModulate
var _wipers: Array[Node2D] = []
var _rainbow: Node2D
var _sound: AudioStreamPlayer
var _time := 0.0
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


func _ready() -> void:
	if not raining:  # unless rain_now came first
		_next = _rng.randf_range(first_rain.x, first_rain.y)
	_gloom = CanvasModulate.new()
	_gloom.name = "Gloom"
	_gloom.color = Color.WHITE
	(world if world else self).add_child(_gloom)
	_layer = CanvasLayer.new()
	_layer.name = "Weather"
	add_child(_layer)
	_rain = _make_snow() if kind == &"snow" else _make_rain()
	_layer.add_child(_rain)
	_rain.emitting = intensity > 0.02  # already falling (a race that starts in the snow)
	if kind == &"snow":
		return
	for side in ([-1.0, 1.0] if wipers else []):
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
	_next = seconds if seconds > 0.0 else _rng.randf_range(rain_seconds.x, rain_seconds.y)


func _process(delta: float) -> void:
	_time += delta
	_next -= delta
	if _next <= 0.0 and not _done:
		if raining:
			raining = false
			_done = not repeat
			_next = _rng.randf_range(dry_seconds.x, dry_seconds.y)
			if _rainbow:
				_show_rainbow()
		else:
			rain_now()
	intensity = move_toward(intensity, 1.0 if raining else 0.0, delta / 3.0)
	if kind == &"rain":
		wetness = move_toward(wetness, 1.0 if raining else 0.0, delta / (WET_IN if raining else DRY_OUT))
		if ground:
			ground.set_wet(wetness)
	_gloom.color = Color.WHITE.lerp(SNOW_GLOOM if kind == &"snow" else GLOOM, intensity)
	_rain.emitting = intensity > 0.02
	_rain.amount_ratio = clampf(intensity, 0.05, 1.0)
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
	if _rainbow:
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


## Soft round flakes of different sizes, falling slowly, a little this way and that.
func _make_snow() -> GPUParticles2D:
	var image := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 24:
			# White in the middle with a soft blue-grey edge, so a flake shows on snow too.
			var d := Vector2(x - 11.5, y - 11.5).length() / 11.5
			var edge := Color(0.55, 0.64, 0.82).lerp(Color.WHITE, clampf((0.75 - d) / 0.3, 0.0, 1.0))
			edge.a = clampf((1.0 - d) / 0.25, 0.0, 1.0)
			image.set_pixel(x, y, edge)
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(1200.0, 10.0, 0.0)
	material.direction = Vector3(-0.15, 1.0, 0.0)
	material.spread = 12.0
	material.initial_velocity_min = 170.0
	material.initial_velocity_max = 300.0
	material.gravity = Vector3.ZERO
	material.scale_min = 0.35
	material.scale_max = 1.0
	material.color = Color(1, 1, 1, 0.9)
	var snow := GPUParticles2D.new()
	snow.name = "Snow"
	snow.process_material = material
	snow.texture = ImageTexture.create_from_image(image)
	snow.amount = 220
	snow.lifetime = 7.0
	snow.preprocess = 7.0
	snow.visibility_rect = Rect2(-3000, -200, 6000, 2400)
	snow.emitting = false
	return snow


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

class_name FireDuty
extends Node2D
## Out in the fire engine (docs/DESIGN.md §23). While the player drives it, FIRES little
## garden bonfires smoke beside houses round town, shown on the map. Holding the drift button
## (Space / X) sprays water from the engine's nose; a fire in the jet goes out after
## DOUSE_SECONDS with a puff of steam and pays PAY coins, and another starts somewhere else
## a little later. The jet makes flower beds it reaches bounce. The fires all go when the
## engine is parked back at the station: nothing burns while nobody is there to help.

const FIRES := 3
const DOUSE_SECONDS := 0.8
## The jet reaches this far from the nose, and this wide (cosine of the half-angle).
const REACH := 480.0
const SPREAD := 0.82
const PAY := 5
const RESPAWN := 8.0
const OUT_SOUND := "res://art/sfx/fire_out.wav"
const SPLASH := "res://art/sfx/splash.wav"
const SPRAY_SOUND := "res://art/sfx/water_spray.wav"
const FLAME := Color(1.0, 0.55, 0.15)
const SMOKE := Color(0.55, 0.55, 0.58)
## The map's dot for a fire.
const MARK := Color(1.0, 0.45, 0.1)

## The town screen (game/screens/town.gd).
var screen: Node
var engine: Car
var active := false
## The fires burning now: {node, at, water (s of spray so far)}.
var fires: Array[Dictionary] = []
var spraying := false

var _spray: CPUParticles2D
var _hiss: AudioStreamPlayer2D
var _voice: AudioStreamPlayer2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	if SoundManager.audible():
		_voice = AudioStreamPlayer2D.new()
		_voice.bus = &"SFX"
		_voice.max_distance = 2000.0
		add_child(_voice)


## The player has got into the fire engine.
func start(fire_engine: Car) -> void:
	engine = fire_engine
	active = true
	if _spray == null or not is_instance_valid(_spray):
		_spray = _make_spray()
		engine.add_child(_spray)
		_spray.position = Vector2(engine.body_texture.get_width() * 0.5, 0)
	for i in FIRES:
		_light_fire()


## Back at the station: the fires fade away.
func stop() -> void:
	active = false
	spraying = false
	if _spray:
		_spray.emitting = false
	if _hiss:
		_hiss.stop()
	for fire in fires:
		var node: Node2D = fire["node"]
		var tween := node.create_tween()
		tween.tween_property(node, "modulate:a", 0.0, 0.5)
		tween.tween_callback(node.queue_free)
	fires.clear()


func marks() -> Array:
	return fires.map(func(fire: Dictionary) -> Array: return [fire["at"], MARK])


func _physics_process(delta: float) -> void:
	if not active or engine == null:
		return
	spraying = engine.handbrake and not engine.frozen
	_spray.emitting = spraying
	_spray_sound(spraying)
	if not spraying:
		return
	var nose := engine.global_position + Vector2.RIGHT.rotated(engine.rotation) * engine.body_texture.get_width() * 0.5
	var ahead := Vector2.RIGHT.rotated(engine.rotation)
	for fire in fires.duplicate():
		if _in_jet(nose, ahead, fire["at"]):
			fire["water"] += delta
			var node: Node2D = fire["node"]
			node.scale = Vector2.ONE * clampf(1.0 - fire["water"] / DOUSE_SECONDS * 0.6, 0.4, 1.0)
			if fire["water"] >= DOUSE_SECONDS:
				_put_out(fire)
	for bed: Sprite2D in screen.town.flower_beds:
		if _in_jet(nose, ahead, bed.global_position) and not bed.has_meta(&"watered"):
			_water(bed)


func _in_jet(nose: Vector2, ahead: Vector2, at: Vector2) -> bool:
	var rel := at - nose
	return rel.length() < REACH and (rel.length() < 60.0 or ahead.dot(rel.normalized()) > SPREAD)


func _put_out(fire: Dictionary) -> void:
	fires.erase(fire)
	var node: Node2D = fire["node"]
	TownFx.steam(screen.get_node(^"World"), fire["at"])
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 0.0, 0.4)
	tween.tween_callback(node.queue_free)
	screen.pay(PAY, fire["at"])
	_play(OUT_SOUND if ResourceLoader.exists(OUT_SOUND) else SPLASH, -4.0, 1.3, fire["at"])
	get_tree().create_timer(RESPAWN, false).timeout.connect(func() -> void:
		if active and fires.size() < FIRES:
			_light_fire())


## A flower bed in the jet: it bounces, and sparkles of water fly off it.
func _water(bed: Sprite2D) -> void:
	bed.set_meta(&"watered", true)
	var rest := bed.scale
	var tween := bed.create_tween()
	tween.tween_property(bed, "scale", rest * 1.25, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(bed, "scale", rest, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_interval(1.0)
	tween.tween_callback(func() -> void: bed.remove_meta(&"watered"))
	TownFx.drops(screen.get_node(^"World"), bed.global_position, 12)


## A bonfire in a front garden: on the grass beside a house that faces a street, near the
## pavement, clear of other fires and of the engine.
func _light_fire() -> void:
	var town: Town = screen.town
	for attempt in 60:
		var house: Dictionary = town.houses[_rng.randi() % town.houses.size()]
		var sprite: Sprite2D = house["sprite"]
		var width := sprite.texture.get_width()
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var at: Vector2 = house["door"] + Vector2(side * (width * 0.5 + 70.0), -TownLayout.SIDEWALK - 80.0)
		if town.surface_at(at) != &"grass":
			continue
		if town.footprints.any(func(r: Rect2) -> bool: return r.grow(50.0).has_point(at)):
			continue
		if town.tree_spots.any(func(t: Vector2) -> bool: return t.distance_to(at) < 100.0):
			continue
		if fires.any(func(f: Dictionary) -> bool: return f["at"].distance_to(at) < 1200.0):
			continue
		if engine and engine.global_position.distance_to(at) < 900.0:
			continue
		var node := _bonfire()
		add_child(node)
		node.global_position = at
		node.modulate.a = 0.0
		node.create_tween().tween_property(node, "modulate:a", 1.0, 0.6)
		fires.append({"node": node, "at": at, "water": 0.0})
		return


## A ring of stones round crossed logs, flames flickering up and smoke drifting off.
func _bonfire() -> Node2D:
	var fire := Node2D.new()
	fire.name = "Bonfire"
	fire.z_index = 2
	for k in 8:
		fire.add_child(TownErrands._disc(Vector2.from_angle(TAU * k / 8.0) * 38.0, 11.0, Color(0.55, 0.53, 0.5)))
	for angle in [0.5, -0.5]:
		var stick := Polygon2D.new()
		stick.polygon = PackedVector2Array([Vector2(-34, -7), Vector2(34, -7), Vector2(34, 7), Vector2(-34, 7)])
		stick.rotation = angle
		stick.color = Color(0.45, 0.28, 0.15)
		fire.add_child(stick)
	var flames := CPUParticles2D.new()
	flames.name = "Flames"
	flames.texture = TownFx.CarEffects._puff_texture()
	flames.amount = 26
	flames.lifetime = 0.6
	flames.direction = Vector2.UP
	flames.spread = 30.0
	flames.initial_velocity_min = 40.0
	flames.initial_velocity_max = 90.0
	flames.gravity = Vector2.ZERO
	flames.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	flames.emission_sphere_radius = 18.0
	flames.scale_amount_min = 0.6
	flames.scale_amount_max = 1.1
	var heat := Gradient.new()
	heat.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	heat.colors = PackedColorArray([Color(1.0, 0.9, 0.35, 1.0), FLAME, Color(0.9, 0.2, 0.1, 0.0)])
	flames.color_ramp = heat
	fire.add_child(flames)
	var smoke := CPUParticles2D.new()
	smoke.name = "Smoke"
	smoke.texture = flames.texture
	smoke.amount = 14
	smoke.lifetime = 2.2
	smoke.direction = Vector2(0.6, -1.0)
	smoke.spread = 20.0
	smoke.initial_velocity_min = 40.0
	smoke.initial_velocity_max = 70.0
	smoke.gravity = Vector2.ZERO
	smoke.position = Vector2(0, -20)
	smoke.scale_amount_min = 1.0
	smoke.scale_amount_max = 2.4
	var drift := Gradient.new()
	drift.offsets = PackedFloat32Array([0.0, 1.0])
	drift.colors = PackedColorArray([Color(SMOKE, 0.55), Color(SMOKE, 0.0)])
	smoke.color_ramp = drift
	fire.add_child(smoke)
	return fire


## The hose: a fan of water drops thrown forward from the nose.
func _make_spray() -> CPUParticles2D:
	var spray := CPUParticles2D.new()
	spray.name = "Hose"
	spray.texture = TownFx.CarEffects._puff_texture()
	spray.amount = 60
	spray.lifetime = 0.5
	spray.direction = Vector2.RIGHT
	spray.spread = 9.0
	spray.initial_velocity_min = 820.0
	spray.initial_velocity_max = 980.0
	spray.gravity = Vector2.ZERO
	spray.scale_amount_min = 0.25
	spray.scale_amount_max = 0.55
	spray.local_coords = false
	spray.z_index = 4
	var water := Gradient.new()
	water.offsets = PackedFloat32Array([0.0, 1.0])
	water.colors = PackedColorArray([Color(0.75, 0.9, 1.0, 0.95), Color(0.85, 0.95, 1.0, 0.0)])
	spray.color_ramp = water
	spray.emitting = false
	return spray


func _spray_sound(on: bool) -> void:
	if not ResourceLoader.exists(SPRAY_SOUND) or not SoundManager.audible():
		return
	if _hiss == null:
		_hiss = AudioStreamPlayer2D.new()
		_hiss.stream = load(SPRAY_SOUND)
		_hiss.bus = &"SFX"
		_hiss.volume_db = -8.0
		engine.add_child(_hiss)
		_hiss.finished.connect(func() -> void:
			if spraying:
				_hiss.play())
	if on and not _hiss.playing:
		_hiss.play()
	elif not on and _hiss.playing:
		_hiss.stop()


func _play(path: String, volume_db: float, pitch: float, at: Vector2) -> void:
	if _voice == null or not ResourceLoader.exists(path):
		return
	_voice.stream = load(path)
	_voice.volume_db = volume_db
	_voice.pitch_scale = pitch
	_voice.global_position = at
	_voice.play()

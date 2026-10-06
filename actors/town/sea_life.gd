class_name SeaLife
extends Node2D
## What lives round Free Drive's island (docs/DESIGN.md §21.5): two sailboats on fixed loops,
## a pod of dolphins that comes to leap beside a boat sailing near it, seagulls circling over
## the harbour and the lighthouse, and the lighthouse's beam sweeping round.
##
## The sailboats, dolphins and gulls are side-on pictures (FLUX would not draw them from
## above): they are never turned, only mirrored to face the way they go. The sailboats are
## bumpers a boat bounces off; nothing else here touches a vehicle.

const SAILBOAT := preload("res://art/town/island/sailboat.png")
const DOLPHIN := preload("res://art/town/island/dolphin.png")
const GULL := preload("res://art/town/island/seagull.png")
const SAIL_SPEED := 150.0
const SAIL_SIZE := 260.0
## The pod: how many, how near a boat must come to bring it over, how far it follows from home.
const DOLPHINS := 3
const DOLPHIN_SIZE := 200.0
const DOLPHIN_NOTICE := 1100.0
const DOLPHIN_ROAM := 2600.0
const DOLPHIN_SPEED := 900.0
const LEAP_SECONDS := 0.9
const LEAP_EVERY := Vector2(1.0, 2.4)
const GULL_SIZE := 110.0
const GULL_CIRCLE := 170.0
const HEAR_HORN := 520.0
const GULL_AWAY_SECONDS := 9.0
const BEAM_LENGTH := 1700.0
const BEAM_TURN := 0.5  # radians per second
const SKY_Z := 20
const LIFE_Z := 4

## The player's vehicle, whichever it is now (the screen keeps this up to date).
var player: Car
var dolphin_voice: AudioStream
var gull_voice: AudioStream

var _sailboats: Array[Dictionary] = []  # {body, sprite, loop, along, length}
var _pod_centre := Island.DOLPHIN_HOME
var _dolphins: Array[Dictionary] = []   # {sprite, ring, offset, leap, next, dir}
var _gulls: Array[Dictionary] = []      # {sprite, shadow, spot, angle, away}
var _beam: Polygon2D
var _voice: AudioStreamPlayer2D
var _voice_cooldown := 0.0
var _time := 0.0


func _enter_tree() -> void:
	EventSystem.CAR_horn.connect(_on_horn)


func _ready() -> void:
	for loop in Island.sail_loops():
		_add_sailboat(loop)
	for i in DOLPHINS:
		var sprite := Sprite2D.new()
		sprite.texture = DOLPHIN
		sprite.scale = Vector2.ONE * DOLPHIN_SIZE / DOLPHIN.get_width()
		sprite.z_index = LIFE_Z
		sprite.visible = false
		add_child(sprite)
		var ring := _ripple()
		add_child(ring)
		_dolphins.append({"sprite": sprite, "ring": ring, "offset": Vector2(-120.0 + i * 120.0, (i % 2) * 140.0 - 70.0),
			"leap": 0.0, "next": randf_range(0.3, 1.5), "dir": -1.0, "from": Vector2.ZERO})
	for spot in Island.GULL_SPOTS:
		var shadow := Sprite2D.new()
		shadow.texture = GULL
		shadow.modulate = Color(0, 0, 0, 0.18)
		shadow.scale = Vector2.ONE * GULL_SIZE * 0.8 / GULL.get_width()
		add_child(shadow)
		var sprite := Sprite2D.new()
		sprite.texture = GULL
		sprite.scale = Vector2.ONE * GULL_SIZE / GULL.get_width()
		sprite.z_index = SKY_Z
		add_child(sprite)
		_gulls.append({"sprite": sprite, "shadow": shadow, "spot": spot, "angle": randf() * TAU, "away": 0.0,
			"flee": Vector2.ZERO})
	_beam = Polygon2D.new()
	_beam.polygon = PackedVector2Array([Vector2.ZERO, Vector2(BEAM_LENGTH, -260.0), Vector2(BEAM_LENGTH, 260.0)])
	_beam.vertex_colors = PackedColorArray([Color(1, 0.95, 0.65, 0.55), Color(1, 0.95, 0.65, 0.0), Color(1, 0.95, 0.65, 0.0)])
	_beam.position = Island.LIGHTHOUSE + Vector2(0, -230)
	_beam.z_index = Town.TREE_Z + 1
	add_child(_beam)
	_voice = AudioStreamPlayer2D.new()
	_voice.bus = &"SFX"
	_voice.max_distance = 2200.0
	add_child(_voice)


func _physics_process(delta: float) -> void:
	_time += delta
	for boat in _sailboats:
		_sail(boat, delta)


func _process(delta: float) -> void:
	_voice_cooldown = maxf(_voice_cooldown - delta, 0.0)
	_beam.rotation += BEAM_TURN * delta
	_swim(delta)
	for gull in _gulls:
		_fly(gull, delta)


# --- sailboats -------------------------------------------------------------------------

func _add_sailboat(loop: PackedVector2Array) -> void:
	var body := AnimatableBody2D.new()
	body.collision_layer = Car.LAYER_WORLD
	body.collision_mask = 0
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 40.0
	capsule.height = 190.0
	shape.shape = capsule
	shape.rotation = PI / 2.0
	shape.position = Vector2(0, 50)
	body.add_child(shape)
	var sprite := Sprite2D.new()
	sprite.texture = SAILBOAT
	sprite.scale = Vector2.ONE * SAIL_SIZE / SAILBOAT.get_width()
	sprite.z_index = LIFE_Z
	body.add_child(sprite)
	add_child(body)
	var length := 0.0
	for i in loop.size():
		length += loop[i].distance_to(loop[(i + 1) % loop.size()])
	var boat := {"body": body, "sprite": sprite, "loop": loop, "along": randf() * length, "length": length}
	_sailboats.append(boat)
	body.position = _along(boat)


func _sail(boat: Dictionary, delta: float) -> void:
	boat["along"] = fmod(boat["along"] + SAIL_SPEED * delta, boat["length"])
	var at := _along(boat)
	var body: AnimatableBody2D = boat["body"]
	var moving := at - body.position
	body.position = at
	var sprite: Sprite2D = boat["sprite"]
	if absf(moving.x) > 0.05:
		sprite.flip_h = moving.x < 0.0  # the picture's bow points right
	sprite.rotation = sin(_time * 1.3 + boat["length"]) * 0.05


func _along(boat: Dictionary) -> Vector2:
	var loop: PackedVector2Array = boat["loop"]
	var left: float = boat["along"]
	for i in loop.size():
		var a := loop[i]
		var b := loop[(i + 1) % loop.size()]
		var d := a.distance_to(b)
		if left <= d:
			return a.lerp(b, left / maxf(d, 0.001))
		left -= d
	return loop[0]


# --- dolphins --------------------------------------------------------------------------

## The pod stays near home until a boat sails close, then swims along beside it — as far as
## DOLPHIN_ROAM from home — leaping out of the water now and then.
func _swim(delta: float) -> void:
	var target := Island.DOLPHIN_HOME
	var boat := player as Boat
	if boat and boat.global_position.distance_to(_pod_centre) < DOLPHIN_NOTICE:
		var side := Town.right_of(boat.velocity.normalized()) * 260.0 if boat.velocity.length() > 50.0 else Vector2(0, 260)
		target = boat.global_position + side
		if target.distance_to(Island.DOLPHIN_HOME) > DOLPHIN_ROAM:
			target = Island.DOLPHIN_HOME + (target - Island.DOLPHIN_HOME).limit_length(DOLPHIN_ROAM)
	var step := _pod_centre.move_toward(target, DOLPHIN_SPEED * delta) - _pod_centre
	_pod_centre += step
	for d in _dolphins:
		var sprite: Sprite2D = d["sprite"]
		var ring: Node2D = d["ring"]
		var home: Vector2 = _pod_centre + d["offset"]
		if d["leap"] > 0.0:
			d["leap"] = maxf(d["leap"] - delta, 0.0)
			var t: float = 1.0 - d["leap"] / LEAP_SECONDS
			var hop := sin(PI * t)
			sprite.position = d["from"] + Vector2(d["dir"] * 220.0 * t, -90.0 * hop)
			sprite.rotation = d["dir"] * lerpf(-0.55, 0.55, t)
			sprite.scale = Vector2.ONE * DOLPHIN_SIZE / DOLPHIN.get_width() * (1.0 + 0.15 * hop)
			if d["leap"] == 0.0:
				sprite.visible = false
				_splash(sprite.position)
		else:
			d["next"] -= delta
			if d["next"] <= 0.0:
				_leap(d, home, step)
		ring.position = home
		ring.modulate.a = 0.35 + 0.25 * sin(_time * 3.0 + d["offset"].x)


func _leap(d: Dictionary, at: Vector2, heading: Vector2) -> void:
	var sprite: Sprite2D = d["sprite"]
	d["dir"] = signf(heading.x) if absf(heading.x) > 0.1 else (1.0 if randf() < 0.5 else -1.0)
	d["from"] = at - Vector2(d["dir"] * 110.0, 0)
	d["leap"] = LEAP_SECONDS
	d["next"] = randf_range(LEAP_EVERY.x, LEAP_EVERY.y) + LEAP_SECONDS
	sprite.flip_h = d["dir"] > 0.0  # the picture's nose points left
	sprite.position = d["from"]
	sprite.visible = true
	_splash(d["from"])
	if player and at.distance_to(player.global_position) < 900.0:
		_say(dolphin_voice, at)


func _ripple() -> Line2D:
	var ring := Line2D.new()
	for k in 25:
		ring.add_point(Vector2(cos(TAU * k / 24.0) * 70.0, sin(TAU * k / 24.0) * 28.0))
	ring.width = 6.0
	ring.default_color = Color(1, 1, 1, 0.8)
	return ring


func _splash(at: Vector2) -> void:
	var spray := CPUParticles2D.new()
	spray.position = at
	spray.z_index = LIFE_Z
	spray.one_shot = true
	spray.explosiveness = 0.9
	spray.amount = 18
	spray.lifetime = 0.6
	spray.direction = Vector2.UP
	spray.spread = 70.0
	spray.initial_velocity_min = 90.0
	spray.initial_velocity_max = 200.0
	spray.gravity = Vector2(0, 420)
	spray.scale_amount_min = 4.0
	spray.scale_amount_max = 9.0
	spray.color = Color(1, 1, 1, 0.85)
	spray.emitting = true
	add_child(spray)
	get_tree().create_timer(1.0, false).timeout.connect(spray.queue_free)


# --- gulls -----------------------------------------------------------------------------

## Circling over its spot, flapping; a horn nearby sends it off crying, and it comes back
## a while later.
func _fly(gull: Dictionary, delta: float) -> void:
	var sprite: Sprite2D = gull["sprite"]
	var shadow: Sprite2D = gull["shadow"]
	var base := GULL_SIZE / GULL.get_width()
	gull["angle"] += delta * 0.7
	var circling: Vector2 = gull["spot"] + Vector2(cos(gull["angle"]), sin(gull["angle"]) * 0.6) * GULL_CIRCLE
	if gull["away"] > 0.0:
		gull["away"] = maxf(gull["away"] - delta, 0.0)
		var gone: float = GULL_AWAY_SECONDS - gull["away"]
		if gone < 2.5:  # flying off, fading out
			sprite.position += gull["flee"] * delta
			sprite.modulate.a = 1.0 - gone / 2.5
		else:  # gone, then fading back in over its spot for the last 2 s
			sprite.position = circling
			sprite.modulate.a = clampf(1.0 - gull["away"] / 2.0, 0.0, 1.0)
	else:
		sprite.position = circling
		sprite.modulate.a = 1.0
	sprite.scale = Vector2(base, base * (0.85 + 0.15 * sin(_time * 9.0 + gull["angle"])))
	shadow.position = sprite.position + Vector2(90, 140)
	shadow.modulate.a = 0.18 * sprite.modulate.a


func _on_horn(car: Node) -> void:
	if not car is Node2D:
		return
	for gull in _gulls:
		var sprite: Sprite2D = gull["sprite"]
		if gull["away"] == 0.0 and sprite.position.distance_to(car.global_position) < HEAR_HORN:
			gull["away"] = GULL_AWAY_SECONDS
			gull["flee"] = (sprite.position - car.global_position).normalized() * 420.0 + Vector2(0, -120)
			_say(gull_voice, sprite.position)


func _say(voice: AudioStream, at: Vector2) -> void:
	if voice == null or _voice_cooldown > 0.0:
		return
	_voice.stream = voice
	_voice.global_position = at
	_voice.play()
	_voice_cooldown = 2.0

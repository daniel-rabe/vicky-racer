class_name BusRoute
extends Node2D
## The school bus (docs/DESIGN.md §23). Animals wait at the town's bus stops: a dog, a cat, a
## duck, up to MAX_WAITING at each. When the player drives the bus and stops it beside a
## stop, first everyone who got on somewhere else hops off (PAY coins each, a little wave of
## hearts), then everyone waiting hops on. Passengers show in a row on the HUD. Stops fill up
## again over time. Parking the bus back at the school lets everyone off there.

const MAX_WAITING := 3
const MAX_RIDING := 6
## Stopping this near a stop, this slow, opens the doors.
const STOP_REACH := 260.0
const STOP_SPEED := 140.0
const PAY := 3
## Seconds between a stop getting another passenger.
const REFILL := Vector2(9.0, 16.0)
const ANIMALS := ["res://art/town/animals/dog.png", "res://art/town/animals/cat.png", "res://art/town/animals/duck.png"]
const BELL := "res://art/sfx/bus_bell.wav"
const BELL_STAND_IN := "res://art/sfx/harbour_swap.wav"
const SIZE := 58.0

## The town screen (game/screens/town.gd).
var screen: Node
var bus: Car
var active := false
## Who is on the bus: {picture, from (stop index)}.
var riding: Array[Dictionary] = []

var _pictures: Array[Texture2D] = []
## Per stop: the animals waiting there (Sprite2D), and seconds until the next one comes.
var _waiting: Array[Array] = []
var _refill: Array[float] = []
## The stop the doors were last opened at; they open again only after driving off.
var _served := -1
var _time := 0.0
var _voice: AudioStreamPlayer2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for path in ANIMALS:
		if ResourceLoader.exists(path):
			_pictures.append(load(path))
	var stops: Array[Dictionary] = screen.town.bus_stops
	for i in stops.size():
		_waiting.append([])
		_refill.append(_rng.randf_range(REFILL.x, REFILL.y))
		for k in _rng.randi_range(1, 2):
			_arrive(i)
	if SoundManager.audible():
		_voice = AudioStreamPlayer2D.new()
		_voice.bus = &"SFX"
		_voice.volume_db = -8.0
		_voice.max_distance = 2000.0
		add_child(_voice)


func start(school_bus: Car) -> void:
	bus = school_bus
	active = true
	_served = -1
	_show_riders()


## Parked back at the school: everyone gets off there.
func stop() -> void:
	if bus and not riding.is_empty():
		for rider in riding:
			_hop_off(rider["picture"], bus.global_position, bus.global_position + Vector2(0, -140))
		screen.pay(PAY * riding.size(), bus.global_position)
	riding.clear()
	active = false
	_show_riders()


func marks() -> Array:
	return []


func _physics_process(delta: float) -> void:
	_time += delta
	var stops: Array[Dictionary] = screen.town.bus_stops
	for i in stops.size():
		_refill[i] -= delta
		if _refill[i] <= 0.0:
			_refill[i] = _rng.randf_range(REFILL.x, REFILL.y)
			if _waiting[i].size() < MAX_WAITING:
				_arrive(i)
		for k in _waiting[i].size():
			var animal: Sprite2D = _waiting[i][k]
			animal.scale = Vector2.ONE * animal.get_meta(&"fit") * (1.0 + 0.05 * maxf(sin(_time * 4.0 + k * 1.7 + i), 0.0))
	if not active or bus == null:
		return
	var near := -1
	for i in stops.size():
		if bus.global_position.distance_to(stops[i]["stop"]) < STOP_REACH:
			near = i
	if near < 0:
		_served = -1
	elif near != _served and bus.velocity.length() < STOP_SPEED:
		_served = near
		_open_doors(near)


## At stop `i`: off first, then on.
func _open_doors(i: int) -> void:
	var stop: Dictionary = screen.town.bus_stops[i]
	var kerb: Vector2 = stop["kerb"]
	var leaving := riding.filter(func(rider: Dictionary) -> bool: return rider["from"] != i)
	for k in leaving.size():
		var rider: Dictionary = leaving[k]
		riding.erase(rider)
		var along: Vector2 = stop["along"]
		_hop_off(rider["picture"], bus.global_position, kerb + along * (k * 70.0 - 120.0) + stop["side"] * 20.0)
	if not leaving.is_empty():
		screen.pay(PAY * leaving.size(), kerb)
		TownFx.hearts(screen.get_node(^"World"), kerb, 4 + leaving.size())
	var boarding: Array = _waiting[i]
	while not boarding.is_empty() and riding.size() < MAX_RIDING:
		var animal: Sprite2D = boarding.pop_front()
		riding.append({"picture": animal.texture, "from": i})
		var tween := animal.create_tween()
		tween.tween_interval(0.15 * riding.size())
		tween.tween_property(animal, "global_position", bus.global_position, 0.35).set_trans(Tween.TRANS_QUAD)
		tween.parallel().tween_property(animal, "scale", Vector2.ZERO, 0.35)
		tween.tween_callback(animal.queue_free)
	if not leaving.is_empty() or riding.size() > 0:
		_ring()
	_show_riders()


## A new passenger walks up to stop `i` and waits, facing the road.
func _arrive(i: int) -> void:
	if _pictures.is_empty():
		return
	var stop: Dictionary = screen.town.bus_stops[i]
	var along: Vector2 = stop["along"]
	var side: Vector2 = stop["side"]
	var animal := Sprite2D.new()
	animal.texture = _pictures[_rng.randi() % _pictures.size()]
	var fit := SIZE / maxf(animal.texture.get_width(), animal.texture.get_height())
	animal.set_meta(&"fit", fit)
	animal.scale = Vector2.ONE * fit
	animal.rotation = (-side).angle()  # every animal picture faces +X: towards the road
	add_child(animal)
	var slot: int = _waiting[i].size()
	animal.global_position = stop["kerb"] + along * (slot * 66.0 - 66.0) + side * 10.0
	animal.modulate.a = 0.0
	animal.create_tween().tween_property(animal, "modulate:a", 1.0, 0.5)
	_waiting[i].append(animal)


## Someone gets off: hops from the bus to `to`, waits a moment, then walks off and fades.
func _hop_off(picture: Texture2D, from: Vector2, to: Vector2) -> void:
	var animal := Sprite2D.new()
	animal.texture = picture
	var fit := SIZE / maxf(picture.get_width(), picture.get_height())
	animal.scale = Vector2.ZERO
	add_child(animal)
	animal.global_position = from
	animal.rotation = (to - from).angle()
	var tween := animal.create_tween()
	tween.tween_property(animal, "global_position", to, 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(animal, "scale", Vector2.ONE * fit, 0.3)
	tween.tween_interval(1.2)
	tween.tween_property(animal, "global_position", to + (to - from).normalized() * 160.0, 1.2)
	tween.parallel().tween_property(animal, "modulate:a", 0.0, 1.2)
	tween.tween_callback(animal.queue_free)


func _show_riders() -> void:
	var pictures: Array[Texture2D] = []
	if active:
		for rider in riding:
			pictures.append(rider["picture"])
	screen.hud.show_passengers(pictures)


func _ring() -> void:
	var path := BELL if ResourceLoader.exists(BELL) else BELL_STAND_IN
	if _voice and ResourceLoader.exists(path):
		_voice.stream = load(path)
		_voice.global_position = bus.global_position
		_voice.play()

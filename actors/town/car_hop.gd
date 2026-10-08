class_name CarHop
extends Node
## A car's hop off one of Free Drive's jump ramps (docs/DESIGN.md §23). The ramp adds this to
## the car: a short boost, and for AIR_SECONDS the body is drawn bigger with its shadow
## dropping away below, then it lands with a thump. Only the picture leaves the ground; the
## car keeps driving and touching things as on the road, so a hop can never carry it over a
## wall or out to sea. Kickable cones and balls let a car in the air pass over them.

## As a boat's hop (Boat), a little longer: a car comes off the ramp slower.
const AIR_SECONDS := 0.75
const AIR_SCALE := 0.3
const SHADOW_OFFSET := Vector2(10, 14)
const WHOOSH := preload("res://art/sfx/ramp_whoosh.wav")
const THUMP := preload("res://art/sfx/wall_bump.wav")

var _time := 0.0
var _car: Car
var _body: Sprite2D
var _shadow: Sprite2D


## Throw `car` into the air, unless it is already up there.
static func launch(car: Car) -> void:
	if car.frozen or car.has_node(^"Hop"):
		return
	var hop := CarHop.new()
	hop.name = "Hop"
	car.add_child(hop)


static func airborne(car: Node) -> bool:
	return car.has_node(^"Hop")


func _ready() -> void:
	_car = get_parent()
	_body = _car.get_node(^"Body")
	_shadow = Sprite2D.new()
	_shadow.name = "HopShadow"
	_shadow.texture = _car.body_texture
	_shadow.modulate = Color(0, 0, 0, 0.3)
	_shadow.show_behind_parent = true
	_car.add_child(_shadow)
	_car.boost()
	_sound(WHOOSH, -4.0, 1.0)
	EventSystem.CAR_jumped.emit(_car)


func _physics_process(delta: float) -> void:
	_time += delta
	var t := minf(_time / AIR_SECONDS, 1.0)
	var hop := sin(PI * t)
	_body.scale = Vector2.ONE * (1.0 + AIR_SCALE * hop)
	_shadow.position = (SHADOW_OFFSET * (1.0 + 3.0 * hop)).rotated(-_car.rotation)
	_shadow.scale = Vector2.ONE * (1.0 - 0.15 * hop)
	if t >= 1.0:
		_body.scale = Vector2.ONE
		_shadow.queue_free()
		_sound(THUMP, -6.0, 0.8)
		EventSystem.CAR_landed.emit(_car)
		queue_free()


func _sound(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if not SoundManager.audible() or not _car.has_node(^"PlayerInput"):
		return
	var player := AudioStreamPlayer2D.new()
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = volume_db
	player.pitch_scale = pitch
	_car.get_parent().add_child(player)
	player.global_position = _car.global_position
	player.finished.connect(player.queue_free)
	player.play()

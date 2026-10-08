class_name Kickable
extends CharacterBody2D
## Something in Free Drive a car can knock about (docs/DESIGN.md §23): a ball that rolls and
## bounces, or a traffic cone that tumbles over and later stands up again where it was.
##
## Cars do not collide with it (it is on no physics layer), so a car never stops dead on a
## ball. Instead it looks every frame for a car touching it and is kicked away by it. It
## bounces off walls, posts and the shore. A car in the air off a ramp (CarHop) passes over.

signal kicked(thing: Kickable, by: Car)

enum Kind { BALL, CONE }

## How fast it slows down, per second: a ball rolls on, a cone skids to a stop.
const BALL_DRAG := 0.8
const CONE_DRAG := 2.6
## Of a car's speed into it, this much becomes the ball's; never less than MIN_KICK.
const KICK := 1.35
const MIN_KICK := 170.0
## Of its speed into a wall, this much comes back off it.
const BOUNCE := 0.7
## A cone knocked over stands up again this long after, once no car is near it.
const STAND_UP_AFTER := 15.0
const STAND_UP_CLEAR := 500.0
## A ball left lying further than `roam` from home this long goes back.
const RETURN_AFTER := 8.0
const SHADOW_OFFSET := Vector2(6, 8)
const BUMP := preload("res://art/sfx/wall_bump.wav")

var kind := Kind.BALL
var picture: Texture2D
## Its size on screen, px across.
var size := 80.0
## Where it starts, and where a cone stands up again.
var home := Vector2.ZERO
var knocked := false
## For a ball: how far it may roll off before it is put back home (0: it may go anywhere).
var roam := 0.0
var _away := 0.0

var _down_time := 0.0
var _spin := 0.0
var _sprite: Sprite2D
var _shadow: Sprite2D
var _voice: AudioStreamPlayer2D
var _quiet := 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = Car.LAYER_WORLD | Car.LAYER_SEA_EDGE
	motion_mode = MOTION_MODE_FLOATING
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = size * 0.4
	shape.shape = circle
	add_child(shape)
	var fit := size / maxf(picture.get_width(), picture.get_height())
	_shadow = Sprite2D.new()
	_shadow.texture = picture
	_shadow.scale = Vector2(fit, fit)
	_shadow.position = SHADOW_OFFSET
	_shadow.modulate = Color(0, 0, 0, 0.22)
	add_child(_shadow)
	_sprite = Sprite2D.new()
	_sprite.texture = picture
	_sprite.scale = Vector2(fit, fit)
	add_child(_sprite)
	if SoundManager.audible():
		_voice = AudioStreamPlayer2D.new()
		_voice.stream = BUMP
		_voice.bus = &"SFX"
		_voice.max_distance = 1400.0
		add_child(_voice)
	global_position = home


func _physics_process(delta: float) -> void:
	_quiet = maxf(_quiet - delta, 0.0)
	_touch_cars()
	if velocity.length_squared() > 1.0:
		var hit := move_and_collide(velocity * delta)
		if hit:
			velocity = velocity.bounce(hit.get_normal()) * BOUNCE
	velocity *= exp(-(BALL_DRAG if kind == Kind.BALL else CONE_DRAG) * delta)
	if velocity.length() < 6.0:
		velocity = Vector2.ZERO
	if kind == Kind.BALL:
		# Rolling: the picture turns with the distance covered.
		_sprite.rotation += velocity.length() * delta / (size * 0.5) * signf(velocity.x + 0.01)
		var lost := roam > 0.0 and velocity == Vector2.ZERO and global_position.distance_to(home) > roam
		_away = _away + delta if lost else 0.0
		if _away > RETURN_AFTER and _clear_of_cars():
			_away = 0.0
			stand_up()
	elif knocked:
		_spin *= exp(-2.0 * delta)
		_sprite.rotation += _spin * delta
		_shadow.rotation = _sprite.rotation
		_down_time += delta
		if _down_time > STAND_UP_AFTER and velocity == Vector2.ZERO and _clear_of_cars():
			stand_up()


## Back where it started: a ball put back on its spot, a cone stood up again, popping in.
func stand_up() -> void:
	knocked = false
	_down_time = 0.0
	velocity = Vector2.ZERO
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.25)
	tween.tween_callback(func() -> void:
		global_position = home
		reset_physics_interpolation()
		_sprite.rotation = 0.0
		_shadow.rotation = 0.0
		_sprite.scale.y = _sprite.scale.x
		_shadow.scale.y = _shadow.scale.x
		scale = Vector2(0.4, 0.4))
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	tween.parallel().tween_property(self, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## Any car whose body touches it kicks it away from that car.
func _touch_cars() -> void:
	var radius := size * 0.45
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		if car.frozen or not car.visible or CarHop.airborne(car):
			continue
		if car.global_position.distance_squared_to(global_position) > 250.0 * 250.0:
			continue
		var collision := car.get_node_or_null(^"Collision") as CollisionShape2D
		if collision == null or not collision.shape is RectangleShape2D:
			continue
		var half: Vector2 = collision.shape.size / 2.0
		var local := car.to_local(global_position)
		var closest := local.clamp(-half, half)
		var gap := local - closest
		var distance := gap.length()
		if distance >= radius:
			continue
		var normal_local := gap / distance if distance > 0.01 else (local.normalized() if local.length() > 0.01 else Vector2.RIGHT)
		var normal := normal_local.rotated(car.global_rotation)
		move_and_collide(normal * (radius - distance))
		var closing := (car.velocity - velocity).dot(normal)
		if closing <= 0.0:
			continue
		if kind == Kind.BALL:
			velocity += normal * maxf(closing * KICK, MIN_KICK)
		else:
			velocity = normal * maxf(closing * 0.9, 140.0) + car.velocity * 0.3
			if not knocked:
				_knock_over()
		_bump(closing)
		kicked.emit(self, car)


func _knock_over() -> void:
	knocked = true
	_down_time = 0.0
	_spin = randf_range(6.0, 12.0) * (1.0 if randf() < 0.5 else -1.0)
	# Lying on its side: longer one way than the other.
	_sprite.scale.y = _sprite.scale.x * 0.7
	_shadow.scale.y = _shadow.scale.x * 0.7


func _bump(speed: float) -> void:
	if _voice == null or _quiet > 0.0 or speed < 80.0:
		return
	_quiet = 0.25
	_voice.pitch_scale = (1.5 if kind == Kind.BALL else 1.9) * randf_range(0.92, 1.08)
	_voice.volume_db = -10.0 + clampf(speed / 600.0, 0.0, 1.0) * 6.0
	_voice.play()


func _clear_of_cars() -> bool:
	for car: Node2D in get_tree().get_nodes_in_group(&"cars"):
		if car.visible and car.global_position.distance_to(global_position) < STAND_UP_CLEAR:
			return false
	return true

class_name TownCoin
extends Area2D
## A coin lying in Free Drive's streets (docs/DESIGN.md §19). It bobs and spins; the player's
## car drives through it to pick it up (`collected`), and the screen puts it somewhere new
## a while later.

signal collected(coin: TownCoin)

const PICTURE := preload("res://art/ui/coin.png")
const SIZE := 60.0

var _sprite: Sprite2D
var _time := 0.0


func _ready() -> void:
	_time = randf() * TAU
	collision_layer = 0
	collision_mask = Car.LAYER_CARS_GROUND
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 44.0
	shape.shape = circle
	add_child(shape)
	_sprite = Sprite2D.new()
	_sprite.texture = PICTURE
	_sprite.scale = Vector2.ONE * SIZE / PICTURE.get_width()
	add_child(_sprite)
	body_entered.connect(func(body: Node2D) -> void:
		if visible and body is Car and body.has_node(^"PlayerInput"):
			collected.emit(self))


func _process(delta: float) -> void:
	_time += delta
	var s := SIZE / PICTURE.get_width()
	_sprite.scale = Vector2(s * absf(cos(_time * 2.2)) + s * 0.08, s)
	_sprite.position.y = sin(_time * 3.0) * 5.0


## Gone with a pop, until moved and shown again.
func pop() -> void:
	set_deferred(&"monitoring", false)
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.6, 1.6), 0.12)
	tween.parallel().tween_property(self, "modulate:a", 0.0, 0.18)
	tween.tween_callback(func() -> void: visible = false)


func reappear(at: Vector2) -> void:
	position = at
	scale = Vector2.ONE
	modulate.a = 1.0
	visible = true
	monitoring = true

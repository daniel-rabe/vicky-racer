class_name GhostCar
extends Sprite2D
## A recorded lap driven again as a see-through car (docs/DESIGN.md §16). It sets off each
## time the player crosses the line (`start`) and drives the lap exactly as recorded — one
## sample per physics tick, so at the recording's tick rate it is where the car was to the
## pixel — then fades away at the line. It touches nothing: no body, no collisions.
##
## Placed in _physics_process, so physics interpolation smooths it like a real car. Drawn at
## the car's own layer (above a bridge deck while on it) but before the cars in the tree, so a
## real car always covers it.

const FADE_SECONDS := 0.4

var ghost: GhostLap:
	set(value):
		ghost = value
		if ghost:
			texture = Paint.body(load("res://game/configs/setups/%s.tres" % ghost.setup_id), ghost.paint) \
				if ResourceLoader.exists("res://game/configs/setups/%s.tres" % ghost.setup_id) else texture
## The ghost's colour: see-through white for the player's own best, gold for the developer's.
var tint := Color(1, 1, 1, 0.45)
## Physics ticks since this lap started.
var tick := 0
var running := false


func _ready() -> void:
	modulate = tint
	visible = false


func start() -> void:
	if ghost == null:
		return
	tick = 0
	running = true
	visible = true
	modulate = tint
	_place()
	reset_physics_interpolation()


func _physics_process(_delta: float) -> void:
	if not running:
		return
	tick += 1
	if tick > ghost.frame_count():
		running = false
		create_tween().tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
		return
	_place()


func _place() -> void:
	if ghost.ticks_per_second == Engine.physics_ticks_per_second:
		# Same tick rate as the recording: exactly the recorded sample.
		var i := maxi(tick - 1, 0)
		global_position = ghost.position_at_frame(i)
		global_rotation = ghost.rotation_at_frame(i)
		z_index = ghost.layer_at_frame(i)
	else:
		var seconds := float(tick) / Engine.physics_ticks_per_second
		var at := ghost.transform_at(seconds)
		global_position = at.origin
		global_rotation = at.get_rotation()
		z_index = ghost.layer_at_frame(roundi(seconds * ghost.ticks_per_second) - 1)

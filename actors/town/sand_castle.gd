class_name SandCastle
extends Node2D
## A sandcastle on Sunny Beach (docs/DESIGN.md §37), seen from above: a moat round it, four
## round towers and a keep in the middle with a little flag. A car (or Vicky on foot) running
## into it knocks it flat in a puff of sand; it builds itself up again a while later, once
## nobody is near. Not solid: it never stops a car.

signal knocked(castle: SandCastle, by: Car)

const SAND := Color(0.9, 0.7, 0.4)
const SAND_DARK := Color(0.66, 0.46, 0.24)
const MOAT := Color(0.45, 0.75, 0.92)
const RADIUS := 80.0
## Slower than this, a car just stops beside it.
const KNOCK_SPEED := 50.0
const REBUILD_AFTER := 20.0
const REBUILD_CLEAR := 450.0

var flag := Color(0.92, 0.25, 0.3)
var flat := false
var _since := 0.0
var _puff: CPUParticles2D


func _ready() -> void:
	_puff = CPUParticles2D.new()
	_puff.emitting = false
	_puff.one_shot = true
	_puff.explosiveness = 1.0
	_puff.amount = 36
	_puff.lifetime = 0.9
	_puff.spread = 180.0
	_puff.gravity = Vector2.ZERO
	_puff.initial_velocity_min = 120.0
	_puff.initial_velocity_max = 300.0
	_puff.damping_min = 250.0
	_puff.damping_max = 350.0
	_puff.scale_amount_min = 8.0
	_puff.scale_amount_max = 16.0
	_puff.color = SAND_DARK
	_puff.z_index = 2
	add_child(_puff)


func _physics_process(delta: float) -> void:
	if flat:
		_since += delta
		if _since > REBUILD_AFTER and not _anyone_within(REBUILD_CLEAR):
			flat = false
			queue_redraw()
		return
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		if CarHop.airborne(car):
			continue
		if car.global_position.distance_to(global_position) < RADIUS + 30.0 and car.velocity.length() > KNOCK_SPEED:
			knock(car)
			return


func knock(by: Car) -> void:
	flat = true
	_since = 0.0
	_puff.restart()
	queue_redraw()
	knocked.emit(self, by)


func _anyone_within(reach: float) -> bool:
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		if car.global_position.distance_to(global_position) < reach:
			return true
	return false


func _draw() -> void:
	draw_arc(Vector2.ZERO, RADIUS + 14.0, 0.0, TAU, 40, MOAT, 16.0)
	if flat:
		# A lumpy heap, and the flag lying in it.
		for k in 6:
			var at := Vector2.from_angle(k * TAU / 6.0 + 0.4) * 34.0
			draw_circle(at + Vector2(5, 7), 34.0, Color(0, 0, 0, 0.12))
			draw_circle(at, 34.0, SAND_DARK.lerp(SAND, 0.4 + 0.1 * (k % 3)))
		draw_line(Vector2(-10, 20), Vector2(40, 2), Color(0.4, 0.3, 0.2), 4.0)
		draw_colored_polygon(PackedVector2Array([Vector2(40, 2), Vector2(58, -14), Vector2(64, 6)]), flag)
		return
	var wall := 54.0
	draw_rect(Rect2(Vector2(-wall, -wall) + Vector2(10, 14), Vector2(wall, wall) * 2.0), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(-wall, -wall, wall * 2.0, wall * 2.0), SAND_DARK)
	draw_rect(Rect2(-wall + 8.0, -wall + 8.0, wall * 2.0 - 16.0, wall * 2.0 - 16.0), SAND)
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		_tower(corner * wall, 32.0)
	_tower(Vector2.ZERO, 38.0)
	draw_line(Vector2(0, 0), Vector2(0, -58), Color(0.4, 0.3, 0.2), 5.0)
	draw_colored_polygon(PackedVector2Array([Vector2(0, -58), Vector2(36, -47), Vector2(0, -36)]), flag)


## A round tower from above: a ring of battlements round a flat top.
func _tower(at: Vector2, radius: float) -> void:
	draw_circle(at + Vector2(7, 10), radius, Color(0, 0, 0, 0.22))
	draw_circle(at, radius, SAND_DARK)
	draw_circle(at, radius - 7.0, SAND.lightened(0.18))
	for k in 8:
		draw_circle(at + Vector2.from_angle(k * TAU / 8.0) * (radius - 4.0), 5.0, SAND)

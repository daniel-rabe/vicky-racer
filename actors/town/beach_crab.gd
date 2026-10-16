class_name BeachCrab
extends Node2D
## A crab on Sunny Beach (docs/DESIGN.md §37), seen from above: it shuffles sideways to and fro
## by its spot. When a car (or Vicky on foot) comes near it scuttles away fast, digs into the
## sand so only its eyes poke out, and once nobody is near walks back home.

enum State { WALK, FLEE, HIDDEN, BACK }

const SHELL := Color(0.93, 0.36, 0.25)
const NOTICE := 300.0
const WALK_SPEED := 70.0
const FLEE_SPEED := 460.0
const FLEE_FOR := 0.8
const HIDE_FOR := 5.0
const WANDER := 90.0

var home := Vector2.ZERO
var state := State.WALK
## How many times it has run off, for the tests.
var scared := 0
var _time := 0.0
var _left := 0.0
var _way := Vector2.RIGHT


func _ready() -> void:
	_time = fmod(home.x * 0.37 + home.y * 0.11, TAU)
	position = home


func _physics_process(delta: float) -> void:
	_time += delta
	match state:
		State.WALK:
			position = home + Vector2(sin(_time * 0.8) * WANDER, 0.0)
			var near := _nearest()
			if near:
				_way = (global_position - near.global_position).normalized()
				state = State.FLEE
				rotation = _way.angle()  # sideways, as crabs go
				_left = FLEE_FOR
				scared += 1
		State.FLEE:
			var next := position + _way * FLEE_SPEED * delta
			_left -= delta
			if BeachIsland.contains(next) and not BeachIsland.on_walk(next):
				position = next
			else:
				_left = 0.0
			if _left <= 0.0:
				state = State.HIDDEN
				_left = HIDE_FOR
		State.HIDDEN:
			_left -= delta
			if _left <= 0.0 and _nearest() == null:
				state = State.BACK
		State.BACK:
			var to := home - position
			if to.length() < 8.0:
				state = State.WALK
				rotation = 0.0
				_time = 0.0
			else:
				rotation = to.angle()
				position += to.limit_length(WALK_SPEED * 2.0 * delta)
	queue_redraw()


func _nearest() -> Car:
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		if car.global_position.distance_to(global_position) < NOTICE:
			return car
	return null


func _draw() -> void:
	if state == State.HIDDEN:
		draw_circle(Vector2(0, 4), 22.0, Color(0.82, 0.68, 0.42))
		for x in [-9.0, 9.0]:
			draw_circle(Vector2(x, -4), 6.0, Color.WHITE)
			draw_circle(Vector2(x, -4), 3.0, Color.BLACK)
		return
	var step := sin(_time * (22.0 if state == State.FLEE else 9.0))
	_draw_body(Vector2(5, 8), Color(0, 0, 0, 0.18), Color(0, 0, 0, 0.0), 0.0)
	_draw_body(Vector2.ZERO, SHELL, SHELL.darkened(0.3), step)
	draw_set_transform(Vector2.ZERO)


## The crab facing up the screen, `offset` away: legs and claws (none for its shadow), its round
## shell, and its eyes on stalks.
func _draw_body(offset: Vector2, shell: Color, legs: Color, step: float) -> void:
	draw_set_transform(offset)
	if legs.a > 0.0:
		for side in [-1.0, 1.0]:
			for k in 3:
				var from := Vector2(side * 18.0, -4.0 + k * 9.0)
				var to := from + Vector2(side * 16.0, 6.0 + (step if k % 2 else -step) * 5.0)
				draw_line(from, to, legs, 4.0)
			draw_line(Vector2(side * 14.0, -12.0), Vector2(side * 24.0, -26.0), legs, 5.0)
			draw_circle(Vector2(side * 26.0, -30.0), 10.0, shell)
			draw_line(Vector2(side * 26.0, -30.0), Vector2(side * 22.0, -40.0), legs, 3.0)
	draw_set_transform(offset + Vector2(0, 8), 0.0, Vector2(1.0, 0.75))
	draw_circle(Vector2.ZERO, 24.0, shell)
	draw_set_transform(offset)
	if legs.a > 0.0:
		for x in [-8.0, 8.0]:
			draw_line(Vector2(x, -10), Vector2(x, -18), legs, 3.0)
			draw_circle(Vector2(x, -19), 5.5, Color.WHITE)
			draw_circle(Vector2(x, -19), 2.8, Color.BLACK)

class_name SkidMarks
extends Node2D
## Tyre marks left on the ground while a car drifts: the visible payoff for buying a
## slippery setup (docs/DESIGN.md §4). Listens to CAR_drift_started / CAR_drift_ended for
## every car, so one SkidMarks node serves the whole race. It sits above the track and
## below the cars in the scene tree, so marks lie on the road and under every car.
##
## Each drift lays two lines, one per rear wheel. Finished marks fade out after a while
## and the oldest are dropped past MAX_MARKS, so a long race never piles up lines.

## Rear wheel centres in the car's own frame (the sprite is 128 x 72, facing +X).
const REAR_WHEELS: Array[Vector2] = [Vector2(-36.0, -26.0), Vector2(-36.0, 26.0)]
const WIDTH := 13.0
const COLOUR := Color(0.11, 0.11, 0.13, 0.4)
## A new point is laid once the wheel has moved this far, px.
const MIN_STEP := 10.0
const FADE_AFTER := 6.0
const FADE_TIME := 2.0
## Lines kept at most (two per drift); the oldest finished ones go first.
const MAX_MARKS := 80

var _active := {}  # Car -> Array[Line2D], one per rear wheel


func _enter_tree() -> void:
	EventSystem.CAR_drift_started.connect(_on_drift_started)
	EventSystem.CAR_drift_ended.connect(_on_drift_ended)


func _on_drift_started(car: Node) -> void:
	var lines: Array[Line2D] = []
	for wheel in REAR_WHEELS:
		var line := Line2D.new()
		line.width = WIDTH
		line.default_color = COLOUR
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.antialiased = true
		add_child(line)
		lines.append(line)
	_active[car] = lines
	_drop_oldest()


func _on_drift_ended(car: Node, _duration: float) -> void:
	var lines: Array = _active.get(car, [])
	_active.erase(car)
	for line: Line2D in lines:
		var tween := line.create_tween()
		tween.tween_interval(FADE_AFTER)
		tween.tween_property(line, "modulate:a", 0.0, FADE_TIME)
		tween.tween_callback(line.queue_free)


func _physics_process(_delta: float) -> void:
	for car: Node2D in _active.keys():
		if not is_instance_valid(car):
			_active.erase(car)
			continue
		var lines: Array = _active[car]
		for i in REAR_WHEELS.size():
			var line: Line2D = lines[i]
			var point := to_local(car.to_global(REAR_WHEELS[i]))
			var count := line.get_point_count()
			if count == 0 or line.get_point_position(count - 1).distance_to(point) >= MIN_STEP:
				line.add_point(point)


## Free the oldest finished marks once there are too many. Children are in creation order.
func _drop_oldest() -> void:
	var drawing := {}
	for lines: Array in _active.values():
		for line in lines:
			drawing[line] = true
	var excess := get_child_count() - MAX_MARKS
	for child in get_children():
		if excess <= 0:
			break
		if not drawing.has(child) and not child.is_queued_for_deletion():
			child.queue_free()
			excess -= 1

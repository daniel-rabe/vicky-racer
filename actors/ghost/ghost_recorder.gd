class_name GhostRecorder
extends Node
## Records the player's laps in a time trial (docs/DESIGN.md §16): from each crossing of the
## line, the car's transform on every physics tick, until it crosses again. Keeps the best
## lap of the session as `best` and says so (`new_best`), so the ghost on the track can become
## the lap just driven.

signal new_best(ghost: GhostLap)

var car: Car
var track_id: StringName
var setup_id: StringName
var paint: StringName = Paint.ORIGINAL
var best: GhostLap
var _current: GhostLap


func _ready() -> void:
	# After the cars have moved this tick, so a sample is where the car is drawn.
	process_physics_priority = 100


func start_lap() -> void:
	_current = GhostLap.new()
	_current.track_id = track_id
	_current.setup_id = setup_id
	_current.paint = paint
	_current.ticks_per_second = Engine.physics_ticks_per_second


## The lap just recorded is over, `lap_time` long: keep it if it is the session's best.
func finish_lap(lap_time: float) -> void:
	if _current == null or _current.frame_count() == 0:
		return
	_current.lap_time = lap_time
	if best == null or lap_time < best.lap_time:
		best = _current
		new_best.emit(best)
	_current = null


func _physics_process(_delta: float) -> void:
	if _current != null and is_instance_valid(car):
		_current.add(car.global_transform, car.z_index)

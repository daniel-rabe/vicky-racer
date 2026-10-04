class_name AIDriver
extends Node
## Drives its parent Car round the track by writing the same three inputs a player would
## (docs/DESIGN.md §8). Deliberately simple: follow the racing line in its own lane, slow
## for the sharpest bend coming up, steer round a car in front. Rubber-banding from the
## RaceManager scales its pace. If it gets stuck it backs out, and as a last resort it is
## put back on the line — a stranded opponent would only puzzle a child.

## 0 = gentle, 1 = sharp: sets its pace on straights and through bends.
@export_range(0.0, 1.0) var skill := 0.7
## Its lane: px to the side of the racing line, so the pack does not drive in single file.
@export var line_offset := 0.0

## Set by the RaceManager: < 1 eases off when far ahead of the player, > 1 pushes when behind.
var rubber_band := 1.0
## Pace from the base car's top speed rather than this car's own. Opponents do: which car
## an opponent drives changes how it handles and looks, not how fast the race is, so a
## Banana-driving opponent cannot run away from a child in the Ice-Cream Van. The player's
## autopilot (balance tests) paces from its own car, so each car's speed still shows.
var pace_from_base := false
var track: Track
## How often this car had to be put back on the line; the race test expects 0.
var rescues := 0

const LOOKAHEAD_MIN := 150.0
## Extra lookahead per px/s of speed: further ahead when fast, so steering stays calm.
const LOOKAHEAD_PER_SPEED := 0.3
## Being this far off the line to the target, in radians, means full lock.
const STEER_FULL_ANGLE := 0.45
## Distances ahead where the road's bend is sampled to choose a speed.
const BEND_SAMPLES: Array[float] = [250.0, 500.0, 800.0]
## A bend of this many radians within those samples means slowing right down.
const SHARP_BEND := 1.6
const AVOID_RANGE := 260.0
const AVOID_SHIFT := 120.0
const STUCK_SPEED := 40.0
const STUCK_SECONDS := 1.2
const REVERSE_SECONDS := 0.9
## After this many back-outs without getting going again, the car is put back on the line.
const BACK_OUTS_BEFORE_RESCUE := 3
const RESCUE_DISTANCE := 900.0

var _offset := 0.0
var _avoid := 0.0
var _stuck_time := 0.0
var _reverse_time := 0.0
var _reverse_steer := 0.0
var _back_outs := 0

@onready var car: Car = get_parent()


func _ready() -> void:
	process_physics_priority = -1  # write inputs before the car moves this frame
	_offset = line_offset


func _physics_process(delta: float) -> void:
	if track == null or car.frozen:
		return
	var speed := car.velocity.length()
	if _handle_stuck(speed, delta):
		return
	var length := track.lap_length()
	var here := track.progress_of(car)
	_update_lane(delta)

	# Steer at a point ahead on the line, shifted sideways into our lane.
	var ahead := fposmod(here + LOOKAHEAD_MIN + speed * LOOKAHEAD_PER_SPEED, length)
	var to_target := _line_point(ahead, _offset) - car.global_position
	var angle := Vector2.RIGHT.rotated(car.rotation).angle_to(to_target)
	car.steer_input = clampf(angle / STEER_FULL_ANGLE, -1.0, 1.0)

	# Speed: slow for the sharpest bend in the stretch ahead.
	var heading := _tangent(here)
	var bend := 0.0
	for d in BEND_SAMPLES:
		bend = maxf(bend, absf(heading.angle_to(_tangent(fposmod(here + d, length)))))
	# Corner speed depends on how quickly the car turns, not on its top speed: a sharp-
	# steering setup (Kart) carries more speed through a bend, a lazy one (Rocket) lifts more.
	var pace_speed := car.base_config.max_speed if pace_from_base else car.config.max_speed
	var straight_speed := minf((0.80 + 0.15 * skill) * pace_speed, car.config.max_speed)
	var turn_factor := car.config.max_steer_rate / car.base_config.max_steer_rate
	var corner_speed := minf((0.45 + 0.15 * skill) * car.base_config.max_speed * turn_factor, straight_speed)
	var bend_fraction := clampf(bend / SHARP_BEND, 0.0, 1.0)
	var top := car.config.max_speed * maxf(rubber_band, 1.0)
	car.catch_up_mult = maxf(rubber_band, 1.0)
	var target_speed := clampf(lerpf(straight_speed, corner_speed, bend_fraction) * rubber_band,
		0.3 * car.config.max_speed, top) * car.surface_speed()
	if speed < target_speed - 30.0:
		car.throttle_input = 1.0
	elif speed > target_speed + 60.0:
		car.throttle_input = -clampf((speed - target_speed) / 300.0, 0.2, 1.0)
	else:
		car.throttle_input = 0.3
	car.handbrake = false


## Drift into another lane while a car is close in front, then ease back into our own.
func _update_lane(delta: float) -> void:
	var forward := Vector2.RIGHT.rotated(car.rotation)
	var right := forward.orthogonal()
	var blocked := false
	for other: Car in get_tree().get_nodes_in_group(&"cars"):
		if other == car or other.level != car.level:
			continue  # a car on the other level (over or under a bridge) is not in the way
		var rel := other.global_position - car.global_position
		var along := rel.dot(forward)
		var side := rel.dot(right)
		if along > 0.0 and along < AVOID_RANGE and absf(side) < 90.0:
			_avoid = -signf(side if side != 0.0 else 1.0) * AVOID_SHIFT
			blocked = true
	if not blocked:
		_avoid = move_toward(_avoid, 0.0, 120.0 * delta)
	var limit := track.road_half_width - 70.0
	_offset = move_toward(_offset, clampf(line_offset + _avoid, -limit, limit), 200.0 * delta)


## True while handling a stuck car (backing out or being rescued); the caller then skips
## normal driving this frame.
func _handle_stuck(speed: float, delta: float) -> bool:
	if _reverse_time > 0.0:
		_reverse_time -= delta
		car.throttle_input = -1.0
		car.steer_input = _reverse_steer
		return true
	if speed > 200.0:
		_back_outs = 0
	if speed < STUCK_SPEED and car.throttle_input > 0.5:
		_stuck_time += delta
	else:
		_stuck_time = 0.0
	if track.distance_of(car) > RESCUE_DISTANCE:
		_rescue()
		return true
	if _stuck_time > STUCK_SECONDS:
		_stuck_time = 0.0
		_back_outs += 1
		if _back_outs > BACK_OUTS_BEFORE_RESCUE:
			_rescue()
			return true
		# Reversing turns the nose the other way, so steer opposite to where we were heading.
		_reverse_steer = -signf(car.steer_input) if car.steer_input != 0.0 else 1.0
		_reverse_time = REVERSE_SECONDS
		return true
	return false


## Put the car back on the racing line, facing along it.
func _rescue() -> void:
	var here := track.progress_of(car)
	car.global_position = _line_point(here, _offset)
	car.rotation = _tangent(here).angle()
	car.velocity = Vector2.ZERO
	car.reset_physics_interpolation()
	rescues += 1
	_stuck_time = 0.0
	_reverse_time = 0.0
	_back_outs = 0


func _line_point(offset: float, sideways: float) -> Vector2:
	return track.line_point(offset, sideways)


func _tangent(offset: float) -> Vector2:
	return track.line_tangent(offset)

class_name RouteDriver
extends Node
## Drives its parent Car along a street race's route through the town (StreetRace, docs/DESIGN.md
## §30): a line of points round the streets, followed with a look ahead, slowing for the corners.
## Like AIDriver on a track, but the town has no Track, only this line. It keeps `lane` px to
## one side of the line, so the racers spread across the road, and goes a little easier when far
## ahead of the player and a little harder when far behind, so a race stays a race.

const LOOKAHEAD := 170.0
const LOOKAHEAD_PER_SPEED := 0.35
const STEER_FULL_ANGLE := 0.45
## A right-angle corner this far ahead brings the speed down to CORNER_SPEED of the top speed.
const CORNER_LOOK := 520.0
const CORNER_SPEED := 0.42
## Further than this ahead of the player it eases off; further behind, it pushes.
const EASE_AHEAD := 900.0
const PUSH_BEHIND := 1400.0

## The route: points along it, and the distance along it at each point.
var points := PackedVector2Array()
var lengths := PackedFloat32Array()
var lane := 0.0
## How good a driver: a share of the car's top speed.
var skill := 0.92
## How far along the route it is, px; the player's, written by the race each frame.
var progress := 0.0
var player_progress := 0.0
var finished := false

@onready var car: Car = get_parent()


func _ready() -> void:
	process_physics_priority = -1  # write the inputs before the car moves


func total() -> float:
	return lengths[lengths.size() - 1] if not lengths.is_empty() else 0.0


func _physics_process(_delta: float) -> void:
	if points.size() < 2 or car.frozen:
		return
	progress = _nearest_progress(car.global_position, progress)
	if progress >= total() - 30.0:
		finished = true
	if finished:
		car.throttle_input = -0.6 if car.forward_speed() > 30.0 else 0.0
		car.steer_input = 0.0
		return
	var ahead := LOOKAHEAD + car.velocity.length() * LOOKAHEAD_PER_SPEED
	var target := point_at(progress + ahead, lane)
	var angle := Vector2.RIGHT.rotated(car.rotation).angle_to(target - car.global_position)
	car.steer_input = clampf(angle / STEER_FULL_ANGLE, -1.0, 1.0)
	var top := car.config.max_speed * car.surface_speed() * skill * _corner_factor()
	var gap := progress - player_progress
	if gap > EASE_AHEAD:
		top *= 0.82
	car.catch_up_mult = 1.12 if gap < -PUSH_BEHIND else 1.0
	var speed := car.forward_speed()
	car.throttle_input = 1.0 if speed < top else (-0.5 if speed > top + 120.0 else 0.0)
	car.handbrake = false


## How hard the turn coming up is: 1 on a straight, CORNER_SPEED at a right angle.
func _corner_factor() -> float:
	var here := direction_at(progress + 60.0)
	var later := direction_at(progress + CORNER_LOOK)
	var turn := absf(here.angle_to(later))
	return lerpf(1.0, CORNER_SPEED, clampf(turn / (PI / 2.0), 0.0, 1.0))


## The point `distance` along the route, `side` px to its right.
func point_at(distance: float, side := 0.0) -> Vector2:
	distance = clampf(distance, 0.0, total())
	var i := lengths.bsearch(distance)
	i = clampi(i, 1, points.size() - 1)
	var a := points[i - 1]
	var b := points[i]
	var span := maxf(lengths[i] - lengths[i - 1], 0.001)
	var t := clampf((distance - lengths[i - 1]) / span, 0.0, 1.0)
	var along := (b - a).normalized()
	return a.lerp(b, t) + along.orthogonal() * -side


func direction_at(distance: float) -> Vector2:
	return (point_at(distance + 20.0) - point_at(distance - 20.0)).normalized()


## How far along the route `at` is, searching a little behind and ahead of `near`.
func _nearest_progress(at: Vector2, near: float) -> float:
	return StreetRace.progress_on(points, lengths, at, near)

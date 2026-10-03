class_name Car
extends CharacterBody2D
## One racing car. It knows nothing about who drives it: a driver child (PlayerInput or
## AIDriver) writes the three inputs below every physics frame. Handling follows
## docs/DESIGN.md §4 — steering rotates the car directly, so it cannot spin out, and
## separate forward/sideways grip is what makes it drift.

## Below this forward speed, holding brake switches to reverse.
const REVERSE_SWITCH_SPEED := 40.0
## How hard the car slows when it is over its speed limit (e.g. after driving onto grass
## at full speed). Gradual on purpose: grass slows you, it never stops you dead.
const OVERSPEED_DECEL := 1500.0

@export var base_config: CarConfig
@export var setup: DriftSetup:
	set(value):
		setup = value
		_resolve_config()
		# A setup changes how the car looks as well as how it drives (its garage card's car).
		if value and value.body:
			body_texture = value.body
@export var body_texture: Texture2D:
	set(value):
		body_texture = value
		if is_node_ready():
			$Body.texture = value

# Written by the driver every physics frame.
var steer_input := 0.0      ## -1 (left) .. 1 (right)
var throttle_input := 0.0   ## -1 (brake / reverse) .. 1 (full throttle)
var handbrake := false

# Written by the track (Phase 6): multipliers for the surface under the car.
var surface_speed_mult := 1.0
var surface_grip_mult := 1.0

## Written by an AI driver while rubber-banded forward: lets an opponent go a little past
## its top speed, so it can keep a player on a faster setup in sight.
var catch_up_mult := 1.0

## Held still, ignoring its driver: during the countdown, and after the race.
var frozen := false

## The handling actually in use: base_config with the setup's multipliers applied.
var config: CarConfig
var is_drifting := false
var lateral_speed := 0.0

var _drift_time := 0.0
var _touching_wall := false


func _ready() -> void:
	add_to_group(&"cars")  # the track updates the surface multipliers of every car in it
	motion_mode = MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	if body_texture:
		$Body.texture = body_texture
	_resolve_config()


func _resolve_config() -> void:
	if base_config:
		config = base_config.with_setup(setup)


func forward_speed() -> float:
	return velocity.dot(Vector2.RIGHT.rotated(rotation))


func _physics_process(delta: float) -> void:
	if frozen:
		velocity = Vector2.ZERO
		return
	var speed_along := forward_speed()
	_steer(speed_along, delta)
	var forward := Vector2.RIGHT.rotated(rotation)
	_apply_throttle(forward, speed_along, delta)
	_apply_grip(forward, delta)
	_limit_speed(speed_along, delta)
	_move_and_handle_walls()
	_update_drift(forward, delta)


func _steer(speed_along: float, delta: float) -> void:
	# Signed speed: reversing steers the natural way round, and at a standstill there is
	# no steering at all, so the car cannot pirouette on the spot.
	var authority := clampf(speed_along / config.steer_speed_ref, -1.0, 1.0)
	rotation += steer_input * config.max_steer_rate * authority * delta


func _apply_throttle(forward: Vector2, speed_along: float, delta: float) -> void:
	var accel := 0.0
	if throttle_input > 0.0:
		accel = throttle_input * config.engine_power
	elif throttle_input < 0.0:
		if speed_along > REVERSE_SWITCH_SPEED:
			accel = throttle_input * config.brake_power
		else:
			accel = throttle_input * config.engine_power * config.reverse_power_fraction
	velocity += forward * accel * delta


func _apply_grip(forward: Vector2, delta: float) -> void:
	# The drift model: forward and sideways motion decay at different rates. exp() is the
	# exact form of the per-frame damping, and can never overshoot into negative grip.
	var forward_part := forward * velocity.dot(forward)
	var sideways_part := velocity - forward_part
	var grip := (config.handbrake_lateral_grip if handbrake else config.lateral_grip) * surface_grip_mult
	velocity = forward_part * exp(-config.forward_drag * delta) + sideways_part * exp(-grip * delta)


func _limit_speed(speed_along: float, delta: float) -> void:
	var limit := config.max_speed * surface_speed_mult * catch_up_mult if speed_along >= 0.0 		else config.max_reverse_speed
	var speed := velocity.length()
	if speed > limit:
		velocity = velocity / speed * move_toward(speed, limit, OVERSPEED_DECEL * delta)


func _move_and_handle_walls() -> void:
	var before := velocity
	move_and_slide()
	# Only walls and props count. Cars touching cars is racing: physics already pushes them
	# apart, and treating each touch as a hit would scrub speed and shake the camera over
	# and over while two cars run side by side.
	var touching := false
	var impact := 0.0
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if not hit.get_collider() is Car:
			touching = true
			impact = maxf(impact, -before.dot(hit.get_normal()))
	if touching and not _touching_wall:
		# A fresh hit: scrub a little speed once. move_and_slide has already removed the
		# part heading into the wall, so the car slides along it instead of stopping.
		if impact > config.wall_hit_threshold:
			velocity *= 1.0 - config.wall_speed_scrub
			EventSystem.CAR_wall_hit.emit(self, impact)
	_touching_wall = touching


func _update_drift(forward: Vector2, delta: float) -> void:
	lateral_speed = absf(velocity.dot(forward.orthogonal()))
	var drifting_now := lateral_speed > config.drift_threshold
	if drifting_now and not is_drifting:
		_drift_time = 0.0
		EventSystem.CAR_drift_started.emit(self)
	elif is_drifting and not drifting_now:
		EventSystem.CAR_drift_ended.emit(self, _drift_time)
	is_drifting = drifting_now
	if is_drifting:
		_drift_time += delta

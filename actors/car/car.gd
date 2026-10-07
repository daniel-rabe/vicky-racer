class_name Car
extends CharacterBody2D
## One racing car. It knows nothing about who drives it: a driver child (PlayerInput or
## AIDriver) writes the three inputs below every physics frame. Handling follows
## docs/DESIGN.md §4 — steering rotates the car directly, so it cannot spin out, and
## separate forward/sideways grip is what makes it drift.

## Physics layers. The world (walls, props) is layer 1; cars on the ground and cars on a
## bridge are on separate layers, so the two levels pass through each other where a road
## crosses itself, and bridge railings stop only the cars up on the bridge.
const LAYER_WORLD := 1
const LAYER_CARS_GROUND := 2
const LAYER_CARS_BRIDGE := 4
const LAYER_RAILINGS := 8
## A boat in the air off a ramp (Boat): only the gates see it, so it sails over the others.
const LAYER_AIRBORNE := 16
## Free Drive's island (docs/DESIGN.md §21): the waterline is two walls on one line. Cars
## stop at the sea edge, boats at the land edge (the shore, the quay, the pier, the islets).
const LAYER_SEA_EDGE := 32
const LAYER_LAND_EDGE := 64
## Cars on a bridge draw above its deck (Track.DECK_Z).
const BRIDGE_Z := 2

## A boost pad: for this long the car may go BOOST_SPEED_MULT over its top speed and gets
## BOOST_PUSH px/s² of extra acceleration. Fades out over the last third.
const BOOST_SECONDS := 1.2
const BOOST_SPEED_MULT := 1.3
const BOOST_PUSH := 1800.0
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
			_update_rider()
## Who is at the wheel (DriverLook, docs/DESIGN.md §22): drawn in the seat DriverSeats gives
## the body. &"" seats nobody.
@export var driver_id: StringName:
	set(value):
		driver_id = value
		if is_node_ready():
			_update_rider()

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
## 0 on the ground, 1 on a bridge. Set by the track through set_level().
var level := 0

## The handling actually in use: base_config with the setup's multipliers applied.
var config: CarConfig
var is_drifting := false
var lateral_speed := 0.0

var _drift_time := 0.0
var _boost_time := 0.0
var _touching_wall := false


func _ready() -> void:
	add_to_group(&"cars")  # the track updates the surface multipliers of every car in it
	motion_mode = MOTION_MODE_FLOATING
	wall_min_slide_angle = 0.0
	if body_texture:
		$Body.texture = body_texture
	_resolve_config()
	set_level(0)
	_update_rider()


## The driver in the seat, rebuilt for the current body and driver.
func _update_rider() -> void:
	var body: Sprite2D = $Body
	var old := body.get_node_or_null(^"Driver")
	if old:
		body.remove_child(old)
		old.queue_free()
	var kind := setup.kind if setup else &"car"
	DriverRider.build(body, DriverLook.texture(driver_id, kind), self)


## Move between the ground and a bridge: what the car can touch, and (with the margin the
## track allows at the deck's ends) whether it is drawn above the deck.
func set_level(value: int) -> void:
	level = value
	set_drawn_above_deck(value == 1)
	collision_layer = LAYER_CARS_BRIDGE if value == 1 else LAYER_CARS_GROUND
	collision_mask = LAYER_WORLD | _edge_layer() | (LAYER_CARS_BRIDGE | LAYER_RAILINGS if value == 1 else LAYER_CARS_GROUND)


## The side of the waterline this vehicle keeps to: a car stays on the land.
func _edge_layer() -> int:
	return LAYER_SEA_EDGE


func _resolve_config() -> void:
	if base_config:
		config = base_config.with_setup(setup)


func set_drawn_above_deck(above: bool) -> void:
	z_index = BRIDGE_Z if above else 0


## Driven over a boost pad. Emits CAR_boosted (sound, effects).
func boost() -> void:
	if frozen:
		return
	_boost_time = BOOST_SECONDS
	EventSystem.CAR_boosted.emit(self)


## 0 normally, up to 1 during a boost.
func boost_strength() -> float:
	return clampf(_boost_time / (BOOST_SECONDS / 3.0), 0.0, 1.0)


func forward_speed() -> float:
	return velocity.dot(Vector2.RIGHT.rotated(rotation))


## The surface's speed limit for this car: grass and sand slow an off-road car (Monster
## Truck) less than a road car (CarConfig.offroad_penalty).
func surface_speed() -> float:
	return _offroad(surface_speed_mult)


func _offroad(mult: float) -> float:
	return maxf(1.0 - (1.0 - mult) * config.offroad_penalty, CarConfig.MIN_SURFACE_MULT)


func _physics_process(delta: float) -> void:
	if frozen:
		velocity = Vector2.ZERO
		return
	var speed_along := forward_speed()
	_steer(speed_along, delta)
	var forward := Vector2.RIGHT.rotated(rotation)
	_apply_throttle(forward, speed_along, delta)
	if _boost_time > 0.0:
		velocity += forward * BOOST_PUSH * boost_strength() * delta
		_boost_time -= delta
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
	var grip := (config.handbrake_lateral_grip if handbrake else config.lateral_grip) * _offroad(surface_grip_mult)
	velocity = forward_part * exp(-config.forward_drag * delta) + sideways_part * exp(-grip * delta)


func _limit_speed(speed_along: float, delta: float) -> void:
	var boosted := lerpf(1.0, BOOST_SPEED_MULT, boost_strength())
	var limit := config.max_speed * surface_speed() * catch_up_mult * boosted
	if speed_along < 0.0:
		limit = config.max_reverse_speed
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

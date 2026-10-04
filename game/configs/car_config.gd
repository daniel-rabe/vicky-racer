class_name CarConfig
extends Resource
## Base handling for a car. Every value is editable in the inspector, also while the
## game runs. Drift setups never replace these — they multiply them (see DriftSetup).

@export_group("Engine")
## Acceleration from full throttle, px/s².
@export var engine_power := 1400.0
## Deceleration from full brake, px/s².
@export var brake_power := 2200.0
## Reverse is a fraction of engine power, so backing out of a wall is gentle.
@export_range(0.0, 1.0) var reverse_power_fraction := 0.4
@export var max_speed := 1100.0
@export var max_reverse_speed := 300.0

@export_group("Steering")
## Turn rate at full lock once moving at steer_speed_ref or faster, rad/s.
@export var max_steer_rate := 3.2
## Below this speed steering authority fades out, so the car cannot spin on the spot.
@export var steer_speed_ref := 350.0

@export_group("Grip")
## How quickly forward speed bleeds away with no throttle, 1/s.
@export var forward_drag := 0.6
## How quickly sideways sliding is killed, 1/s. High = goes where it points.
@export var lateral_grip := 9.0
## Sideways grip while the handbrake is held. Low = the tail kicks out.
@export var handbrake_lateral_grip := 1.8
## Sideways speed above which the car counts as drifting (skid marks, signals).
@export var drift_threshold := 220.0

@export_group("Off road")
## How much grass and sand hold the car back: 1 = the surface slowdown and loss of grip in
## track.gd SURFACES, 0 = drives off road as if it were asphalt, up to 1.5 = worse than
## usual (the Formula). Never so bad that a surface stops a car (MIN_SURFACE_MULT).
@export_range(0.0, 1.5) var offroad_penalty := 1.0

@export_group("Walls")
## Fraction of speed lost on a solid wall hit; the slide along the wall is kept.
@export_range(0.0, 1.0) var wall_speed_scrub := 0.15
## Impacts slower than this (into the wall, px/s) are scrapes, not hits.
@export var wall_hit_threshold := 120.0

# Clamps from docs/DESIGN.md §4.2: no setup may make the car undrivable.
const MIN_LATERAL_GRIP := 3.0
const MAX_SPEED_CAP := 1500.0
## However bad a car is off road, grass and sand keep at least this much speed and grip.
const MIN_SURFACE_MULT := 0.25


## A copy of this config with a drift setup's multipliers applied and clamped.
func with_setup(setup: DriftSetup) -> CarConfig:
	var resolved: CarConfig = duplicate()
	if setup == null:
		return resolved
	resolved.lateral_grip = maxf(lateral_grip * setup.lateral_grip_mult, MIN_LATERAL_GRIP)
	resolved.handbrake_lateral_grip = handbrake_lateral_grip * setup.handbrake_grip_mult
	resolved.engine_power = engine_power * setup.engine_power_mult
	resolved.max_speed = minf(max_speed * setup.max_speed_mult, MAX_SPEED_CAP)
	resolved.max_steer_rate = max_steer_rate * setup.steer_rate_mult
	resolved.offroad_penalty = clampf(offroad_penalty * setup.offroad_mult, 0.0, 1.5)
	return resolved

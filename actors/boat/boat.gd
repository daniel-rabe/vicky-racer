class_name Boat
extends Car
## One racing boat (docs/DESIGN.md §20.1). A Car in every way the race, the AI, the HUD and
## the ghosts care about — the same driver contract, surfaces, boost, levels and signals —
## so they drive it unchanged. What makes it a boat is mostly numbers (base_boat.tres: it
## glides on when the throttle is let go and swings wide through bends), plus a few things a
## car does not do:
##   - it bounces softly off shores, buoys and logs instead of scrubbing speed against them;
##   - a current (written by the Track) carries it along;
##   - off a ramp it flies for AIR_SECONDS, sailing over the others, and splashes down;
##   - it bobs on the water.

## Air time off a ramp, s, and how much bigger the boat is drawn at the top of the hop.
const AIR_SECONDS := 0.6
const AIR_SCALE := 0.25
## Of the speed into a wall, this much comes back as a push away from it.
const BOUNCE := 0.45
## The bob: degrees of rock either way, and the dip in scale, at speed.
const BOB_DEGREES := 3.0
const BOB_DIP := 0.025
const SHADOW_OFFSET := Vector2(10, 14)

## Written by the Track every physics frame: the current here, px/s (zero when there is none).
var current := Vector2.ZERO
## Seconds left in the air; 0 on the water.
var air_time := 0.0

var _bob := 0.0

@onready var _body: Sprite2D = $Body
@onready var _shadow: Sprite2D = $Shadow


func is_airborne() -> bool:
	return air_time > 0.0


## Off a ramp (the Track calls this): a short hop with a little boost.
func jump() -> void:
	if frozen or is_airborne():
		return
	air_time = AIR_SECONDS
	boost()
	set_level(level)
	EventSystem.CAR_jumped.emit(self)


## In the air a boat only touches the walls; the gates still see it (LAYER_AIRBORNE).
func set_level(value: int) -> void:
	super(value)
	if is_airborne():
		collision_layer = LAYER_AIRBORNE
		collision_mask = LAYER_WORLD


## A boat stays on the water: the shore, the quay and the islets stop it.
func _edge_layer() -> int:
	return LAYER_LAND_EDGE


## Shallows and banks hold a boat back; not one in the air, nor a hovercraft.
func _offroad(mult: float) -> float:
	if is_airborne() or (setup and setup.ignores_land):
		return 1.0
	return super(mult)


func _physics_process(delta: float) -> void:
	super(delta)
	if is_airborne():
		air_time = maxf(air_time - delta, 0.0)
		if not is_airborne():
			set_level(level)
			EventSystem.CAR_landed.emit(self)
	_draw_motion(delta)


## In a current the water itself moves: grip and drag work on the boat's motion through the
## water, so whichever way it points, the river carries it along.
func _apply_grip(forward: Vector2, delta: float) -> void:
	var water := current if not is_airborne() else Vector2.ZERO
	velocity -= water
	super(forward, delta)
	velocity += water


func _limit_speed(speed_along: float, delta: float) -> void:
	# As a car's, plus whatever the current adds: a boat riding a current goes faster.
	var boosted := lerpf(1.0, BOOST_SPEED_MULT, boost_strength())
	var limit := config.max_speed * surface_speed() * catch_up_mult * boosted + current.length()
	if speed_along < 0.0:
		limit = config.max_reverse_speed
	var speed := velocity.length()
	if speed > limit:
		velocity = velocity / speed * move_toward(speed, limit, OVERSPEED_DECEL * delta)


func _move_and_handle_walls() -> void:
	var before := velocity
	move_and_slide()
	var touching := false
	var impact := 0.0
	var normal := Vector2.ZERO
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		if not hit.get_collider() is Car:
			touching = true
			var into := -before.dot(hit.get_normal())
			if into > impact:
				impact = into
				normal = hit.get_normal()
	if touching and not _touching_wall and impact > config.wall_hit_threshold:
		# A fresh bump: a little speed lost, and a soft push back out into the water.
		velocity = velocity * (1.0 - config.wall_speed_scrub) + normal * impact * BOUNCE
		EventSystem.CAR_wall_hit.emit(self, impact)
	_touching_wall = touching


## The bob on the water, and the hop off a ramp with its shadow dropping away below.
func _draw_motion(delta: float) -> void:
	var fraction := clampf(velocity.length() / config.max_speed, 0.0, 1.0)
	_bob += delta * (2.2 + 3.0 * fraction)
	var hop := sin(PI * (1.0 - air_time / AIR_SECONDS)) if is_airborne() else 0.0
	var lift := 1.0 + AIR_SCALE * hop
	var dip := 1.0 - BOB_DIP * (0.5 + 0.5 * sin(_bob * 1.7)) * (1.0 - hop)
	_body.scale = Vector2(lift, lift * dip)
	_body.rotation = deg_to_rad(BOB_DEGREES) * sin(_bob) * (0.4 + 0.6 * fraction) * (1.0 - hop)
	_shadow.visible = is_airborne()
	_shadow.texture = _body.texture  # follows a repaint
	_shadow.position = SHADOW_OFFSET * (1.0 + 3.0 * hop)
	_shadow.scale = Vector2.ONE * (1.0 - 0.15 * hop)

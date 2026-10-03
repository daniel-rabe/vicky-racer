extends Node
## Headless checks that the handling keeps the promises in docs/DESIGN.md §4.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/handling_test.tscn
## Exit code 0 = all passed. Each test drives a fresh car on an empty arena.

const CAR_SCENE := preload("res://actors/car/car.tscn")
const SETUP_DIR := "res://game/configs/setups/"
const DT := 1.0 / 60.0

var _failures: PackedStringArray = []
var _wall_hits := 0


func _ready() -> void:
	EventSystem.CAR_wall_hit.connect(func(_car: Node, _impact: float) -> void: _wall_hits += 1)
	await _run_all()
	if _failures.is_empty():
		print("ALL HANDLING TESTS PASSED")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _run_all() -> void:
	await _test_accelerates_to_top_speed()
	await _test_no_turning_on_the_spot()
	await _test_cannot_spin_out()
	await _test_handbrake_drifts()
	await _test_reverse_is_capped()
	await _test_wall_slides_not_stops()
	await _test_grass_slows_gradually()
	_test_setups_resolve_within_clamps()


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures.append(message)


func _new_car(setup_id := "starter") -> Car:
	var arena := Node2D.new()
	add_child(arena)
	var car: Car = CAR_SCENE.instantiate()
	car.setup = load(SETUP_DIR + setup_id + ".tres")
	car.position = Vector2(5000, 5000)
	arena.add_child(car)
	return car


func _drive(car: Car, seconds: float, steer := 0.0, throttle := 0.0, handbrake := false) -> void:
	for i in int(seconds / DT):
		car.steer_input = steer
		car.throttle_input = throttle
		car.handbrake = handbrake
		await get_tree().physics_frame


func _done(car: Car) -> void:
	car.get_parent().queue_free()
	await get_tree().physics_frame


func _test_accelerates_to_top_speed() -> void:
	print("accelerates to top speed")
	var car := _new_car()
	await _drive(car, 4.0, 0.0, 1.0)
	var speed := car.velocity.length()
	_check(speed > 0.9 * car.config.max_speed, "reaches >90%% of max speed in 4 s (got %d)" % speed)
	_check(speed <= car.config.max_speed + 1.0, "never exceeds max speed (got %d)" % speed)
	await _done(car)


func _test_no_turning_on_the_spot() -> void:
	print("no turning on the spot")
	var car := _new_car()
	await _drive(car, 1.0, 1.0, 0.0)
	_check(is_zero_approx(car.rotation), "full steer at a standstill does not rotate the car")
	await _done(car)


func _test_cannot_spin_out() -> void:
	print("cannot spin out")
	var car := _new_car("banana")  # the slipperiest setup
	await _drive(car, 1.5, 0.0, 1.0)
	var max_rate := 0.0
	var last := car.rotation
	for i in 300:
		car.steer_input = 1.0 if (i / 60) % 2 == 0 else -1.0  # flick left/right every second
		car.throttle_input = 1.0
		car.handbrake = true
		await get_tree().physics_frame
		max_rate = maxf(max_rate, absf(angle_difference(last, car.rotation)) / DT)
		last = car.rotation
	_check(max_rate <= car.config.max_steer_rate + 0.01,
		"rotation never faster than the steering allows (%.2f <= %.2f rad/s)" % [max_rate, car.config.max_steer_rate])
	_check(car.forward_speed() > 0.0, "still pointing the way it travels after 5 s of flicking with handbrake")
	await _done(car)


func _test_handbrake_drifts() -> void:
	print("handbrake drifts")
	var grippy_slide := 0.0
	var handbrake_slide := 0.0
	for use_handbrake in [false, true]:
		var car := _new_car()
		await _drive(car, 2.0, 0.0, 1.0)
		var peak := 0.0
		for i in 45:
			await _drive(car, DT, 1.0, 1.0, use_handbrake)
			peak = maxf(peak, car.lateral_speed)
		if use_handbrake:
			handbrake_slide = peak
		else:
			grippy_slide = peak
		await _done(car)
	_check(handbrake_slide > 2.0 * grippy_slide,
		"handbrake at least doubles the sideways slide in a turn (%d vs %d px/s)" % [handbrake_slide, grippy_slide])
	_check(handbrake_slide > 220.0, "handbrake turn crosses the drift threshold (%d px/s)" % handbrake_slide)


func _test_reverse_is_capped() -> void:
	print("reverse is capped")
	var car := _new_car()
	await _drive(car, 4.0, 0.0, -1.0)
	_check(car.forward_speed() < -100.0, "holding brake from a standstill reverses (%d)" % car.forward_speed())
	_check(-car.forward_speed() <= car.config.max_reverse_speed + 1.0,
		"reverse speed capped at %d (got %d)" % [car.config.max_reverse_speed, -car.forward_speed()])
	await _done(car)


func _test_wall_slides_not_stops() -> void:
	print("walls slide, not stop")
	var car := _new_car()
	var wall := StaticBody2D.new()
	var shape := CollisionShape2D.new()
	var box := RectangleShape2D.new()
	box.size = Vector2(40, 4000)
	shape.shape = box
	wall.add_child(shape)
	wall.position = car.position + Vector2(900, 0)
	car.get_parent().add_child(wall)
	car.rotation = deg_to_rad(-30.0)  # hit the wall at a glancing angle
	_wall_hits = 0
	await _drive(car, 1.6, 0.0, 1.0)
	var before := car.velocity.length()
	await _drive(car, 0.8, 0.0, 1.0)
	_check(_wall_hits >= 1, "wall hit was reported (%d)" % _wall_hits)
	_check(car.velocity.length() > 0.3 * before, "keeps moving along the wall (%d of %d px/s)" % [car.velocity.length(), before])
	_check(car.position.x < wall.position.x, "does not pass through the wall")
	await _done(car)


func _test_grass_slows_gradually() -> void:
	print("grass slows gradually")
	var car := _new_car()
	await _drive(car, 4.0, 0.0, 1.0)
	var top := car.velocity.length()
	car.surface_speed_mult = 0.55
	await _drive(car, 0.1, 0.0, 1.0)
	var after_a_moment := car.velocity.length()
	await _drive(car, 2.0, 0.0, 1.0)
	var settled := car.velocity.length()
	_check(after_a_moment > 0.85 * top, "no sudden stop on leaving the road (%d -> %d)" % [top, after_a_moment])
	_check(settled <= 0.55 * car.config.max_speed + 5.0, "settles to the grass speed limit (%d)" % settled)
	await _done(car)


func _test_setups_resolve_within_clamps() -> void:
	print("setups resolve within clamps")
	var base: CarConfig = load("res://game/configs/cars/base_car.tres")
	for file in DirAccess.get_files_at(SETUP_DIR):
		if not file.ends_with(".tres"):
			continue
		var setup: DriftSetup = load(SETUP_DIR + file)
		var c := base.with_setup(setup)
		_check(c.lateral_grip >= CarConfig.MIN_LATERAL_GRIP and c.max_speed <= CarConfig.MAX_SPEED_CAP,
			"%s: grip %.2f, top speed %d within clamps" % [setup.id, c.lateral_grip, c.max_speed])

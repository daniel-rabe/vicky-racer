extends Node
## Headless checks for Track 01: surfaces, lap progress, gates and the start grid
## (docs/DESIGN.md §7).
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/track_test.tscn
## Exit code 0 = all passed.

const TRACK_SCENE := preload("res://track/tracks/track_01.tscn")
const CAR_SCENE := preload("res://actors/car/car.tscn")
const TILE := 128.0

var _failures: PackedStringArray = []
var _finishes := 0
var _checkpoints := 0
var track: Track


func _ready() -> void:
	track = TRACK_SCENE.instantiate()
	add_child(track)
	track.finish_crossed.connect(func(_c: Car) -> void: _finishes += 1)
	track.checkpoint_crossed.connect(func(_c: Car) -> void: _checkpoints += 1)
	await get_tree().physics_frame
	_test_surfaces()
	_test_progress()
	_test_grid()
	await _test_car_gets_surface()
	await _test_gates()
	if _failures.is_empty():
		print("ALL TRACK TESTS PASSED")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures.append(message)


func _line_point(fraction: float) -> Vector2:
	var curve := track.racing_line.curve
	return track.racing_line.to_global(curve.sample_baked(curve.get_baked_length() * fraction))


func _test_surfaces() -> void:
	print("surfaces")
	var off_road := 0
	for i in 40:
		if track.surface_at(_line_point(i / 40.0)) != &"asphalt":
			off_road += 1
	_check(off_road == 0, "40 points along the racing line are asphalt (%d were not)" % off_road)
	# Sand-trap centres from the layout (tiles): outside T1 and outside the T2 hairpin.
	for centre in [Vector2(42.5, 24.0), Vector2(37.0, 1.6)]:
		var surface := track.surface_at(centre * TILE)
		_check(surface == &"sand", "sand trap at %s is sand (got %s)" % [centre, surface])
	var infield := track.surface_at(Vector2(20, 17) * TILE)
	_check(infield == &"grass", "the infield is grass (got %s)" % infield)


func _test_progress() -> void:
	print("lap progress")
	var length := track.lap_length()
	_check(length > 12000.0 and length < 15000.0, "lap length matches the layout, ~13,600 px (got %d)" % length)
	var backwards := 0
	var last := -1.0
	for i in 50:
		var p := track.progress_at(_line_point(i / 50.0))
		if p < last:
			backwards += 1
		last = p
	_check(backwards == 0, "progress only increases along the line (%d steps went back)" % backwards)


func _test_grid() -> void:
	print("start grid")
	var grid := track.grid_transforms()
	_check(grid.size() == 4, "four grid slots (got %d)" % grid.size())
	for i in grid.size():
		var t: Transform2D = grid[i]
		var ahead := track.progress_at(t.origin + t.x * 100.0) - track.progress_at(t.origin)
		_check(track.surface_at(t.origin) == &"asphalt" and ahead > 50.0,
			"slot %d is on the road and faces the way the lap runs" % (i + 1))


func _test_car_gets_surface() -> void:
	print("cars get the surface under them")
	var car: Car = CAR_SCENE.instantiate()
	car.position = Vector2(42.5, 24.0) * TILE
	add_child(car)
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(is_equal_approx(car.surface_speed_mult, 0.4) and is_equal_approx(car.surface_grip_mult, 0.6),
		"a car in the sand trap drives with sand multipliers (%.2f, %.2f)" % [car.surface_speed_mult, car.surface_grip_mult])
	car.global_position = _line_point(0.5)
	car.reset_physics_interpolation()
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(is_equal_approx(car.surface_speed_mult, 1.0), "back on the road it gets asphalt again")
	car.queue_free()
	await get_tree().physics_frame


func _test_gates() -> void:
	print("finish line and checkpoint")
	for gate_name in ["FinishLine", "Checkpoint"]:
		var gate: Area2D = track.get_node(gate_name)
		var car: Car = CAR_SCENE.instantiate()
		car.global_position = gate.global_position - gate.transform.y * 300.0  # behind the gate
		car.rotation = gate.rotation + PI / 2.0                                # facing through it
		add_child(car)
		await get_tree().physics_frame
		for i in 60:
			car.throttle_input = 1.0
			await get_tree().physics_frame
		car.queue_free()
		await get_tree().physics_frame
	_check(_finishes == 1, "driving through the finish line reports it once (got %d)" % _finishes)
	_check(_checkpoints == 1, "driving through the checkpoint reports it once (got %d)" % _checkpoints)

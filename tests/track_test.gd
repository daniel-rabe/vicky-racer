extends Node
## Headless checks for Track 01 (surfaces, lap progress, gates, the start grid) and for
## every track (docs/DESIGN.md §7): road, grid, theme surfaces, ice, boost pads, props.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/track_test.tscn
## Exit code 0 = all passed.

const TRACK_SCENE := preload("res://track/tracks/track_01.tscn")
const CAR_SCENE := preload("res://actors/car/car.tscn")
const TILE := 128.0

var _failures: PackedStringArray = []
var _finishes := 0
var _checkpoints := 0
var track: Track
var layout: Dictionary  # Track 01's points file, as the builder read it


func _ready() -> void:
	layout = JSON.parse_string(FileAccess.get_file_as_string("res://docs/mockups/track_01_points.json"))
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
	track.queue_free()
	await get_tree().physics_frame
	for id in GarageManager.TRACK_ORDER:
		await _test_every_track(id)
	await _test_boost_pad()
	await _test_bridges()
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
	# Every sand trap in the layout is sand at its centre.
	for patch: Array in layout["patches_tiles"]:
		var centre := Vector2(patch[0][0], patch[0][1]).clamp(Vector2.ONE, Vector2(layout["map_tiles"][0], layout["map_tiles"][1]) - Vector2.ONE)
		var surface := track.surface_at(centre * TILE)
		_check(surface == &"sand", "sand trap at %s is sand (got %s)" % [centre, surface])
	var infield := track.surface_at(Vector2(15, 20) * TILE)
	_check(infield == &"grass", "the infield is grass (got %s)" % infield)


func _test_progress() -> void:
	print("lap progress")
	var length := track.lap_length()
	var expected: float = layout["lap_length_px"]
	_check(absf(length - expected) < expected * 0.01, "lap length matches the layout, ~%d px (got %d)" % [expected, length])
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
		var ahead := fposmod(track.progress_at(t.origin + t.x * 100.0) - track.progress_at(t.origin), track.lap_length())
		_check(track.surface_at(t.origin) == &"asphalt" and ahead > 50.0 and ahead < 500.0,
			"slot %d is on the road and faces the way the lap runs" % (i + 1))


func _test_car_gets_surface() -> void:
	print("cars get the surface under them")
	var car: Car = CAR_SCENE.instantiate()
	var trap: Array = layout["patches_tiles"][0][0]
	car.position = Vector2(trap[0], trap[1]).clamp(Vector2.ONE, Vector2(layout["map_tiles"][0], layout["map_tiles"][1]) - Vector2.ONE) * TILE
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


## The same promises for each track, built from its layout.
func _test_every_track(id: StringName) -> void:
	var config: TrackConfig = load("res://game/configs/tracks/%s.tres" % id)
	var layout: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://docs/mockups/%s_points.json" % id))
	var t: Track = config.track_scene.instantiate()
	add_child(t)
	await get_tree().physics_frame
	print("%s: %s" % [id, config.display_name])
	var curve := t.racing_line.curve
	var bad := 0
	for i in 60:
		var at := t.racing_line.to_global(curve.sample_baked(curve.get_baked_length() * i / 60.0))
		if t.surface_at(at) not in [&"asphalt", &"ice"]:
			bad += 1
	_check(bad == 0, "  the racing line is road all the way round (%d points off it)" % bad)
	var grid := t.grid_transforms()
	var grid_ok := grid.size() == 4
	for g: Transform2D in grid:
		var on_road := t.surface_at(g.origin) == &"asphalt"
		var step := fposmod(t.progress_at(g.origin + g.x * 100.0) - t.progress_at(g.origin), t.lap_length())
		var facing := step > 0.0 and step < t.lap_length() / 2.0  # forward, even across the lap's start
		grid_ok = grid_ok and on_road and facing
	_check(grid_ok, "  four grid slots on the road, facing the way the lap runs")
	for patch: Array in layout.get("patches_tiles", []):
		var centre := Vector2(patch[0][0], patch[0][1]) * TILE
		if t.distance_to_line(centre) > t.road_half_width + 200.0 and Rect2(Vector2.ZERO, t.map_size).has_point(centre):
			_check(t.surface_at(centre) == t.theme.patch_surface,
				"  a patch at %s is %s (got %s)" % [patch[0], t.theme.patch_surface, t.surface_at(centre)])
			break
	var spans: Array = layout.get("ice_spans", [])
	_check(t.ice_spans.size() == spans.size(), "  %d ice span(s) on the road" % spans.size())
	for span: Array in spans:
		var mid := t.line_point((span[0] + span[1] / 2.0) * t.lap_length())
		_check(t.surface_at(mid) == &"ice", "  the middle of an ice span is ice")
	var pads: Array = layout.get("boost_pads", [])
	var built := t.get_node("BoostPads").get_child_count() if t.has_node("BoostPads") else 0
	_check(built == pads.size(), "  %d boost pad(s) (built %d)" % [pads.size(), built])
	var on_road := 0
	for prop: Node2D in t.get_node("Props").get_children():
		if t.distance_to_line(prop.global_position) < t.road_half_width + 40.0:
			on_road += 1
	_check(on_road == 0, "  no prop stands on the road (%d do)" % on_road)
	t.queue_free()
	await get_tree().physics_frame


## A car crossing a boost pad goes faster than its top speed for a moment.
func _test_boost_pad() -> void:
	print("boost pads")
	var t: Track = load("res://game/configs/tracks/track_04.tres").track_scene.instantiate()
	add_child(t)
	var pad: Area2D = t.get_node("BoostPads").get_child(0)
	var car: Car = CAR_SCENE.instantiate()
	car.global_position = pad.global_position - pad.transform.x * 900.0
	car.rotation = pad.rotation
	add_child(car)
	var top := 0.0
	var boosts := [0]
	var count := func(_c: Node) -> void: boosts[0] += 1
	EventSystem.CAR_boosted.connect(count)
	for i in 120:
		car.throttle_input = 1.0
		await get_tree().physics_frame
		top = maxf(top, car.velocity.length())
	EventSystem.CAR_boosted.disconnect(count)
	_check(boosts[0] == 1, "driving over a pad boosts once (%d)" % boosts[0])
	_check(top > car.config.max_speed * 1.1, "the boost passes the car's top speed (%d of %d)" % [top, car.config.max_speed])
	car.queue_free()
	t.queue_free()
	await get_tree().physics_frame


## Bridges (docs/DESIGN.md §7.7), on the figure-of-eight Meadow Loop.
func _test_bridges() -> void:
	print("bridges")
	var t: Track = load("res://game/configs/tracks/track_01.tres").track_scene.instantiate()
	add_child(t)
	await get_tree().physics_frame
	_check(t.bridge_spans.size() == 1 and t.has_node("Railings"), "Meadow Loop has a bridge with railings")
	var span := t.bridge_spans[0]
	var length := t.lap_length()
	# A car driven along the line from before the bridge to after it.
	var car: Car = CAR_SCENE.instantiate()
	var start := (span.x - 0.06) * length
	car.global_position = t.line_point(start)
	car.rotation = t.line_tangent(start).angle()
	add_child(car)
	var levels := []
	var last := t.progress_at(car.global_position)
	var backwards := 0
	for i in 480:
		var here := t.progress_of(car)
		var ahead := t.line_point(here + 250.0)
		car.steer_input = clampf(Vector2.RIGHT.rotated(car.rotation).angle_to(ahead - car.global_position) / 0.45, -1.0, 1.0)
		car.throttle_input = 0.6
		await get_tree().physics_frame
		var now := t.progress_of(car)
		if fposmod(now - last, length) > length / 2.0:
			backwards += 1
		last = now
		if levels.is_empty() or levels[-1] != car.level:
			levels.append(car.level)
	_check(levels == [0, 1, 0], "a car driving over goes up onto the bridge and down again (%s)" % [levels])
	_check(backwards == 0, "its race position never jumps to the other pass at the crossing (%d jumps)" % backwards)
	car.queue_free()
	# Two cars at the crossing, one on each level, driven into each other.
	var crossing := t.line_point((span.x + span.y / 2.0) * length)
	for same in [false, true]:
		var a: Car = CAR_SCENE.instantiate()
		var b: Car = CAR_SCENE.instantiate()
		add_child(a)
		add_child(b)
		for c in [a, b]:
			c.set_physics_process(false)
			c.remove_from_group(&"cars")  # the track would set their levels from where they are
		a.global_position = crossing + Vector2(-200, 0)
		b.global_position = crossing
		a.set_level(1)
		b.set_level(1 if same else 0)
		await get_tree().physics_frame
		a.velocity = Vector2(900, 0)
		var hit := false
		for i in 20:
			if a.move_and_collide(a.velocity / 60.0, true) and a.move_and_collide(a.velocity / 60.0, true).get_collider() == b:
				hit = true
			a.global_position += a.velocity / 60.0
		if same:
			_check(hit, "two cars on the same level still bump")
		else:
			_check(not hit, "a car on the bridge passes over a car below it")
		a.queue_free()
		b.queue_free()
		await get_tree().physics_frame
	# A car on the deck steering hard sideways meets the railing.
	var rail_car: Car = CAR_SCENE.instantiate()
	add_child(rail_car)
	rail_car.global_position = crossing
	rail_car.rotation = t.line_tangent((span.x + span.y / 2.0) * length).angle() + PI / 2.0
	rail_car.set_level(1)
	rail_car.set_physics_process(false)
	rail_car.remove_from_group(&"cars")
	await get_tree().physics_frame
	var blocked := rail_car.move_and_collide(Vector2.RIGHT.rotated(rail_car.rotation) * (t.road_half_width + 120.0), true)
	_check(blocked != null, "a car on the bridge cannot drive off its side")
	rail_car.set_level(0)
	blocked = rail_car.move_and_collide(Vector2.RIGHT.rotated(rail_car.rotation) * (t.road_half_width + 120.0), true)
	_check(blocked == null or not (blocked.get_collider() is StaticBody2D and blocked.get_collider().name == "Railings"),
		"while a car below drives under the railings")
	rail_car.queue_free()
	t.queue_free()
	await get_tree().physics_frame

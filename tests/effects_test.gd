extends Node2D
## Headless checks for the Phase 8 effects (docs/DESIGN.md §4.3): skid marks while
## drifting, dust on grass and sand, tyre smoke on the road, and the wall-hit camera shake.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/effects_test.tscn
## Exit code 0 = all passed. Run with a window and `-- --screenshot=<path.png>` to save a
## picture of a drift onto the grass, for checking the look.

const CAR_SCENE := preload("res://actors/car/car.tscn")
const CAMERA_SCRIPT := preload("res://actors/car/chase_camera.gd")
const GRASS := preload("res://art/tiles/grass.png")
const ASPHALT := preload("res://art/tiles/asphalt.png")
const DT := 1.0 / 60.0

var _failures: PackedStringArray = []
var _screenshot := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_screenshot = arg.get_slice("=", 1)
	await _test_skid_marks_and_smoke()
	await _test_dust_on_grass()
	await _test_wall_shake()
	await _test_car_specific_effects()
	if not _screenshot.is_empty():
		await _take_screenshot()
		# With a window the cars' engines are audible: free them and let audio mix once, or
		# the still-playing loops are reported as leaked at exit (see SoundManager.audible).
		for child in get_children():
			child.queue_free()
		await get_tree().create_timer(0.5).timeout
	if _failures.is_empty():
		print("ALL EFFECTS TESTS PASSED")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures.append(message)


## A ground of `texture`, a SkidMarks layer and a car on top, the way the race stacks them.
func _arena(texture: Texture2D) -> Car:
	var arena := Node2D.new()
	arena.name = "Arena"
	add_child(arena)
	var ground := Sprite2D.new()
	ground.texture = texture
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.region_enabled = true
	ground.region_rect = Rect2(0, 0, 8000, 8000)
	ground.position = Vector2(5000, 5000)
	arena.add_child(ground)
	var skids := SkidMarks.new()
	skids.name = "SkidMarks"
	arena.add_child(skids)
	var car: Car = CAR_SCENE.instantiate()
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


func _marks(car: Car) -> Array[Line2D]:
	var out: Array[Line2D] = []
	for child in car.get_parent().get_node("SkidMarks").get_children():
		out.append(child as Line2D)
	return out


func _emitter(car: Car, index: int) -> GPUParticles2D:
	return car.get_node("Effects").get_child(index)  # 0 = dust, 1 = smoke


func _test_skid_marks_and_smoke() -> void:
	print("skid marks and tyre smoke")
	var car := _arena(ASPHALT)
	await _drive(car, 1.5, 0.0, 1.0)
	_check(_marks(car).is_empty(), "driving straight leaves no marks")
	_check(not _emitter(car, 1).emitting, "and no smoke")
	await _drive(car, 1.0, 1.0, 1.0, true)
	var marks := _marks(car)
	_check(car.is_drifting, "a handbrake turn drifts")
	_check(marks.size() == 2, "a drift lays two marks, one per rear wheel (got %d)" % marks.size())
	_check(marks.all(func(l: Line2D) -> bool: return l.get_point_count() > 10),
		"the marks follow the car (%s points)" % [marks.map(func(l: Line2D) -> int: return l.get_point_count())])
	_check(_emitter(car, 1).emitting, "drifting on the road smokes")
	await _drive(car, 2.0, 0.0, -1.0)
	_check(not car.is_drifting and not _emitter(car, 1).emitting, "the smoke stops with the drift")
	var points := marks[0].get_point_count()
	await _drive(car, 0.5, 0.0, 1.0)
	_check(marks[0].get_point_count() == points, "a finished mark stops growing")
	await get_tree().create_timer(SkidMarks.FADE_AFTER + SkidMarks.FADE_TIME + 0.5).timeout
	_check(_marks(car).is_empty(), "finished marks fade away")
	for i in 60:  # many short drifts: the layer must stay capped
		EventSystem.CAR_drift_started.emit(car)
		EventSystem.CAR_drift_ended.emit(car, 0.1)
	await get_tree().process_frame
	var kept := _marks(car).filter(func(l: Line2D) -> bool: return not l.is_queued_for_deletion())
	_check(kept.size() <= SkidMarks.MAX_MARKS, "marks are capped at %d (kept %d)" % [SkidMarks.MAX_MARKS, kept.size()])
	await _done(car)


func _test_dust_on_grass() -> void:
	print("dust on grass and sand")
	var car := _arena(GRASS)
	var dust := _emitter(car, 0)
	await _drive(car, 1.0, 0.0, 1.0)
	_check(not dust.emitting, "no dust on the road")
	EventSystem.CAR_surface_changed.emit(car, &"grass")
	await _drive(car, 0.2, 0.0, 1.0)
	_check(dust.emitting, "dust flies on grass")
	EventSystem.CAR_surface_changed.emit(car, &"sand")
	await _drive(car, 0.2, 0.0, 1.0)
	_check(dust.emitting and dust.modulate != car.get_node("Effects").DUST_COLOURS[&"grass"],
		"sand throws sand-coloured dust")
	car.velocity = Vector2.ZERO
	await _drive(car, 0.2)
	_check(not dust.emitting, "no dust once the car has stopped")
	await _done(car)


func _test_wall_shake() -> void:
	print("wall-hit shake")
	var car := _arena(GRASS)
	var rig := Node2D.new()
	rig.name = "ChaseCamera"
	rig.set_script(CAMERA_SCRIPT)
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	rig.add_child(camera)
	car.add_child(rig)
	await _drive(car, 0.2)
	_check(rig.position.is_zero_approx(), "a parked car's camera is still")
	EventSystem.CAR_wall_hit.emit(car, 600.0)
	await _drive(car, DT)
	var jolt: float = rig.position.length()
	_check(jolt > 0.5 and jolt <= rig.shake_max * 1.5, "a wall hit shakes the view a little (%.1f px)" % jolt)
	await _drive(car, 1.0)
	_check(rig.position.length() < 0.5, "the shake dies away within a second (%.2f px)" % rig.position.length())
	var other := CAR_SCENE.instantiate()
	add_child(other)
	EventSystem.CAR_wall_hit.emit(other, 600.0)
	await _drive(car, DT)
	_check(rig.position.length() < 0.5, "another car's wall hit does not shake this camera")
	other.queue_free()
	await _done(car)


## Cars bring their own effects: the Dragon's fiery marks and smoke, the Police Car's lights.
func _test_car_specific_effects() -> void:
	print("car-specific effects")
	var dragon := _arena(ASPHALT)
	dragon.setup = load("res://game/configs/setups/dragon.tres")
	await _drive(dragon, 1.0, 0.0, 1.0)
	await _drive(dragon, 0.6, 1.0, 1.0, true)
	var marks := _marks(dragon)
	_check(not marks.is_empty() and marks[0].default_color == dragon.setup.skid_colour, "the Dragon leaves fire-coloured skid marks")
	_check(_emitter(dragon, 1).modulate == dragon.setup.smoke_colour, "and orange smoke")
	await _done(dragon)
	var police := _arena(ASPHALT)
	police.setup = load("res://game/configs/setups/police.tres")
	var lights: Node2D = police.get_node("Effects").get_child(2)
	await _drive(police, 1.0, 0.0, 1.0)
	_check(not lights.visible, "the Police Car's lights are off while it drives straight")
	await _drive(police, 0.6, 1.0, 1.0, true)
	_check(lights.visible, "and flash while it drifts")
	await _done(police)


## A drift that runs off the road onto the grass: marks, smoke and dust in one picture.
func _take_screenshot() -> void:
	var car := _arena(ASPHALT)
	var grass := Sprite2D.new()
	grass.texture = GRASS
	grass.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	grass.region_enabled = true
	grass.region_rect = Rect2(0, 0, 4000, 8000)
	grass.centered = false
	grass.position = Vector2(5750, 1000)
	car.get_parent().add_child(grass)
	car.get_parent().move_child(grass, 1)
	var camera := Camera2D.new()
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	camera.zoom = Vector2(0.92, 0.92)
	car.add_child(camera)
	camera.make_current()
	await _drive(car, 1.0, 0.0, 1.0)
	await _drive(car, 0.9, 1.0, 1.0, true)
	EventSystem.CAR_surface_changed.emit(car, &"grass")
	await _drive(car, 0.6, 0.4, 1.0, true)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_screenshot)

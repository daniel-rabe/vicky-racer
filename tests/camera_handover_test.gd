extends Node
## Headless test: a screen whose camera arrives while the old screen's camera is still current
## takes the view over. The title's attract-mode race has a camera; going from the title
## straight into Free Drive once left the town's camera not current, and the view froze where
## the car started while the car drove away (docs/DESIGN.md §19).
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/camera_handover_test.tscn -- --save=user://camera_handover_test.cfg
## Exit code 0 = all passed.

func _ready() -> void:
	var main: Node = load("res://game/main.tscn").instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	EventSystem.UI_screen_requested.emit(&"town")
	await get_tree().create_timer(0.5).timeout
	Input.action_press(&"accelerate")
	await get_tree().create_timer(2.5).timeout
	Input.action_release(&"accelerate")
	var player: Car
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		if car.has_node(^"PlayerInput"):
			player = car
	var failures: PackedStringArray = []
	var check := func(ok: bool, message: String) -> void:
		print(("  ok   " if ok else "  FAIL ") + message)
		if not ok:
			failures.append(message)
	var camera := get_viewport().get_camera_2d()
	check.call(camera != null and player.is_ancestor_of(camera), "the player's camera is the one in use")
	var on_screen := get_viewport().get_canvas_transform() * player.global_position
	check.call(Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size).has_point(on_screen),
		"the car is still on screen after driving away (drawn at %s)" % on_screen.round())
	if failures.is_empty():
		print("ALL CAMERA HANDOVER TESTS PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)

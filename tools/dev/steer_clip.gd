extends Node2D
## A short drive for a look at the steering front wheels and the body leaning out of a drift
## (docs/CAR_ANIMATION_PLAN.md §4, §5): frames saved as PNGs, to be put together into a clip.
## Needs a window:
##   Godot --path . --fixed-fps 60 res://tools/dev/steer_clip.tscn -- --out=<dir> [--car=kart]

const CAR_SCENE := preload("res://actors/car/car.tscn")
const ASPHALT := preload("res://art/tiles/asphalt.png")
## Seconds, steer, throttle, handbrake.
const PLAN := [[0.6, 0.0, 1.0, false], [0.5, -1.0, 1.0, false], [0.4, 1.0, 1.0, false],
	[1.2, 1.0, 1.0, true], [0.8, 0.0, 1.0, false], [0.9, -1.0, 1.0, true], [0.6, 0.0, 0.6, false]]
## Every this many ticks a frame is saved.
const EVERY := 3


func _ready() -> void:
	var out := "user://steer_clip"
	var car_id := "starter"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
		elif arg.begins_with("--car="):
			car_id = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(out)
	var ground := Sprite2D.new()
	ground.texture = ASPHALT
	ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	ground.region_enabled = true
	ground.region_rect = Rect2(0, 0, 8000, 8000)
	ground.position = Vector2(4000, 4000)
	add_child(ground)
	var skids := SkidMarks.new()
	skids.name = "SkidMarks"
	add_child(skids)
	var car: Car = CAR_SCENE.instantiate()
	car.setup = load("res://game/configs/setups/%s.tres" % car_id)
	car.position = Vector2(4000, 4000)
	add_child(car)
	var camera := Camera2D.new()
	camera.zoom = Vector2(2.5, 2.5)
	camera.ignore_rotation = true
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	car.add_child(camera)
	camera.make_current()
	var tick := 0
	var frame := 0
	for step: Array in PLAN:
		for i in int(step[0] * 60.0):
			car.steer_input = step[1]
			car.throttle_input = step[2]
			car.handbrake = step[3]
			await get_tree().physics_frame
			tick += 1
			if tick % EVERY == 0:
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png("%s/%04d.png" % [out, frame])
				frame += 1
	print("saved %d frames" % frame)
	for child in get_children():
		child.queue_free()
	await get_tree().create_timer(0.3).timeout
	get_tree().quit()

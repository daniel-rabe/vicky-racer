extends Node2D
## Every car with its front wheels turned left, straight and right, for a check by eye of the
## steering wheels (docs/CAR_ANIMATION_PLAN.md §4). Needs a window:
##   Godot --path . res://tools/dev/steer_sheet.tscn -- --out=<path.png>

const CAR_SCENE := preload("res://actors/car/car.tscn")
const SETUPS := ["starter", "kart", "formula", "monster", "dragon", "police", "rocket",
	"icecream", "banana", "grippy", "slider", "soapbox"]
const STEERS := [-1.0, 0.0, 1.0]
const CELL := Vector2(170, 110)


func _ready() -> void:
	var out := "user://steer_sheet.png"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out = arg.get_slice("=", 1)
	RenderingServer.set_default_clear_color(Color(0.42, 0.44, 0.47))
	scale = Vector2(1.8, 1.8)
	var cars: Array[Car] = []
	for row in SETUPS.size():
		for col in STEERS.size() * 2:
			var car: Car = CAR_SCENE.instantiate()
			car.setup = load("res://game/configs/setups/%s.tres" % SETUPS[row])
			if col >= STEERS.size():
				car.body_texture = Paint.body(car.setup, &"pink")
			car.frozen = true
			car.position = Vector2(90 + col * CELL.x + (20 if col >= STEERS.size() else 0), 60 + row * CELL.y / 1.15)
			add_child(car)
			cars.append(car)
	for i in 40:
		for c in cars.size():
			cars[c].steer_input = STEERS[(c % (STEERS.size() * 2)) % STEERS.size()]
		await get_tree().physics_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	get_tree().quit()

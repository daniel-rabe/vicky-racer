extends Node2D
## Saves pictures of a track's ground the way the race camera sees it, for judging ground art.
##   godot --path . --fixed-fps 60 res://tools/dev/ground_probe.tscn -- --track=res://track/tracks/track_01.tscn --out=<dir> [--frames=N]
## Writes <out>/<name>_<k>.png: one still per spot along the racing line, or with --frames=N
## N frames 1/15 s apart at the first spot (for a gif of anything that moves). A scene with
## no racing line (Free Drive's town) is shown through its own camera.

const CAR := preload("res://art/cars/car_red.png")

var _track_path := "res://track/tracks/track_01.tscn"
var _out := "user://ground_probe"
var _frames := 0
var _zoom := 0.92


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		var value := arg.get_slice("=", 1)
		match arg.get_slice("=", 0):
			"--track": _track_path = value
			"--out": _out = value
			"--frames": _frames = int(value)
			"--zoom": _zoom = float(value)
	DirAccess.make_dir_recursive_absolute(_out)
	var track: Node = load(_track_path).instantiate()
	add_child(track)
	var track_name := _track_path.get_file().get_basename()
	var line: Path2D = track.get_node_or_null(^"RacingLine")
	if line == null:
		for i in 60:
			await get_tree().process_frame
		await _shoot(track_name, 0)
		get_tree().quit(0)
		return
	var curve := line.curve
	var camera := Camera2D.new()
	camera.zoom = Vector2(_zoom, _zoom)
	add_child(camera)
	camera.make_current()
	var car := Sprite2D.new()
	car.texture = CAR
	add_child(car)
	var length := curve.get_baked_length()
	var spots := [0.08, 0.33, 0.6] if _frames == 0 else [0.08]
	for k in spots.size():
		var at: float = spots[k] * length
		var pos := line.to_global(curve.sample_baked(at))
		var ahead := line.to_global(curve.sample_baked(at + 20.0))
		car.position = pos
		car.rotation = (ahead - pos).angle()
		camera.position = pos + (ahead - pos).normalized() * 260.0
		await _shoot(track_name, k)
	get_tree().quit(0)


func _shoot(track_name: String, k: int) -> void:
	for f in maxi(1, _frames):
		for i in (8 if f == 0 else 4):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var file := "%s/%s_%d.png" % [_out, track_name, k] if _frames == 0 else "%s/%s_f%03d.png" % [_out, track_name, f]
		get_viewport().get_texture().get_image().save_png(file)

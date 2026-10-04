extends Node
## Performance probe (not a pass/fail test): races Track 01 with every car on autopilot and
## reports where frame time goes, so optimisations are measured, not guessed. `--track=track_03`
## races another track; `--two-player` splits the screen (two players and two AI) — with both,
## the busiest case the game has: four cars sliding on Snowy Peak's ice in two views.
##   with a window (rendering cost, vsync off):
##     Godot_console.exe --path . res://tests/perf_probe.tscn -- --autopilot
##   headless CPU benchmark (script + physics per simulated frame, nothing rendered):
##     Godot_console.exe --path . --headless --fixed-fps 60 res://tests/perf_probe.tscn -- --autopilot --bench
## Also times the track queries the cars make every frame, call by call.

const RACE_SCENE := preload("res://game/screens/race.tscn")
const WARMUP := 5.0
const MEASURE := 20.0

var _samples := {"frame": [], "process": [], "physics": [], "draw_calls": [], "objects": []}


func _enter_tree() -> void:
	var track_id := &"track_01"
	var two_player := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--track="):
			track_id = StringName(arg.get_slice("=", 1))
		two_player = two_player or arg == "--two-player"
	var config: TrackConfig = load("res://game/configs/tracks/%s.tres" % track_id)
	EventSystem.PRO_state_requested.connect(func() -> void:
		EventSystem.PRO_state_changed.emit({"setups": [load("res://game/configs/setups/banana.tres"),
			load("res://game/configs/setups/slider.tres")], "equipped": &"banana", "selected_track": track_id,
			"tracks": [{"config": config}]}))
	EventSystem.PLY_state_requested.connect(func() -> void:
		EventSystem.PLY_state_changed.emit({"two_player": two_player, "opponents": true, "players": [
			{"device": {"kind": &"keys_left"}, "setup": &"banana"}, {"device": {"kind": &"keys_right"}, "setup": &"slider"}]}))
	EventSystem.UI_settings_requested.connect(func() -> void:
		EventSystem.UI_settings_changed.emit({"sound_volume": 0.0, "music_volume": 0.0, "fullscreen": false,
			"auto_accelerate": false, "steering_help": false, "difficulty": &"normal"}))


func _ready() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var load_start := Time.get_ticks_usec()
	var race: Node2D = RACE_SCENE.instantiate()
	add_child(race)
	# No pause menu: it pauses the race when the window loses focus, and a probe started from a
	# terminal often never has focus. It measures the race, not the menus.
	race.get_node("PauseMenu").free()
	print("race load: %.1f ms (instantiate + _ready: track, road, cars)" % ((Time.get_ticks_usec() - load_start) / 1000.0))
	_time_track_queries(race.track)
	await get_tree().create_timer(WARMUP).timeout
	if "--bench" in OS.get_cmdline_user_args():
		await _bench(race)
		return
	var end := Time.get_ticks_msec() + int(MEASURE * 1000.0)
	var frames := 0
	var paused := 0
	var progress_before: float = race.manager.racers[0]["progress"]
	var start := Time.get_ticks_usec()
	while Time.get_ticks_msec() < end:
		await get_tree().process_frame
		frames += 1
		paused += 1 if get_tree().paused else 0
		_samples["process"].append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		_samples["physics"].append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
		_samples["draw_calls"].append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		_samples["objects"].append(Performance.get_monitor(Performance.OBJECT_COUNT))
	var elapsed := (Time.get_ticks_usec() - start) / 1e6
	print("paused frames %d; car 1 drove %.0f px" % [paused,
		race.manager.racers[0]["progress"] - progress_before])
	print("frames %d in %.1fs = %.0f fps (%.2f ms/frame)" % [frames, elapsed, frames / elapsed, elapsed * 1000.0 / frames])
	for key in ["process", "physics"]:
		print("%-10s avg %.3f ms  p99 %.3f ms  max %.3f ms" % [key, _avg(_samples[key]), _pct(_samples[key], 0.99), _samples[key].max()])
	print("draw calls avg %.0f  max %d" % [_avg(_samples["draw_calls"]), _samples["draw_calls"].max()])
	print("objects    first %d  last %d" % [_samples["objects"][0], _samples["objects"][-1]])
	print("static memory %.1f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0))
	race.queue_free()
	await get_tree().create_timer(0.5).timeout
	get_tree().quit()


## With --fixed-fps 60 each frame is exactly one physics tick and nothing waits on the
## clock, so wall time per frame is the whole CPU cost of simulating the race.
func _bench(race: Node) -> void:
	var frames := 1800
	var start := Time.get_ticks_usec()
	for i in frames:
		await get_tree().physics_frame
	var per_frame := (Time.get_ticks_usec() - start) / float(frames)
	print("bench: %.0f us per simulated frame (%d frames, %d cars)" % [per_frame, frames, race.racers.size()])

	race.queue_free()
	await get_tree().process_frame
	get_tree().quit()


## Microbenchmark the per-frame track queries every car makes.
func _time_track_queries(track: Track) -> void:
	var points: Array[Vector2] = []
	var rect := track.world_rect()
	for i in 500:
		points.append(rect.position + Vector2(randf() * rect.size.x, randf() * rect.size.y))
	for name in ["progress_at", "distance_to_line", "surface_at", "side_of_line", "line_point"]:
		var t := Time.get_ticks_usec()
		for p in points:
			match name:
				"progress_at": track.progress_at(p)
				"distance_to_line": track.distance_to_line(p)
				"surface_at": track.surface_at(p)
				"side_of_line": track.side_of_line(p)
				"line_point": track.line_point(p.x)
		print("  %-17s %.1f us/call" % [name, (Time.get_ticks_usec() - t) / float(points.size())])


static func _avg(values: Array) -> float:
	var total := 0.0
	for v in values:
		total += v
	return total / maxi(values.size(), 1)


static func _pct(values: Array, p: float) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[int((sorted.size() - 1) * p)]

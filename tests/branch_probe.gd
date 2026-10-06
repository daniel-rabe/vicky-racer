extends "res://tests/race_test.gd"
## Dev probe (not part of the suite): the race test on a boat course, printing the player's
## measure every frame while it is near a branch, to see where progress jumps.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/branch_probe.tscn -- --autopilot --track=boat_03 --setup=banana_boat

var _last := {}


func _physics_process(delta: float) -> void:
	super(delta)
	if not race or not race.manager.running:
		return
	var track: Track = race.track
	for r in race.racers:
		var car: Car = r["car"]
		var here := track.progress_of(car)
		var near := false
		for b in track.branch_lines.size():
			var d := fposmod(here - track.branch_entry(b) + 600.0, track.lap_length())
			if d < track.branch_exit(b) - track.branch_entry(b) + 1800.0:
				near = true
		if near:
			print("%-7s %7.0f  b=%d along=%6.0f dist=%5.0f  line=%7.0f line_d=%5.0f  pos=%s %s" % [r["name"], here, track.branch_of(car),
				track.branch_progress_of(car), track.distance_of(car), track.progress_at(car.global_position),
				track.distance_to_line(car.global_position), car.global_position.round(),
				"JUMP" if _last.has(car) and absf(here - _last[car]) > 200.0 and absf(here - _last[car]) < 20000.0 else ""])
		_last[car] = here

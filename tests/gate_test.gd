extends Node
## Headless test: a lap still counts when the car leaves the road at the finish line or the
## checkpoint and drives round the gate (the gates only span the road). The player's car is
## carried a lap and a bit along the line, well off the road to one side, past both gates.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/gate_test.tscn
## Exit code 0 = all passed.

const RACE_SCENE := preload("res://game/screens/race.tscn")
## Beyond the gates' ends (road, kerbs and a margin), but near enough to keep to this pass.
const SIDEWAYS := 360.0
const STEP := 20.0  # px a frame: 1200 px/s, about a car's top speed

var race: Node2D
var _player_laps := 0
var _gate_hits := 0
var _positions: Array = []
var _offset := 0.0
var _travel := -1.0  # < 0 until the race starts


func _enter_tree() -> void:
	EventSystem.RAC_lap_completed.connect(func(car: Node, _lap: int, _time: float) -> void:
		if car == _player_car():
			_player_laps += 1)
	EventSystem.RAC_positions_updated.connect(func(order: Array) -> void:
		for e: Dictionary in order:
			if e["is_player"]:
				_positions.append(e["position"]))
	EventSystem.UI_settings_requested.connect(func() -> void:
		EventSystem.UI_settings_changed.emit({"sound_volume": 0.0, "music_volume": 0.0, "fullscreen": false,
			"auto_accelerate": false, "steering_help": false, "difficulty": &"normal"}))
	EventSystem.PRO_state_requested.connect(func() -> void:
		EventSystem.PRO_state_changed.emit({"setups": [load("res://game/configs/setups/starter.tres")],
			"equipped": &"starter", "selected_track": &"track_01",
			"tracks": [{"config": load("res://game/configs/tracks/track_01.tres")}]}))
	EventSystem.RAC_race_started.connect(_on_started)


func _ready() -> void:
	race = RACE_SCENE.instantiate()
	add_child(race)
	race.track.finish_crossed.connect(func(car: Car) -> void:
		if car == _player_car():
			_gate_hits += 1)
	race.track.checkpoint_crossed.connect(func(car: Car) -> void:
		if car == _player_car():
			_gate_hits += 1)


func _player_car() -> Car:
	for r in race.racers:
		if r["is_player"]:
			return r["car"]
	return null


func _on_started() -> void:
	var car := _player_car()
	car.frozen = true  # carried by the test, not driven
	_offset = race.track.progress_of(car)
	_travel = 0.0


func _physics_process(_delta: float) -> void:
	if _travel < 0.0:
		return
	var track: Track = race.track
	var car := _player_car()
	_offset += STEP
	_travel += STEP
	car.global_position = track.line_point(_offset, SIDEWAYS)
	car.rotation = track.line_tangent(_offset).angle()
	if _travel >= track.lap_length() * 1.25:
		_travel = -1.0
		_report()


func _report() -> void:
	var failures: PackedStringArray = []
	var check := func(ok: bool, message: String) -> void:
		print(("  ok   " if ok else "  FAIL ") + message)
		if not ok:
			failures.append(message)
	check.call(_gate_hits == 0, "the car went round both gates (%d gate hits)" % _gate_hits)
	check.call(_player_laps == 1, "the lap counted all the same (%d laps)" % _player_laps)
	var r: Dictionary = race.racers.filter(func(x: Dictionary) -> bool: return x["is_player"])[0]
	check.call(r["progress"] > race.track.lap_length(), "progress is past one lap (%d px)" % r["progress"])
	check.call(not _positions.is_empty() and _positions[-1] == 1, "and the player leads (positions %s)" % [_positions])
	if failures.is_empty():
		print("ALL GATE TESTS PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)

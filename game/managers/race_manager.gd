class_name RaceManager
extends Node
## Runs one race (docs/DESIGN.md §6.2): the 3-2-1-GO countdown with cars held still, lap
## counting off the finish line (only after the mid-lap checkpoint), live positions, lap
## times, rubber-banding for the AI, and the finish.
##
## The race ends when the *player* finishes. Opponents still racing get a time estimated
## from their progress, so a child never waits on a race that is already over for them.

signal race_over

const COUNTDOWN_FROM := 3
## After the player crosses the line, the race keeps running this long before results.
const FINISH_HOLD_SECONDS := 2.5

var track: Track
var config: TrackConfig
## Rubber-band tuning (docs/DESIGN.md §8.3): an AI ahead of where it wants to be eases off,
## behind it pushes, and the weaker opponents want to be a little behind the player.
var difficulty: DifficultyConfig
var racers: Array[Dictionary] = []
var running := false
var race_time := 0.0

var _finish_offset := 0.0
var _player: Dictionary
var _order: Array[Dictionary] = []
var _ended := false


func start(race_track: Track, race_config: TrackConfig, race_racers: Array[Dictionary],
		race_difficulty: DifficultyConfig) -> void:
	track = race_track
	config = race_config
	difficulty = race_difficulty
	racers = race_racers
	_finish_offset = track.progress_at(track.get_node("FinishLine").global_position)
	for r in racers:
		r.merge({"laps": 0, "crossed_start": false, "checkpoint": false, "lap_start": 0.0,
			"best_lap": 0.0, "finished": false, "finish_time": 0.0, "progress": 0.0})
		if r["is_player"]:
			_player = r
	track.finish_crossed.connect(_on_finish_crossed)
	track.checkpoint_crossed.connect(func(car: Car) -> void: _racer(car)["checkpoint"] = true)
	_update_positions()
	_countdown()


func _countdown() -> void:
	for n in range(COUNTDOWN_FROM, 0, -1):
		EventSystem.RAC_countdown_tick.emit(n)
		await get_tree().create_timer(1.0, false).timeout
	EventSystem.RAC_countdown_tick.emit(0)
	for r in racers:
		r["car"].frozen = false
	running = true
	EventSystem.RAC_race_started.emit()


func _physics_process(delta: float) -> void:
	if not running:
		return
	race_time += delta
	_update_positions()
	_rubber_band()


func _racer(car: Car) -> Dictionary:
	for r in racers:
		if r["car"] == car:
			return r
	return {}


func _on_finish_crossed(car: Car) -> void:
	var r := _racer(car)
	if r.is_empty() or not running or r["finished"]:
		return
	if not r["crossed_start"]:
		# The grid is behind the line: the first crossing starts lap 1, it does not end one.
		r["crossed_start"] = true
		return
	if not r["checkpoint"]:
		return  # no lap without the mid-lap checkpoint: no reversing over the line, no shortcuts
	r["checkpoint"] = false
	r["laps"] += 1
	var lap_time: float = race_time - r["lap_start"]
	r["lap_start"] = race_time
	r["best_lap"] = lap_time if r["best_lap"] == 0.0 else minf(r["best_lap"], lap_time)
	EventSystem.RAC_lap_completed.emit(car, r["laps"], lap_time)
	if r["laps"] >= config.laps:
		r["finished"] = true
		r["finish_time"] = race_time
		if r == _player:
			_finish_race()


## Progress in px from the start of the race: negative while still behind the line on the grid.
func _progress(r: Dictionary) -> float:
	var length := track.lap_length()
	var rel := fposmod(track.progress_of(r["car"]) - _finish_offset, length)
	if not r["crossed_start"]:
		return rel - length
	return r["laps"] * length + rel


func _update_positions() -> void:
	for r in racers:
		r["progress"] = _progress(r)
	var order := racers.duplicate()
	order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["finished"] != b["finished"]:
			return a["finished"]
		if a["finished"]:
			return a["finish_time"] < b["finish_time"]
		return a["progress"] > b["progress"])
	# Compare by name: the dictionaries themselves change every frame (progress lives in them).
	var changed := order.size() != _order.size()
	for i in order.size():
		if changed or order[i]["name"] != _order[i]["name"]:
			changed = true
			break
	_order.assign(order)
	if changed:
		EventSystem.RAC_positions_updated.emit(_order.map(func(r: Dictionary) -> Dictionary:
			return {"name": r["name"], "is_player": r["is_player"], "colour": r["colour"],
				"position": _order.find(r) + 1, "lap": r["laps"]}))


func _rubber_band() -> void:
	for r in racers:
		if r.has("driver") and not r["is_player"]:
			var d := difficulty
			var wanted: float = minf(0.0, (r["driver"].skill - d.band_centre_skill) * d.hang_back_per_skill)
			var gap: float = r["progress"] - _player["progress"] - wanted
			var t := clampf(gap / d.band_distance, -1.0, 1.0)
			r["driver"].rubber_band = lerpf(1.0, d.ease_off, t) if t > 0.0 else lerpf(1.0, d.push, -t)


func position_of(r: Dictionary) -> int:
	return _order.find(r) + 1


func _finish_race() -> void:
	if _ended:
		return
	_ended = true
	await get_tree().create_timer(FINISH_HOLD_SECONDS, false).timeout
	running = false
	for r in racers:
		r["car"].frozen = true
	_update_positions_final()
	var results := []
	for i in _order.size():
		var r: Dictionary = _order[i]
		results.append({"name": r["name"], "body": r["body"], "is_player": r["is_player"],
			"position": i + 1, "time": r["finish_time"], "best_lap": r["best_lap"]})
	EventSystem.RAC_race_finished.emit(results, config.track_id)
	race_over.emit()


## Opponents still racing when the player finished get an estimated time: their average
## pace so far, carried over the distance they still had to go. Order follows those times.
func _update_positions_final() -> void:
	var total := config.laps * track.lap_length()
	for r in racers:
		if not r["finished"]:
			var progress := maxf(r["progress"], 1.0)
			var pace := progress / maxf(race_time, 0.1)
			r["finish_time"] = race_time + (total - progress) / maxf(pace, 1.0)
			r["finished"] = true
	_order.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["finish_time"] < b["finish_time"])

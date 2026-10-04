class_name CupManager
extends Node
## Runs tournament cups (docs/DESIGN.md §12): which cup is on, which race is next, the
## points and the standings, and the trophy at the end. Lives in the main.tscn shell next
## to GarageManager. GarageManager owns the save file: this sends it the progress after
## every race (CUP_progress_changed) and the trophy at the end (CUP_finished), and reads
## the saved progress and trophies back from PRO_state_changed.
##
## A cup's next cup opens only when it has been won — 1st in the final standings.
##
## Phases: none (no cup) -> ready (a race is next) -> racing (on the track) -> results
## (race over, standings to show) -> ready ... and after the last race -> done (podium).

const CUP_DIR := "res://game/configs/cups/"
const CUP_ORDER: Array[StringName] = [&"sunshine", &"snowflake"]
const TROPHY_FOR_PLACE: Array[StringName] = [&"gold", &"silver", &"bronze", &"ribbon"]
## Better trophies first; a cup remembers the best one ever won.
const TROPHY_RANK: Array[StringName] = [&"gold", &"silver", &"bronze", &"ribbon"]

var cups := {}  # id -> CupConfig
var phase := &"none"
var cup: CupConfig
var race_index := 0
var points := {}          # racer name -> points so far
var gained := {}          # racer name -> points from the last race
var bodies := {}          # racer name -> car sprite path, from the last race
var last_positions := {}  # racer name -> place in the last race (breaks ties)
var trophy := &""         # set when the cup is over
var _trophies := {}       # cup id -> best trophy, from the save
var _loaded := false


func _enter_tree() -> void:
	EventSystem.CUP_state_requested.connect(_publish)
	EventSystem.CUP_start_requested.connect(start)
	EventSystem.CUP_continue_requested.connect(continue_cup)
	EventSystem.RAC_race_finished.connect(_on_race_finished)
	EventSystem.UI_screen_requested.connect(_on_screen_requested)
	EventSystem.PRO_state_changed.connect(_on_garage_state)


func _ready() -> void:
	for id in CUP_ORDER:
		cups[id] = load(CUP_DIR + String(id) + ".tres")
	EventSystem.PRO_state_requested.emit()  # answered synchronously: saved progress, trophies


func is_unlocked(cup_id: StringName) -> bool:
	var i := CUP_ORDER.find(cup_id)
	return i == 0 or (i > 0 and _trophies.get(CUP_ORDER[i - 1]) == &"gold")


func current_track() -> TrackConfig:
	return cup.tracks[race_index] if cup and race_index < cup.tracks.size() else null


## Start a cup from its first race (a cup already running is given up).
func start(cup_id: StringName) -> void:
	if not cups.has(cup_id) or not is_unlocked(cup_id):
		return
	cup = cups[cup_id]
	race_index = 0
	points.clear()
	gained.clear()
	bodies.clear()
	last_positions.clear()
	trophy = &""
	_save_progress()
	phase = &"racing"
	EventSystem.UI_screen_requested.emit(&"race")


## On to the next race of the running cup — or to the podium if it is over.
func continue_cup() -> void:
	if phase == &"done":
		EventSystem.UI_screen_requested.emit(&"podium")
	elif cup:
		phase = &"racing"
		EventSystem.UI_screen_requested.emit(&"race")


## Racers in standings order: most points, ties to whoever did better in the last race.
func standings() -> Array:
	var rows := []
	for name: String in points:
		rows.append({"name": name, "points": points[name], "gained": gained.get(name, 0),
			"body": bodies.get(name, ""), "is_player": name == "YOU", "last": last_positions.get(name, 9)})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["points"] != b["points"]:
			return a["points"] > b["points"]
		return a["last"] < b["last"])
	for i in rows.size():
		rows[i]["position"] = i + 1
	return rows


func _on_race_finished(results: Array, _track_id: StringName) -> void:
	if phase != &"racing":
		return  # a single race, not part of the cup
	gained.clear()
	for entry: Dictionary in results:
		var name: String = entry["name"]
		var p := cup.points_for(int(entry["position"]))
		points[name] = points.get(name, 0) + p
		gained[name] = p
		bodies[name] = entry["body"]
		last_positions[name] = int(entry["position"])
	race_index += 1
	if race_index < cup.tracks.size():
		phase = &"results"
		_save_progress()
		return
	phase = &"done"
	var table := standings()
	var place := 4
	for row: Dictionary in table:
		if row["is_player"]:
			place = row["position"]
	trophy = TROPHY_FOR_PLACE[clampi(place - 1, 0, 3)]
	EventSystem.CUP_progress_changed.emit({})  # nothing left to resume
	EventSystem.CUP_finished.emit(cup.id, table, trophy)


func _on_screen_requested(screen: StringName) -> void:
	if phase == &"racing" and screen != &"race":
		phase = &"ready"  # left the race (pause menu): the cup waits for it
	elif phase == &"results" and screen in [&"garage", &"tracks", &"title"]:
		phase = &"ready"
	elif phase == &"done" and screen in [&"garage", &"tracks", &"title"]:
		_clear()


func _on_garage_state(state: Dictionary) -> void:
	_trophies = state.get("trophies", {})
	if _loaded:
		return
	_loaded = true
	var saved: Dictionary = state.get("cup_progress", {})
	if saved.is_empty() or not cups.has(StringName(saved.get("cup", ""))):
		return
	cup = cups[StringName(saved["cup"])]
	race_index = clampi(int(saved.get("race", 0)), 0, cup.tracks.size() - 1)
	points = saved.get("points", {})
	gained = saved.get("gained", {})
	bodies = saved.get("bodies", {})
	last_positions = saved.get("last", {})
	phase = &"ready"


func _save_progress() -> void:
	EventSystem.CUP_progress_changed.emit({"cup": String(cup.id), "race": race_index, "points": points,
		"gained": gained, "bodies": bodies, "last": last_positions})


func _clear() -> void:
	phase = &"none"
	cup = null
	race_index = 0
	points.clear()
	gained.clear()
	bodies.clear()
	last_positions.clear()
	trophy = &""


func _publish() -> void:
	EventSystem.CUP_state_changed.emit({
		"phase": phase,
		"cup": cup,
		"race_index": race_index,
		"track": current_track(),
		"standings": standings(),
		"trophy": trophy,
		"cups": CUP_ORDER.map(func(id: StringName) -> Dictionary:
			return {"config": cups[id], "unlocked": is_unlocked(id), "trophy": _trophies.get(id, &"")}),
	})

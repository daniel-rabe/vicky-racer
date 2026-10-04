class_name GarageManager
extends Node
## Owns the wallet, which setups are owned and equipped, best laps, and the summary of
## the last race. Lives in the main shell so it survives every screen change.
##
## Screens talk to it only through EventSystem: PRO_state_requested / PRO_buy_requested /
## PRO_equip_requested in, PRO_state_changed (the whole state) and feedback signals out.
## Every change is saved straight away.

const SETUP_DIR := "res://game/configs/setups/"
## Display order in the garage, six to a page; prices rise left to right, top to bottom.
const SETUP_ORDER: Array[StringName] = [&"starter", &"grippy", &"icecream", &"slider", &"rocket", &"kart",
	&"monster", &"bubble", &"police", &"banana", &"formula", &"dragon"]

## Track-select order. A track unlocks when the one before it has been finished — any place
## counts, so a child is never stuck behind a race they cannot win (docs/DESIGN.md §7.6).
const TRACK_ORDER: Array[StringName] = [&"track_01", &"track_02", &"track_03", &"track_04"]
const TRACK_DIR := "res://game/configs/tracks/"

@export var economy: EconomyConfig
@export var save_path := SaveGame.DEFAULT_PATH

var profile: SaveGame
var setups: Dictionary = {}  # id -> DriftSetup
var tracks: Dictionary = {}  # id -> TrackConfig
## What the results screen shows: results, coins breakdown, total awarded, new best lap.
var last_race := {}
## The cup just finished, for the podium: cup id, trophy, bonus coins.
var last_cup := {}
## &"race" or &"time_trial", for the next race (PICK A RACE's switch). Not saved.
var race_mode: StringName = &"race"


func _enter_tree() -> void:
	EventSystem.PRO_state_requested.connect(_publish_state)
	EventSystem.PRO_buy_requested.connect(buy)
	EventSystem.PRO_equip_requested.connect(equip)
	EventSystem.PRO_paint_requested.connect(repaint)
	EventSystem.PRO_track_select_requested.connect(select_track)
	EventSystem.CUP_progress_changed.connect(func(progress: Dictionary) -> void:
		profile.cup_progress = progress
		profile.save_to(save_path))
	EventSystem.CUP_finished.connect(_on_cup_finished)
	EventSystem.PRO_sticker_earned.connect(func(id: StringName) -> void:
		if id not in profile.stickers:
			profile.stickers.append(id)
			_commit())
	EventSystem.RAC_race_finished.connect(_on_race_finished)
	EventSystem.RAC_time_trial_finished.connect(_on_time_trial_finished)
	EventSystem.PRO_race_mode_requested.connect(func(mode: StringName) -> void:
		if mode in [&"race", &"time_trial"]:
			race_mode = mode
			_publish_state())


func _ready() -> void:
	for id in SETUP_ORDER:
		setups[id] = load(SETUP_DIR + String(id) + ".tres")
	for id in TRACK_ORDER:
		tracks[id] = load(TRACK_DIR + String(id) + ".tres")
	profile = SaveGame.load_from(save_path, economy.starting_coins)
	if not is_unlocked(profile.selected_track):
		profile.selected_track = TRACK_ORDER[0]


func owns(id: StringName) -> bool:
	return id in profile.owned_setups


func can_afford(id: StringName) -> bool:
	return profile.coins >= setups[id].price


func equipped_setup() -> DriftSetup:
	return setups[profile.equipped_setup]


func buy(id: StringName) -> void:
	if not setups.has(id) or owns(id):
		return
	if not can_afford(id):
		EventSystem.PRO_purchase_refused.emit(id, &"not_enough_coins")
		return
	profile.coins -= setups[id].price
	profile.owned_setups.append(id)
	EventSystem.PRO_setup_purchased.emit(id)
	EventSystem.PRO_coins_changed.emit(profile.coins)
	# A child who just bought something wants to drive it: equip straight away.
	equip(id)


func equip(id: StringName) -> void:
	if not owns(id):
		return
	profile.equipped_setup = id
	EventSystem.PRO_setup_equipped.emit(id)
	_commit()


func is_unlocked(track_id: StringName) -> bool:
	var i := TRACK_ORDER.find(track_id)
	return i == 0 or (i > 0 and TRACK_ORDER[i - 1] in profile.completed_tracks)


func selected_track() -> TrackConfig:
	return tracks[profile.selected_track]


## Choose the track for the next race; refused (PRO_track_locked) while it is locked.
func select_track(track_id: StringName) -> void:
	if not tracks.has(track_id):
		return
	if not is_unlocked(track_id):
		EventSystem.PRO_track_locked.emit(track_id)
		return
	profile.selected_track = track_id
	_commit()


## Paint an owned car the next colour in the palette (free, any number of times).
func repaint(id: StringName) -> void:
	if not owns(id):
		return
	var colour := Paint.next(profile.paint.get(id, Paint.ORIGINAL))
	if colour == Paint.ORIGINAL:
		profile.paint.erase(id)
	else:
		profile.paint[id] = colour
	EventSystem.PRO_setup_painted.emit(id, colour)
	_commit()


## The end of a cup: the trophy's bonus coins, and the trophy kept if it beats the best.
func _on_cup_finished(cup_id: StringName, _standings: Array, trophy: StringName) -> void:
	var bonus := int(economy.cup_bonus.get(trophy, 0))
	profile.coins += bonus
	var best: StringName = profile.trophies.get(cup_id, &"")
	if best == &"" or CupManager.TROPHY_RANK.find(trophy) < CupManager.TROPHY_RANK.find(best):
		profile.trophies[cup_id] = trophy
	profile.cup_progress = {}
	last_cup = {"cup": cup_id, "trophy": trophy, "bonus": bonus}
	EventSystem.PRO_coins_changed.emit(profile.coins)
	_commit()


## Pays for a race. With two players both places are paid into the one family garage
## ("place_p1", "place_p2" in the breakdown) — racing together still moves the save on —
## and a new track's bonus is paid once.
func _on_race_finished(results: Array, track_id: StringName) -> void:
	var players := results.filter(func(entry: Dictionary) -> bool: return entry.get("is_player", false))
	if players.is_empty():
		return
	var first_finish := track_id not in profile.completed_tracks
	var breakdown := {}
	var best := 0.0
	for entry: Dictionary in players:
		var key := "place" if players.size() == 1 else "place_p%d" % int(entry.get("player", 1))
		breakdown[key] = economy.payout(int(entry["position"]), false)["place"]
		var lap := float(entry.get("best_lap", 0.0))
		if lap > 0.0 and (best == 0.0 or lap < best):
			best = lap
	if first_finish:
		breakdown["first_finish"] = economy.first_finish_bonus
	var amount := 0
	for line in breakdown.values():
		amount += int(line)
	profile.coins += amount
	if first_finish:
		profile.completed_tracks.append(track_id)
	var new_best: bool = best > 0.0 and (not profile.best_laps.has(track_id) or best < float(profile.best_laps[track_id]))
	if new_best:
		profile.best_laps[track_id] = best
	last_race = {"results": results, "track_id": track_id, "breakdown": breakdown,
		"amount": amount, "new_best_lap": new_best}
	EventSystem.PRO_coins_awarded.emit(amount, breakdown)
	EventSystem.PRO_coins_changed.emit(profile.coins)
	_commit()


## Where the record ghosts are kept: beside the save file, one file per track, so a test's
## own save keeps its own ghosts.
func ghost_dir() -> String:
	return save_path.get_basename() + "_ghosts"


## A time trial pays nothing (nobody else raced) but keeps records: the best lap per track
## and per car, and the record lap's ghost.
func _on_time_trial_finished(track_id: StringName, setup_id: StringName, lap_times: Array, ghost: GhostLap) -> void:
	var best := 0.0
	for lap in lap_times:
		if float(lap) > 0.0 and (best == 0.0 or float(lap) < best):
			best = float(lap)
	var entry: Dictionary = profile.trials.get(track_id, {"best": 0.0, "setup": setup_id, "cars": {}})
	var record_before := float(entry["best"])
	var car_before := float(entry["cars"].get(setup_id, 0.0))
	var new_record := best > 0.0 and (record_before == 0.0 or best < record_before)
	var new_car_best := best > 0.0 and (car_before == 0.0 or best < car_before)
	if new_car_best:
		entry["cars"][setup_id] = best
	if new_record:
		entry["best"] = best
		entry["setup"] = setup_id
		if ghost:
			ghost.save_file(ghost_dir().path_join("%s.ghost" % track_id))
	if new_record or new_car_best:
		profile.trials[track_id] = entry
	last_race = {"mode": &"time_trial", "track_id": track_id, "setup_id": setup_id, "lap_times": lap_times,
		"best": best, "record_before": record_before, "new_record": new_record,
		"car_best_before": car_before, "new_car_best": new_car_best}
	_commit()


func _commit() -> void:
	profile.save_to(save_path)
	_publish_state()


func _publish_state() -> void:
	EventSystem.PRO_state_changed.emit({
		"coins": profile.coins,
		"owned": profile.owned_setups.duplicate(),
		"equipped": profile.equipped_setup,
		"paint": profile.paint.duplicate(),
		"selected_track": profile.selected_track,
		"cup_progress": profile.cup_progress.duplicate(true),
		"trophies": profile.trophies.duplicate(),
		"stickers": profile.stickers.duplicate(),
		"last_cup": last_cup,
		"tracks": TRACK_ORDER.map(func(id: StringName) -> Dictionary:
			return {"config": tracks[id], "unlocked": is_unlocked(id), "best_lap": profile.best_laps.get(id, 0.0),
				"completed": id in profile.completed_tracks}),
		"setups": SETUP_ORDER.map(func(id: StringName) -> DriftSetup: return setups[id]),
		"best_laps": profile.best_laps.duplicate(),
		"last_race": last_race,
		"race_mode": race_mode,
		"ghost_dir": ghost_dir(),
		"trials": profile.trials.duplicate(true),
	})

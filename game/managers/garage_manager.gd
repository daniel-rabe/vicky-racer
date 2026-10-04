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

@export var economy: EconomyConfig
@export var save_path := SaveGame.DEFAULT_PATH

var profile: SaveGame
var setups: Dictionary = {}  # id -> DriftSetup
## What the results screen shows: results, coins breakdown, total awarded, new best lap.
var last_race := {}


func _enter_tree() -> void:
	EventSystem.PRO_state_requested.connect(_publish_state)
	EventSystem.PRO_buy_requested.connect(buy)
	EventSystem.PRO_equip_requested.connect(equip)
	EventSystem.PRO_paint_requested.connect(repaint)
	EventSystem.RAC_race_finished.connect(_on_race_finished)


func _ready() -> void:
	for id in SETUP_ORDER:
		setups[id] = load(SETUP_DIR + String(id) + ".tres")
	profile = SaveGame.load_from(save_path, economy.starting_coins)


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


func _on_race_finished(results: Array, track_id: StringName) -> void:
	var player: Dictionary = {}
	for entry: Dictionary in results:
		if entry.get("is_player", false):
			player = entry
	if player.is_empty():
		return
	var first_finish := track_id not in profile.completed_tracks
	var breakdown := economy.payout(int(player["position"]), first_finish)
	var amount := 0
	for line in breakdown.values():
		amount += int(line)
	profile.coins += amount
	if first_finish:
		profile.completed_tracks.append(track_id)
	var best := float(player.get("best_lap", 0.0))
	var new_best: bool = best > 0.0 and (not profile.best_laps.has(track_id) or best < float(profile.best_laps[track_id]))
	if new_best:
		profile.best_laps[track_id] = best
	last_race = {"results": results, "track_id": track_id, "breakdown": breakdown,
		"amount": amount, "new_best_lap": new_best}
	EventSystem.PRO_coins_awarded.emit(amount, breakdown)
	EventSystem.PRO_coins_changed.emit(profile.coins)
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
		"setups": SETUP_ORDER.map(func(id: StringName) -> DriftSetup: return setups[id]),
		"best_laps": profile.best_laps.duplicate(),
		"last_race": last_race,
	})

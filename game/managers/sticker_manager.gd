class_name StickerManager
extends Node
## Decides when a sticker is earned (docs/DESIGN.md §14) and announces it with
## PRO_sticker_earned. Lives in the main.tscn shell next to GarageManager, which owns the
## save: it records each sticker and sends the earned set back in PRO_state_changed. A
## sticker can never be earned twice, and never lost.
##
## Everything here is about the player's own car (the one with a PlayerMarker) and only while
## a race is on, so the attract mode and the test field never award anything.

const STICKER_DIR := "res://game/configs/stickers/"
## Book order.
const ORDER: Array[StringName] = [&"drift", &"long_drift", &"first_win", &"clean_lap", &"coins",
	&"every_track", &"all_cars", &"first_splash", &"splash_cup", &"first_flight", &"comet_cup"]
## A race finished in a boat, or in a spaceship (docs/DESIGN.md §20, §24), and a cup won outright
## in one, earn these.
const FIRST_RACE_IN := {&"boat": &"first_splash", &"ship": &"first_flight"}
const CUP_WON := {&"splash": &"splash_cup", &"comet": &"comet_cup"}
## A drift at least this long earns the long-drift sticker.
const LONG_DRIFT_SECONDS := 3.0
## Coins from a single race, the cup bonus included. A win alone pays 100 (EconomyConfig), so
## it takes a win on a new track, or a cup won or placed 2nd at the end.
const RICH_RACE_COINS := 200

@export var economy: EconomyConfig

var stickers := {}  # id -> StickerConfig
var earned: Array[StringName] = []
var _racing := false
var _wall_hit_this_lap := false
var _race_coins := 0
## What the player is racing in this race (&"car", &"boat" or &"ship"), seen on their car.
var _player_kind := &"car"


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_garage_state)
	EventSystem.RAC_race_started.connect(func() -> void:
		_racing = true
		_wall_hit_this_lap = false
		_race_coins = 0
		_player_kind = _kind_of_player())
	EventSystem.RAC_race_finished.connect(_on_race_finished)
	EventSystem.UI_screen_requested.connect(func(_screen: StringName) -> void: _racing = false)
	EventSystem.CAR_drift_started.connect(func(car: Node) -> void:
		if _racing and _is_player(car):
			earn(&"drift"))
	EventSystem.CAR_drift_ended.connect(func(car: Node, duration: float) -> void:
		if _racing and _is_player(car) and duration >= LONG_DRIFT_SECONDS:
			earn(&"long_drift"))
	EventSystem.CAR_wall_hit.connect(func(car: Node, _impact: float) -> void:
		if _is_player(car):
			_wall_hit_this_lap = true)
	EventSystem.RAC_lap_completed.connect(_on_lap_completed)
	EventSystem.PRO_coins_awarded.connect(func(amount: int, _breakdown: Dictionary) -> void:
		_add_race_coins(amount))
	EventSystem.CUP_finished.connect(func(cup: StringName, _standings: Array, trophy: StringName) -> void:
		_add_race_coins(int(economy.cup_bonus.get(trophy, 0)) if economy else 0)
		if trophy == &"gold" and CUP_WON.has(cup):
			earn(CUP_WON[cup]))


func _ready() -> void:
	for id in ORDER:
		stickers[id] = load(STICKER_DIR + String(id) + ".tres")
	EventSystem.PRO_state_requested.emit()  # answered synchronously: the stickers in the save


func has(id: StringName) -> bool:
	return id in earned


## Award a sticker once. Anything already in the book is ignored, so every trigger can just
## call this whenever its condition holds.
func earn(id: StringName) -> void:
	if not stickers.has(id) or has(id):
		return
	earned.append(id)
	EventSystem.PRO_sticker_earned.emit(id)


static func _is_player(car: Node) -> bool:
	return is_instance_valid(car) and car.has_node(^"PlayerMarker")


## What the player's car is: a Ship is a Boat is a Car, so the most special first.
func _kind_of_player() -> StringName:
	for car in get_tree().get_nodes_in_group(&"cars"):
		if _is_player(car):
			return &"ship" if car is Ship else (&"boat" if car is Boat else &"car")
	return &"car"


func _on_lap_completed(racer: Node, _lap: int, _lap_time: float) -> void:
	if not _racing or not _is_player(racer):
		return
	if not _wall_hit_this_lap:
		earn(&"clean_lap")
	_wall_hit_this_lap = false


func _on_race_finished(results: Array, _track_id: StringName) -> void:
	_racing = false
	for entry: Dictionary in results:
		if entry.get("is_player", false) and int(entry["position"]) == 1:
			earn(&"first_win")
	if FIRST_RACE_IN.has(_player_kind) and results.any(func(entry: Dictionary) -> bool: return entry.get("is_player", false)):
		earn(FIRST_RACE_IN[_player_kind])


func _add_race_coins(amount: int) -> void:
	_race_coins += amount
	if _race_coins >= RICH_RACE_COINS:
		earn(&"coins")


## The garage state carries what is already earned, what is owned and which tracks are done.
func _on_garage_state(state: Dictionary) -> void:
	for id: StringName in state.get("stickers", []):
		if id not in earned:
			earned.append(id)
	var setups: Array = state.get("car_setups", state.get("setups", []))
	var owned: Array = state.get("owned", [])
	if not setups.is_empty() and setups.all(func(s: DriftSetup) -> bool: return s.id in owned):
		earn(&"all_cars")
	var tracks: Array = state.get("car_tracks", state.get("tracks", []))
	if not tracks.is_empty() and tracks.all(func(t: Dictionary) -> bool: return t["completed"]):
		earn(&"every_track")
	# A cup won before its sticker existed (the Splash Cup, before Phase 22) still earns it.
	var trophies: Dictionary = state.get("trophies", {})
	for cup: StringName in CUP_WON:
		if trophies.get(cup) == &"gold":
			earn(CUP_WON[cup])

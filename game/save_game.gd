class_name SaveGame
extends RefCounted
## The player's profile and how it reaches disk: a ConfigFile at user://vicky_racer.cfg
## (schema in docs/DESIGN.md §9.2).
##
## Loading is defensive by design. A missing, unreadable or unknown-version file gives a
## fresh profile instead of an error — a broken save must never stand between a child and
## the game. An unreadable file is kept as .bak rather than silently overwritten.

const DEFAULT_PATH := "user://vicky_racer.cfg"
## 2 added [paint]. 3: the tracks were rebuilt longer (with bridges), so best laps saved
## before then are dropped — they were set on different tracks. Older files otherwise load
## as they are and are written back as the current version.
## 4 added the boats (docs/DESIGN.md §20): the equipped boat and the selected boat course;
## older files load with the Speedboat owned and the first course selected.
const SCHEMA_VERSION := 4
const READABLE_VERSIONS: Array[int] = [1, 2, 3, 4]
## Below this version, saved best laps belong to the old, shorter tracks.
const TRACKS_REBUILT_VERSION := 3
const STARTER_SETUP := &"starter"
const STARTER_BOAT := &"speedboat"
const FIRST_COURSE := &"boat_01"

var coins := 0
## Cars and boats both: their ids never clash (the boat is &"banana_boat", the car &"banana").
var owned_setups: Array[StringName] = [STARTER_SETUP, STARTER_BOAT]
var equipped_setup: StringName = STARTER_SETUP
var equipped_boat: StringName = STARTER_BOAT
## The boat course the next boat race is on.
var selected_course: StringName = FIRST_COURSE
## track id -> best lap in seconds
var best_laps := {}
var completed_tracks: Array[StringName] = []
## setup id -> paint colour (Paint.COLOURS); a car with no entry has its original paint.
var paint := {}
## The track the next race is on (track select). Optional in the file: older saves
## without it start on the first track.
var selected_track: StringName = &"track_01"
## A cup in progress, as CupManager sent it ({} = none), so closing the game mid-cup loses
## nothing; and the best trophy won per cup (cup id -> &"gold" / &"silver" / ...).
## Both optional in the file.
var cup_progress := {}
var trophies := {}
## Stickers in the book, in the order they were earned. Optional in the file; never shrinks.
var stickers: Array[StringName] = []
## Time-trial records (docs/DESIGN.md §16): track id -> {"best": seconds, "setup": the car that
## set it, "cars": {setup id: that car's best}}. The record's ghost lives in its own file
## (GarageManager.ghost_path). Optional in the file.
var trials := {}


static func fresh(starting_coins := 0) -> SaveGame:
	var profile := SaveGame.new()
	profile.coins = starting_coins
	return profile


static func load_from(path := DEFAULT_PATH, starting_coins := 0) -> SaveGame:
	if not FileAccess.file_exists(path):
		return fresh(starting_coins)
	var file := ConfigFile.new()
	if file.load(path) != OK:
		_keep_unreadable(path)
		return fresh(starting_coins)
	if int(file.get_value("profile", "schema_version", -1)) not in READABLE_VERSIONS:
		_keep_unreadable(path)
		return fresh(starting_coins)

	var profile := SaveGame.new()
	profile.coins = maxi(0, int(file.get_value("profile", "coins", 0)))
	profile.owned_setups = _string_names(file.get_value("profile", "owned_setups", []))
	if STARTER_SETUP not in profile.owned_setups:
		profile.owned_setups.push_front(STARTER_SETUP)
	if STARTER_BOAT not in profile.owned_setups:
		profile.owned_setups.append(STARTER_BOAT)
	var equipped := StringName(str(file.get_value("profile", "equipped_setup", STARTER_SETUP)))
	profile.equipped_setup = equipped if equipped in profile.owned_setups else STARTER_SETUP
	var boat := StringName(str(file.get_value("profile", "equipped_boat", STARTER_BOAT)))
	profile.equipped_boat = boat if boat in profile.owned_setups else STARTER_BOAT
	profile.selected_course = StringName(str(file.get_value("profile", "selected_course", FIRST_COURSE)))
	profile.completed_tracks = _string_names(file.get_value("profile", "completed_tracks", []))
	profile.selected_track = StringName(str(file.get_value("profile", "selected_track", "track_01")))
	var progress: Variant = file.get_value("cup", "progress", {})
	profile.cup_progress = progress if progress is Dictionary else {}
	if file.has_section("trophies"):
		for cup in file.get_section_keys("trophies"):
			var trophy := StringName(str(file.get_value("trophies", cup, "")))
			if trophy in [&"gold", &"silver", &"bronze", &"ribbon"]:
				profile.trophies[StringName(cup)] = trophy
	profile.stickers = _string_names(file.get_value("stickers", "earned", []))
	if file.has_section("time_trial"):
		for track in file.get_section_keys("time_trial"):
			var entry := _trial(file.get_value("time_trial", track, {}))
			if not entry.is_empty():
				profile.trials[StringName(track)] = entry
	if file.has_section("paint"):  # absent in version 1 files
		for id in file.get_section_keys("paint"):
			var colour := StringName(str(file.get_value("paint", id, "")))
			if colour in Paint.COLOURS and colour != Paint.ORIGINAL:
				profile.paint[StringName(id)] = colour
	var version := int(file.get_value("profile", "schema_version", SCHEMA_VERSION))
	if file.has_section("best_laps") and version >= TRACKS_REBUILT_VERSION:
		for track in file.get_section_keys("best_laps"):
			var seconds := float(file.get_value("best_laps", track, 0.0))
			if seconds > 0.0:
				profile.best_laps[StringName(track)] = seconds
	return profile


func save_to(path := DEFAULT_PATH) -> Error:
	var file := ConfigFile.new()
	file.set_value("profile", "schema_version", SCHEMA_VERSION)
	file.set_value("profile", "coins", coins)
	file.set_value("profile", "owned_setups", PackedStringArray(owned_setups))
	file.set_value("profile", "equipped_setup", String(equipped_setup))
	file.set_value("profile", "completed_tracks", PackedStringArray(completed_tracks))
	file.set_value("profile", "selected_track", String(selected_track))
	file.set_value("profile", "equipped_boat", String(equipped_boat))
	file.set_value("profile", "selected_course", String(selected_course))
	for track in best_laps:
		file.set_value("best_laps", String(track), best_laps[track])
	for id in paint:
		file.set_value("paint", String(id), String(paint[id]))
	if not cup_progress.is_empty():
		file.set_value("cup", "progress", cup_progress)
	for cup in trophies:
		file.set_value("trophies", String(cup), String(trophies[cup]))
	if not stickers.is_empty():
		file.set_value("stickers", "earned", PackedStringArray(stickers))
	for track in trials:
		file.set_value("time_trial", String(track), trials[track])
	return file.save(path)


static func _string_names(value: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for item in value:
			var id := StringName(str(item))
			if id not in out:
				out.append(id)
	return out


## One track's time-trial entry, cleaned: {} unless it has a positive best.
static func _trial(value: Variant) -> Dictionary:
	if not value is Dictionary or float(value.get("best", 0.0)) <= 0.0:
		return {}
	var cars := {}
	var raw: Variant = value.get("cars", {})
	if raw is Dictionary:
		for id in raw:
			if float(raw[id]) > 0.0:
				cars[StringName(str(id))] = float(raw[id])
	return {"best": float(value["best"]), "setup": StringName(str(value.get("setup", ""))), "cars": cars}


static func _keep_unreadable(path: String) -> void:
	DirAccess.rename_absolute(path, path + ".bak")

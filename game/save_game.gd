class_name SaveGame
extends RefCounted
## The player's profile and how it reaches disk: a ConfigFile at user://vicky_racer.cfg
## (schema in docs/DESIGN.md §9.2).
##
## Loading is defensive by design. A missing, unreadable or unknown-version file gives a
## fresh profile instead of an error — a broken save must never stand between a child and
## the game. An unreadable file is kept as .bak rather than silently overwritten.

const DEFAULT_PATH := "user://vicky_racer.cfg"
## 2 added [paint]. Version 1 files load as they are (no paint yet) and are written back as 2.
const SCHEMA_VERSION := 2
const READABLE_VERSIONS: Array[int] = [1, 2]
const STARTER_SETUP := &"starter"

var coins := 0
var owned_setups: Array[StringName] = [STARTER_SETUP]
var equipped_setup: StringName = STARTER_SETUP
## track id -> best lap in seconds
var best_laps := {}
var completed_tracks: Array[StringName] = []
## setup id -> paint colour (Paint.COLOURS); a car with no entry has its original paint.
var paint := {}
## The track the next race is on (track select). Optional in the file: older saves
## without it start on the first track.
var selected_track: StringName = &"track_01"


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
	var equipped := StringName(str(file.get_value("profile", "equipped_setup", STARTER_SETUP)))
	profile.equipped_setup = equipped if equipped in profile.owned_setups else STARTER_SETUP
	profile.completed_tracks = _string_names(file.get_value("profile", "completed_tracks", []))
	profile.selected_track = StringName(str(file.get_value("profile", "selected_track", "track_01")))
	if file.has_section("paint"):  # absent in version 1 files
		for id in file.get_section_keys("paint"):
			var colour := StringName(str(file.get_value("paint", id, "")))
			if colour in Paint.COLOURS and colour != Paint.ORIGINAL:
				profile.paint[StringName(id)] = colour
	if file.has_section("best_laps"):
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
	for track in best_laps:
		file.set_value("best_laps", String(track), best_laps[track])
	for id in paint:
		file.set_value("paint", String(id), String(paint[id]))
	return file.save(path)


static func _string_names(value: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if value is Array or value is PackedStringArray:
		for item in value:
			var id := StringName(str(item))
			if id not in out:
				out.append(id)
	return out


static func _keep_unreadable(path: String) -> void:
	DirAccess.rename_absolute(path, path + ".bak")

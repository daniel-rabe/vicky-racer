class_name Settings
extends RefCounted
## Machine and player settings (docs/DESIGN.md §10.1): sound and music volume, fullscreen, the two
## driving assists and how fast the opponents are. A ConfigFile at
## user://vicky_settings.cfg, separate from the save game: settings belong to the computer
## and the person at it, progress belongs to the child, and neither should be able to
## break the other.
##
## Loads defensively like SaveGame: anything missing, unreadable or out of range falls back
## to its default.

const DEFAULT_PATH := "user://vicky_settings.cfg"
const DIFFICULTIES: Array[StringName] = [&"easy", &"normal", &"fast"]
## Volume moves in steps of this much, so a gamepad reaches every value in a few presses.
const VOLUME_STEP := 0.1

var sound_volume := 0.8
var music_volume := 0.6
var fullscreen := false
var auto_accelerate := false
var steering_help := false
var difficulty: StringName = &"normal"
## Where the window was, windowed: position and size, so the game opens where it was left.
## Empty until the window has been moved or closed once; not shown on the settings screen.
var window_rect := Rect2i()
## The smallest window remembered: anything smaller is a mistake, not a choice.
const MIN_WINDOW := Vector2i(640, 360)


static func load_from(path := DEFAULT_PATH) -> Settings:
	var settings := Settings.new()
	var file := ConfigFile.new()
	if not FileAccess.file_exists(path) or file.load(path) != OK:
		return settings
	for key in settings.to_dict():
		if file.has_section_key("settings", key):
			settings.set_value(StringName(key), file.get_value("settings", key))
	return settings


func save_to(path := DEFAULT_PATH) -> Error:
	var file := ConfigFile.new()
	var values := to_dict()
	for key in values:
		var value: Variant = values[key]
		file.set_value("settings", key, String(value) if value is StringName else value)
	return file.save(path)


func to_dict() -> Dictionary:
	return {"sound_volume": sound_volume, "music_volume": music_volume, "fullscreen": fullscreen, "auto_accelerate": auto_accelerate,
		"steering_help": steering_help, "difficulty": difficulty, "window_rect": window_rect}


## Set one value, validated. Returns false (and changes nothing) for an unknown key or a
## value of the wrong kind, so a hand-edited or old file can never put nonsense in.
func set_value(key: StringName, value: Variant) -> bool:
	match key:
		&"sound_volume", &"music_volume":
			if not (value is float or value is int):
				return false
			set(key, snappedf(clampf(float(value), 0.0, 1.0), VOLUME_STEP))
		&"fullscreen", &"auto_accelerate", &"steering_help":
			if not value is bool:
				return false
			set(key, value)
		&"difficulty":
			var id := StringName(str(value))
			if id not in DIFFICULTIES:
				return false
			difficulty = id
		&"window_rect":
			if not value is Rect2i or (value != Rect2i() and (value.size.x < MIN_WINDOW.x or value.size.y < MIN_WINDOW.y)):
				return false
			window_rect = value
		_:
			return false
	return true

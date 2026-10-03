class_name DifficultyConfig
extends Resource
## How hard the opponents push (docs/DESIGN.md §8.3), chosen on the settings screen as
## OPPONENTS: EASY / NORMAL / FAST. Shifts the opponents' skill and retunes the rubber band;
## normal.tres is the tuning the balance pass settled on.

@export var id: StringName
@export var display_name := ""
## Added to every opponent's skill from the TrackConfig, then clamped to 0–1.
@export_range(-1.0, 1.0) var skill_offset := 0.0

@export_group("Rubber band")
## An AI this far ahead of where it wants to be eases to ease_off of its pace; as far
## behind, it pushes to push (and may pass its own top speed by as much).
@export var band_distance := 1500.0
@export var ease_off := 0.6
@export var push := 1.12
## Opponents with less skill than this hang back hang_back_per_skill px per point of
## skill below it, leaving room on the podium.
@export var band_centre_skill := 0.85
@export var hang_back_per_skill := 5000.0


static func named(difficulty_id: StringName) -> DifficultyConfig:
	var path := "res://game/configs/difficulty/%s.tres" % difficulty_id
	if not ResourceLoader.exists(path):
		path = "res://game/configs/difficulty/normal.tres"
	return load(path)

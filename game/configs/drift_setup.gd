class_name DriftSetup
extends Resource
## What the garage sells: a set of multipliers over a CarConfig. Each setup is a
## different trade rather than a strict upgrade (docs/DESIGN.md §4.2).

@export var id: StringName
@export var display_name := ""
@export var card_art: Texture2D
## Coins; 0 means owned from the start.
@export var price := 0

@export_group("Multipliers")
@export var lateral_grip_mult := 1.0
@export var handbrake_grip_mult := 1.0
@export var engine_power_mult := 1.0
@export var max_speed_mult := 1.0
@export var steer_rate_mult := 1.0

@export_group("Garage bars")
## Authored, not computed: they describe how the setup *feels*, 0–1.
@export_range(0.0, 1.0) var bar_grip := 0.5
@export_range(0.0, 1.0) var bar_slide := 0.5
@export_range(0.0, 1.0) var bar_speed := 0.5

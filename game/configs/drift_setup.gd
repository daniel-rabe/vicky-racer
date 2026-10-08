class_name DriftSetup
extends Resource
## What the garage sells — one car: a set of multipliers over a CarConfig plus how the car
## looks and sounds. Each car is a different trade rather than a strict upgrade
## (docs/DESIGN.md §4.2).

@export var id: StringName
## &"car", &"boat" or &"ship" (docs/DESIGN.md §20, §23): which garage sells it and which races it
## drives in.
@export var kind := &"car"
@export var display_name := ""
@export var card_art: Texture2D
## What the player's car looks like with this setup equipped (128 x 72, facing +X).
@export var body: Texture2D
## Coins; 0 means owned from the start.
@export var price := 0

@export_group("Multipliers")
@export var lateral_grip_mult := 1.0
@export var handbrake_grip_mult := 1.0
@export var engine_power_mult := 1.0
@export var max_speed_mult := 1.0
@export var steer_rate_mult := 1.0
## Scales how much grass and sand slow the car and loosen its grip (CarConfig.offroad_penalty).
@export var offroad_mult := 1.0

@export_group("Look and sound")
## Tyre marks while drifting (SkidMarks) and the puffs from the wheels (CarEffects).
@export var skid_colour := Color(0.11, 0.11, 0.13, 0.4)
@export var smoke_colour := Color(0.93, 0.93, 0.91)
## Engine loop pitch, x the speed-based pitch: a big truck rumbles lower, a bubble car higher.
@export var engine_pitch := 1.0
## Played on the horn button; null = the standard toy horn.
@export var horn: AudioStream
## Red and blue lights flash on the roof while drifting (the Police Car).
@export var siren := false
## The engine loop; null = the toy car engine. Boats have motors, a jet and a fan.
@export var engine_sound: AudioStream
## A hovercraft rides over shallows and banks at full speed (Boat).
@export var ignores_land := false

@export_group("Garage bars")
## Authored, not computed: they describe how the setup *feels*, 0–1.
@export_range(0.0, 1.0) var bar_grip := 0.5
@export_range(0.0, 1.0) var bar_slide := 0.5
@export_range(0.0, 1.0) var bar_speed := 0.5

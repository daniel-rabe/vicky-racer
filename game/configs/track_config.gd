class_name TrackConfig
extends Resource
## One race: which track, how many laps, where the player starts, and who they race.
## Adding a track or changing difficulty is data, not code (docs/DESIGN.md §8).

@export var track_id := &"track_01"
@export var track_scene: PackedScene
@export var laps := 3
## Grid slot for the player, 1 = front. Starting third gives something to chase.
@export var player_slot := 3

@export_group("Opponents")
## One entry per AI car, in the order they fill the free grid slots from the front.
@export var opponent_names: PackedStringArray = ["BLUE", "YELLOW", "GREEN"]
## The car each opponent drives (handling and look) and the paint it wears. The paint
## matches its colour, so the minimap and results stay readable.
@export var opponent_setups: Array[DriftSetup] = []
@export var opponent_paints: Array[StringName] = []
@export var opponent_colours: PackedColorArray = []
## 0-1 each; see AIDriver.skill.
@export var opponent_skills: PackedFloat32Array = [0.85, 0.7, 0.55]

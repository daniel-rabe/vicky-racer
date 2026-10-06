class_name CupConfig
extends Resource
## One tournament cup (docs/DESIGN.md §12): a few races in a row with points, standings
## and a trophy at the end. Each race uses its track's own TrackConfig (laps, opponents).

@export var id: StringName
@export var display_name := ""
@export var icon: Texture2D
## &"car" or &"boat" (docs/DESIGN.md §20): which PICK A RACE shows it, and what it is raced in.
@export var vehicle_kind := &"car"
@export var tracks: Array[TrackConfig] = []
## Points by finishing position, index 0 = 1st. Never zero: a child always scores.
@export var points: Array[int] = [10, 7, 5, 3]


func points_for(position: int) -> int:
	return points[clampi(position - 1, 0, points.size() - 1)]

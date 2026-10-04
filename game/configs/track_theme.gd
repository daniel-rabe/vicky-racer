class_name TrackTheme
extends Resource
## How a track looks and what its ground is (docs/DESIGN.md §7.5): the ground tiles, which
## surface is everywhere off the road and which one the painted patches are, the road and
## kerb textures, and the prop that lines the map edge. Textures are built by
## tools/layouts/theme_art.py from tools/layouts/themes.json.

@export var id: StringName
@export var display_name := ""
## Base and patch tiles with every corner combination (custom data "sand_corners").
@export var ground_tiles: TileSet
## Surface ids from Track.SURFACES.
@export var base_surface := &"grass"
@export var patch_surface := &"sand"
@export var asphalt: Texture2D
@export var kerb: Texture2D
## Lines the map edge, on top of the solid wall.
@export var wall_prop: Texture2D
@export var wall_spacing := 76.0
## Background of this track's card on the track-select screen.
@export var card_colour := Color(0.36, 0.73, 0.29)
## Played during the race (docs/DESIGN.md §13).
@export var music: MusicPiece

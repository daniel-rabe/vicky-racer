class_name MusicPiece
extends Resource
## One piece of music (docs/DESIGN.md §13). Written by tools/comfy/generate_music.py
## `build`, which cuts each piece to whole bars and measures where its loop starts: the file
## plays from the top, and at its end jumps back to `loop_offset`, past the lead-in.

@export var id: StringName
@export var stream: AudioStream
## False for a sting, which plays once.
@export var loops := true
## Seconds from the start of the file to the start of the loop.
@export var loop_offset := 0.0
@export var bpm := 0.0

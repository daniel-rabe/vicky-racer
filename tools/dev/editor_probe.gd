extends Node
## Pictures of the track editor (docs/DESIGN.md §26) for review: a figure-of-eight on Candy
## Lane's theme, the MY TRACKS page, and a race on the track. Uses its own save and tracks folder.
##   godot --path . res://tools/dev/editor_probe.tscn -- --shots=<folder>

const MAIN := preload("res://game/main.tscn")
const EIGHT := [[24, 25], [31, 26.5], [38, 24], [42, 16], [38, 7.5], [30, 6], [24, 15], [18, 24], [10, 23.5],
	[6, 15], [10, 7], [17, 5.5]]

var _shots := "user://editor_shots"


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots = arg.get_slice("=", 1)
	DirAccess.make_dir_recursive_absolute(_shots)
	var folder := "user://probe_tracks"
	for file in DirAccess.get_files_at(folder) if DirAccess.dir_exists_absolute(folder) else PackedStringArray():
		DirAccess.remove_absolute(folder.path_join(file))
	MyTracks.folder = folder
	# Two older tracks, so MY TRACKS has something to show.
	var beach := CustomTrack.default_spec(&"beach")
	beach["road"] = [[24, 25], [36, 24], [42, 15], [34, 6], [24, 10], [14, 6], [6, 15], [12, 24]]
	MyTracks.create(beach)
	var snow := CustomTrack.default_spec(&"snow")
	snow["road"] = [[20, 25], [40, 25], [40, 6], [28, 6], [28, 17], [20, 17], [20, 6], [8, 6], [8, 25]]
	MyTracks.create(snow)
	var main := MAIN.instantiate()
	add_child(main)
	await get_tree().create_timer(1.0).timeout
	EventSystem.UI_screen_requested.emit(&"editor")
	await get_tree().create_timer(1.0).timeout
	var editor: Control = main.get_node("ScreenSlot").get_child(0)
	editor._open_new()
	var spec: Dictionary = CustomTrack.with_theme(editor.spec, &"candy")
	spec["road"] = EIGHT
	spec["props"] = {"lollipop": [[24, 3], [3, 3], [45, 3], [45, 27], [3, 27]],
		"donut": [[16, 15], [33, 15], [24, 21]], "cupcake": [[46, 15], [2.5, 15], [24, 28]],
		"gumdrop": [[13, 12], [13, 18], [35, 12], [35, 18], [28, 28], [20, 28]]}
	spec["puddles"] = [[30, 15], [17, 13]]
	spec["boosts"] = [[40, 21], [8, 10]]
	editor.spec = spec
	editor._build_tools()
	editor._show_theme()
	editor._commit()
	editor._tool = editor.Tool.PROP
	editor._prop_kind = "lollipop"
	editor._show_tool()
	await _shot("editor_candy")
	editor._show_gallery()
	await _shot("my_tracks")
	editor._gallery.visible = false
	editor._race()
	await get_tree().create_timer(7.0).timeout
	await _shot("race_on_it")
	get_tree().quit()


func _shot(shot_name: String) -> void:
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots.path_join(shot_name + ".png"))

extends Node
## Headless checks for the track editor (docs/DESIGN.md §26): the track file (what is kept,
## what a broken or hostile file becomes), the track built from the dots (finish, checkpoint,
## grid, a bridge where the road crosses itself), the folder of tracks, the editor's tools,
## and a whole race on a child's figure-of-eight with every car finding its way round.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/editor_test.tscn -- --autopilot
## Exit code 0 = all passed. Uses its own tracks folder (user://test_tracks).

const EDITOR := preload("res://ui/editor/track_editor.tscn")
const RACE_SCENE := preload("res://game/screens/race.tscn")
const EIGHT := [[24, 25], [31, 26.5], [38, 24], [42, 16], [38, 7.5], [30, 6], [24, 15], [18, 24], [10, 23.5],
	[6, 15], [10, 7], [17, 5.5]]
const RACE_TIMEOUT := 150.0

var _failures: PackedStringArray = []
var _results: Array = []
var _result_track := &""
var _laps := {}


func _enter_tree() -> void:
	EventSystem.RAC_race_finished.connect(func(results: Array, id: StringName) -> void:
		_results = results
		_result_track = id)
	EventSystem.RAC_lap_completed.connect(func(car: Node, _lap: int, _time: float) -> void:
		_laps[car.name] = _laps.get(car.name, 0) + 1)


func _ready() -> void:
	MyTracks.folder = "user://test_tracks"
	_empty_folder()
	_test_file()
	_test_points()
	_test_folder()
	await _test_editor()
	await _test_race()
	_empty_folder()
	if _failures.is_empty():
		print("ALL EDITOR TESTS PASSED")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures.append(message)


func _empty_folder() -> void:
	for file in DirAccess.get_files_at(MyTracks.dir()):
		DirAccess.remove_absolute(MyTracks.folder.path_join(file))


func _eight(theme := &"candy") -> Dictionary:
	var spec := CustomTrack.default_spec(theme)
	spec["road"] = EIGHT.duplicate(true)
	return spec


func _test_file() -> void:
	print("the track file")
	var spec := _eight()
	spec["props"] = {"lollipop": [[3, 3], [45, 27]], "donut": [[16, 15]]}
	spec["puddles"] = [[30, 15]]
	spec["boosts"] = [[40, 21]]
	var once := CustomTrack.from_json(CustomTrack.to_json(spec))
	_check(once["road"].size() == EIGHT.size() and once["props"].size() == 2 and once["boosts"].size() == 1,
		"a track is read back from its file")
	_check(CustomTrack.from_json(CustomTrack.to_json(once)) == once, "and survives its file unchanged after that")
	for junk in ["", "hello", "[1, 2]", "{}", '{"format": "something-else", "road": [[1,1],[2,2],[3,3],[4,4]]}',
			'{"format": "vicky-racer-track", "road": [[5, 5], [9, 9]]}', " ".repeat(CustomTrack.MAX_FILE_BYTES + 1)]:
		_check(CustomTrack.from_json(junk).is_empty(), "not a track: %s" % junk.left(40).replace("\n", " "))
	var hostile := CustomTrack.from_json(JSON.stringify({"format": "vicky-racer-track", "theme": "lava",
		"name": "a very very very long name indeed for a track",
		"road": [[1e9, 5], [-40, 3], [10, "x"], [20, 20], [30, 20], [25, 10], [3, 3, 3]] + range(80).map(
			func(i: int) -> Array: return [10 + i % 20, 10]),
		"props": {"tree": [[5, 5]], "toy_house": [[6, 6]], "../../evil": [[1, 1]]},
		"puddles": "lots", "boosts": [[1, 1]]}))
	_check(hostile["theme"] == "meadow", "an unknown theme becomes the meadow")
	_check(hostile["road"].size() == CustomTrack.MAX_DOTS, "dots are capped at %d" % CustomTrack.MAX_DOTS)
	_check(hostile["road"].all(func(p: Array) -> bool:
		return p[0] >= CustomTrack.EDGE and p[0] <= CustomTrack.MAP_TILES.x - CustomTrack.EDGE), "dots are kept on the map")
	_check(hostile["props"].keys() == ["tree"], "only the theme's own props are kept (%s)" % [hostile["props"].keys()])
	_check(hostile["puddles"] == [] and hostile["name"].length() <= 24, "nonsense fields are dropped, long names cut")


func _test_points() -> void:
	print("the track from the dots")
	var oval := CustomTrack.to_points_data(CustomTrack.default_spec())
	_check(oval["bridge_spans"].is_empty() and oval["crossings_px"].is_empty(), "an oval has no bridge")
	var data := CustomTrack.to_points_data(_eight())
	_check(data["crossings_px"].size() == 1 and data["bridge_spans"].size() == 1,
		"a figure-of-eight crosses once and gets one bridge (%s)" % [data["crossings_px"]])
	var span: Array = data["bridge_spans"][0]
	_check(fposmod(0.0 - span[0], 1.0) > span[1], "the finish is not on the bridge")
	var track := CustomTrack.make_track(_eight())
	add_child(track)
	_check(track.grid_transforms().size() == 4, "four grid slots")
	var on_road := track.grid_transforms().all(func(t: Transform2D) -> bool: return track.surface_at(t.origin) == &"asphalt")
	_check(on_road, "every grid slot is on the road")
	var checkpoint: Vector2 = track.get_node("Checkpoint").global_position
	var crossing := Vector2(data["crossings_px"][0][0], data["crossings_px"][0][1])
	_check(checkpoint.distance_to(crossing) > CustomTrack.CROSSING_CLEAR * CustomTrack.TILE_PX * 0.9,
		"the checkpoint keeps away from the crossing")
	track.free()


func _test_folder() -> void:
	print("my tracks")
	var a := MyTracks.create(CustomTrack.default_spec())
	var b := MyTracks.create(_eight())
	var names := MyTracks.list().map(func(e: Dictionary) -> String: return e["spec"]["name"])
	_check(names.size() == 2 and "TRACK 1" in names and "TRACK 2" in names, "new tracks are TRACK 1, TRACK 2 (%s)" % [names])
	var shared := _eight(&"snow")
	shared["name"] = "VICKY'S LOOP!"
	var c := MyTracks.import_text(CustomTrack.to_json(shared))
	_check(c != "" and CustomTrack.from_json(FileAccess.get_file_as_string(c))["name"] == "VICKY'S LOOP!",
		"a shared track comes in under its own name")
	var again := MyTracks.import_text(CustomTrack.to_json(shared))
	_check(CustomTrack.from_json(FileAccess.get_file_as_string(again))["name"] == "TRACK 3",
		"the same name twice becomes the next TRACK n")
	_check(MyTracks.import_text("not a track") == "", "a file that is no track is refused")
	_check(MyTracks.share_name(shared) == "vicky_s_loop_.vrtrack", "the shared copy has a safe file name")
	MyTracks.remove(a)
	MyTracks.remove("user://save.cfg")  # outside the folder: left alone
	_check(not FileAccess.file_exists(a) and FileAccess.file_exists(b), "a track can be erased")
	_empty_folder()


func _click(editor: Control, tiles: Vector2, release := true) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = editor._to_local(tiles)
	editor._on_map_input(press)
	if release:
		var up := press.duplicate()
		up.pressed = false
		editor._on_map_input(up)


func _test_editor() -> void:
	print("the editor")
	var editor: Control = EDITOR.instantiate()
	add_child(editor)
	await get_tree().process_frame
	_check(editor.spec["road"].size() == 8 and MyTracks.list().size() == 1, "it opens on a new oval, saved at once")
	var path: String = editor.path
	# ROAD: a dot outside the oval joins the loop next to its neighbours, and drags.
	_click(editor, Vector2(24, 2.5), false)
	var motion := InputEventMouseMotion.new()
	motion.position = editor._to_local(Vector2(26, 3))
	editor._on_map_input(motion)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.position = motion.position
	editor._on_map_input(up)
	var road: Array = editor.spec["road"]
	var i := road.find([26.0, 3.0])
	_check(road.size() == 9 and i >= 0, "a tap adds a dot and dragging moves it (%s)" % [road])
	var top := road.map(func(p: Array) -> float: return p[1]).find(road.map(func(p: Array) -> float: return p[1]).min())
	_check(absi(i - top) <= 1 or road.size() - absi(i - top) <= 1, "it joined the loop beside the top dots")
	_check(CustomTrack.from_json(FileAccess.get_file_as_string(path)) == editor.spec, "the change was saved")
	# PROPS: not on the road; anywhere else.
	editor._tool = editor.Tool.PROP
	editor._prop_kind = "tree"
	_click(editor, Vector2(road[0][0], road[0][1]))
	_check(editor.spec["props"].is_empty(), "a tree is not put on the road")
	_click(editor, Vector2(24, 15))
	_check(editor.spec["props"].get("tree", []).size() == 1, "a tree goes in the middle")
	# Theme: the tree becomes the snow's pine tree.
	editor._set_theme(&"snow")
	_check(editor.spec["props"].keys() == ["pine_tree"], "on snow the tree is a pine tree")
	editor._undo_last()
	_check(editor.spec["theme"] == "meadow" and editor.spec["props"].keys() == ["tree"], "UNDO takes the snow back")
	# ERASE: the tree, then dots, but never below four.
	editor._tool = editor.Tool.ERASE
	_click(editor, Vector2(24, 15))
	_check(editor.spec["props"].is_empty(), "ERASE takes the tree away")
	for k in 8:
		var p: Array = editor.spec["road"][1]
		_click(editor, Vector2(p[0], p[1]))
	_check(editor.spec["road"].size() == CustomTrack.MIN_DOTS, "the loop keeps four dots (%d)" % editor.spec["road"].size())
	# BOOST: only on the road.
	editor._tool = editor.Tool.BOOST
	_click(editor, Vector2(24, 15))
	var p0: Array = editor.spec["road"][0]
	_click(editor, Vector2(p0[0] + 4, p0[1]))
	_check(editor.spec["boosts"].size() == 1, "a boost pad goes on the road, not beside it")
	# The road runs over a tree: the tree makes way.
	editor._tool = editor.Tool.PROP
	editor._prop_kind = "tree"
	_click(editor, Vector2(10, 10))
	editor._tool = editor.Tool.ROAD
	editor._remember()
	editor.spec["road"].append([10.0, 10.0])
	editor._commit()
	_check(editor.spec["props"].is_empty(), "a tree the road now runs over makes way")
	editor.queue_free()
	await get_tree().process_frame
	_empty_folder()


## A whole race round a figure-of-eight, on the custom track the editor hands the race.
func _test_race() -> void:
	print("a race on it")
	var config := CustomTrack.make_config(_eight())
	EventSystem.UI_settings_requested.connect(func() -> void:
		EventSystem.UI_settings_changed.emit({"sound_volume": 0.0, "music_volume": 0.0, "fullscreen": false,
			"auto_accelerate": false, "steering_help": false, "difficulty": &"normal"}))
	EventSystem.PRO_state_requested.connect(func() -> void:
		EventSystem.PRO_state_changed.emit({"setups": [load("res://game/configs/setups/starter.tres")],
			"equipped": &"starter", "selected_track": CustomTrack.ID, "custom_track": config,
			"tracks": [{"config": load("res://game/configs/tracks/track_01.tres")}]}))
	var race: Node2D = RACE_SCENE.instantiate()
	add_child(race)
	_check(race.config == config, "the race is on the custom track")
	var waited := 0.0
	while _results.is_empty() and waited < RACE_TIMEOUT:
		await get_tree().create_timer(1.0).timeout
		waited += 1.0
	_check(not _results.is_empty() and _result_track == CustomTrack.ID, "the race finished, on the custom track (%ds)" % waited)
	for r in race.racers:
		var laps: int = _laps.get(r["car"].name, 0)
		_check(laps >= (3 if r["is_player"] else 2), "%s went round (%d laps)" % [r["name"], laps])
		if not r["is_player"]:
			_check(r["driver"].rescues == 0, "%s never needed rescuing over the bridge" % r["name"])
	race.queue_free()

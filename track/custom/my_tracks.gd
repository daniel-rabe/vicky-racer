class_name MyTracks
extends RefCounted
## The child's own tracks on this computer (docs/DESIGN.md §26): one .vrtrack file each (a
## CustomTrack spec, as JSON) in user://my_tracks/, beside the save. The track editor saves
## after every change, so nothing is ever lost and there is no SAVE button to forget.
##
## Sharing is the same file: SHARE writes a copy wherever the parent wants it (on the web, the
## browser downloads it), and GET A TRACK reads one back in as a new track here. A file another
## person made goes through CustomTrack.from_json, which keeps only what it understands.

const MAX_TRACKS := 60

## Where they are; tests and screenshots use another folder (main.gd's --tracks-dir).
static var folder := "user://my_tracks"


static func dir() -> String:
	DirAccess.make_dir_recursive_absolute(folder)
	return folder


## Every track here, newest first: {"path", "spec", "modified"}. Unreadable files are skipped.
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for file in DirAccess.get_files_at(dir()):
		if file.get_extension() != CustomTrack.EXTENSION:
			continue
		var path := folder.path_join(file)
		var spec := CustomTrack.from_json(FileAccess.get_file_as_string(path))
		if not spec.is_empty():
			out.append({"path": path, "spec": spec, "modified": FileAccess.get_modified_time(path)})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["modified"] > b["modified"] or (a["modified"] == b["modified"] and a["path"] > b["path"]))
	return out


static func save(spec: Dictionary, path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(CustomTrack.to_json(spec))
	file.close()
	return OK


## A new file for a track: TRACK 1, TRACK 2... the first name nobody has.
static func create(spec: Dictionary) -> String:
	var taken := list().map(func(entry: Dictionary) -> String: return entry["spec"]["name"])
	var n := 1
	while "TRACK %d" % n in taken:
		n += 1
	spec["name"] = "TRACK %d" % n
	var path := dir().path_join("track_%d_%d.%s" % [n, Time.get_unix_time_from_system(), CustomTrack.EXTENSION])
	save(spec, path)
	return path


static func remove(path: String) -> void:
	if path.begins_with(folder + "/"):
		DirAccess.remove_absolute(path)


static func full() -> bool:
	return list().size() >= MAX_TRACKS


## Somebody's track file, read in as a new track here under its own name (or the next free
## TRACK n if that name is taken). Returns its path, or "" when the text is not a track.
static func import_text(text: String) -> String:
	var spec := CustomTrack.from_json(text)
	if spec.is_empty() or full():
		return ""
	var wanted: String = spec["name"]
	var taken := list().map(func(entry: Dictionary) -> String: return entry["spec"]["name"])
	if wanted in taken or wanted.begins_with("TRACK "):
		return create(spec)
	var path := dir().path_join("shared_%d_%d.%s" % [Time.get_unix_time_from_system(), randi() % 10000,
		CustomTrack.EXTENSION])
	save(spec, path)
	return path


## What a shared copy is called: the track's name, safe for any file system.
static func share_name(spec: Dictionary) -> String:
	var safe := ""
	for c in String(spec["name"]).to_lower():
		safe += c if (c >= "a" and c <= "z") or (c >= "0" and c <= "9") else "_"
	return "%s.%s" % [safe.strip_edges() if safe != "" else "my_track", CustomTrack.EXTENSION]

class_name GhostLap
extends Resource
## One recorded lap, to be raced against as a see-through car (docs/DESIGN.md §16): the car's
## position and rotation on every physics tick from the moment it crossed the line until it
## crossed it again. About 30 s × 60 ticks × 3 floats — some 20 KB.
##
## The player's own best lap per track is saved as plain data (to_dict / FileAccess.store_var,
## which can hold no objects, so a ghost file can never carry code); the developer ghosts that
## ship with the game are .res files of this resource in game/configs/ghosts/.

@export var track_id: StringName
@export var setup_id: StringName
@export var paint: StringName = &"original"
@export var lap_time := 0.0
@export var ticks_per_second := 60
## x, y, rotation per tick, flat.
@export var samples := PackedFloat32Array()
## The car's z_index per tick: on a bridge it is drawn above the deck, and so is its ghost.
@export var layers := PackedByteArray()


func frame_count() -> int:
	return samples.size() / 3


func add(at: Transform2D, layer := 0) -> void:
	samples.append(at.origin.x)
	samples.append(at.origin.y)
	samples.append(at.get_rotation())
	layers.append(layer)


func layer_at_frame(frame: int) -> int:
	return layers[clampi(frame, 0, layers.size() - 1)] if not layers.is_empty() else 0


func position_at_frame(frame: int) -> Vector2:
	var i := clampi(frame, 0, frame_count() - 1) * 3
	return Vector2(samples[i], samples[i + 1])


func rotation_at_frame(frame: int) -> float:
	return samples[clampi(frame, 0, frame_count() - 1) * 3 + 2]


## Where the ghost is `seconds` into its lap. At the recording's own tick rate this lands on
## the recorded samples exactly; at another rate it blends the two nearest.
func transform_at(seconds: float) -> Transform2D:
	if frame_count() == 0:
		return Transform2D.IDENTITY
	var at := seconds * ticks_per_second - 1.0  # sample 0 is the first tick after the line
	var a := clampi(floori(at), 0, frame_count() - 1)
	var b := mini(a + 1, frame_count() - 1)
	var t := clampf(at - a, 0.0, 1.0)
	var pos := position_at_frame(a).lerp(position_at_frame(b), t)
	return Transform2D(lerp_angle(rotation_at_frame(a), rotation_at_frame(b), t), pos)


func to_dict() -> Dictionary:
	return {"version": 1, "track": String(track_id), "setup": String(setup_id), "paint": String(paint),
		"lap_time": lap_time, "tps": ticks_per_second, "samples": samples, "layers": layers}


static func from_dict(data: Variant) -> GhostLap:
	if not data is Dictionary or int(data.get("version", 0)) != 1 or not data.get("samples") is PackedFloat32Array:
		return null
	var ghost := GhostLap.new()
	ghost.track_id = StringName(str(data.get("track", "")))
	ghost.setup_id = StringName(str(data.get("setup", "starter")))
	ghost.paint = StringName(str(data.get("paint", "original")))
	ghost.lap_time = float(data.get("lap_time", 0.0))
	ghost.ticks_per_second = maxi(1, int(data.get("tps", 60)))
	ghost.samples = data["samples"]
	var layers: Variant = data.get("layers")
	if layers is PackedByteArray and layers.size() == ghost.samples.size() / 3:
		ghost.layers = layers
	if ghost.samples.size() % 3 != 0 or ghost.samples.is_empty():
		return null
	return ghost


func save_file(path: String) -> Error:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_var(to_dict())
	return OK


## A broken or missing file is simply no ghost.
static func load_file(path: String) -> GhostLap:
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	return from_dict(file.get_var(false))

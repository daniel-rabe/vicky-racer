class_name DriverLook
extends RefCounted
## Who is at the wheel (docs/DESIGN.md §22.1): a driver id and its picture. The children
## wear a helmet in a car and a cap and life vest on a boat; the town's grown-ups drive the
## big vehicles. Pictures are built by tools/comfy/generate_assets.py into art/drivers/.

const VICKY := &"vicky"
const PLAYER_2 := &"p2"
## The opponents, in the order of TrackConfig.opponent_names (BLUE, YELLOW, GREEN).
const OPPONENTS: Array[StringName] = [&"blue", &"yellow", &"green"]
const KIDS: Array[StringName] = [&"vicky", &"p2", &"blue", &"yellow", &"green"]
## The town's big vehicles and who drives them.
## (The delivery van shows nobody: its windscreen is its face.)
const TRAFFIC := {"bus": &"bus", "fire_engine": &"fire", "garbage_truck": &"garbage"}

static var _cache := {}


## The driver's picture for this kind of vehicle (&"car" or &"boat"), facing +X; null if
## there is none (an unknown id, or art not built yet), and then the seat stays empty.
static func texture(driver_id: StringName, vehicle_kind: StringName) -> Texture2D:
	if driver_id.is_empty():
		return null
	var folder := "traffic" if driver_id in TRAFFIC.values() else ("boat" if vehicle_kind == &"boat" else "car")
	var path := "res://art/drivers/%s/%s.png" % [folder, driver_id]
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


## Player 1 is Vicky, player 2 the friend (`player` 1-based).
static func for_player(player: int) -> StringName:
	return PLAYER_2 if player == 2 else VICKY


## The grown-up who drives this town vehicle picture, or &"" for none.
static func for_traffic(body: Texture2D) -> StringName:
	return TRAFFIC.get(body.resource_path.get_file().get_basename(), &"") if body else &""

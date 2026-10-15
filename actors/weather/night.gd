class_name Night
extends Node
## Night (docs/DESIGN.md §27): the world goes a deep, friendly blue and every car, boat, bus
## and fire engine drives with its lights on — two headlight beams lighting the road ahead,
## and red tail lights that glow brighter on the brake. Cars added later (traffic, the fire
## engine, the boat at the harbour) get their lights as they arrive. Nothing plays
## differently at night: it is just how it looks.
##
## The owner sets `world` (where the dark goes, for the split screen) and `weather` (if a
## Weather has the world's CanvasModulate already, the night darkens that one instead: a
## canvas has only one). Its lights go on the cars under its parent (the screen), not the
## next screen's coming in. Removing the node turns the day back on.

## How dark the night is: blue, and still bright enough for a child to see the road.
const TINT := Color(0.34, 0.38, 0.62)

## Where the dark goes, if not the parent: the split screen's world, drawn in its viewports.
var world: Node
## The weather in the same world, if any: its gloom is the night's dark too.
var weather: Weather

var _dark: CanvasModulate


func _ready() -> void:
	if weather:
		weather.tint = TINT
	else:
		_dark = CanvasModulate.new()
		_dark.name = "NightDark"
		_dark.color = TINT
		(world if world else get_parent()).add_child.call_deferred(_dark)
	for car in _cars():
		CarLights.fit(car)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	get_tree().node_added.disconnect(_on_node_added)
	if is_instance_valid(weather):
		weather.tint = Color.WHITE
	if is_instance_valid(_dark):
		_dark.queue_free()
	for car in _cars():
		CarLights.remove(car)


func _on_node_added(node: Node) -> void:
	if node is Car and get_parent().is_ancestor_of(node):
		CarLights.fit.call_deferred(node)


func _cars() -> Array[Node]:
	return get_tree().get_nodes_in_group(&"cars").filter(func(car: Node) -> bool:
		return get_parent().is_ancestor_of(car))

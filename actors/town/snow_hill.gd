class_name SnowHill
extends Node
## What happens on the snowy hill (docs/DESIGN.md §33; SnowIsland has where things are):
##   - snow falls while the player is out there (it stops back over the bridge);
##   - the hill pulls every car downhill: slow going up, whoosh coming down, and a car left
##     at the top rolls off it; Vicky on foot just plods up;
##   - the first time across the bridge each drive, SNOWY HILL comes up, and reaching the
##     flag at the top says so too.

## Snow falls this far out from the island's shore, and stops beyond it.
const SNOW_REACH := 900.0
const TOP_REACH := 160.0

## The town screen (TownScreen): the player, the HUD.
var screen: Node
var snowing := false
var arrived := false
var on_top := false
var _layer: CanvasLayer
var _snow: GPUParticles2D


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "SnowFall"
	_layer.layer = 1
	add_child(_layer)
	_snow = Weather.make_snow()
	_snow.position = Vector2(960, -40)
	_layer.add_child(_snow)


func _physics_process(delta: float) -> void:
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		if car is Kid or car.frozen or CarHop.airborne(car):
			continue
		var push := SnowIsland.slope_at(car.global_position)
		if push != Vector2.ZERO:
			car.velocity += push * delta
	var player: Car = screen.player
	if player == null:
		return
	var at := player.global_position
	var near := at.x > SnowIsland.shore_x() - SNOW_REACH and \
		Rect2(SnowIsland.CENTRE - SnowIsland.RADII, SnowIsland.RADII * 2.0).grow(SNOW_REACH).has_point(at)
	if near != snowing:
		snowing = near
		_snow.emitting = near
	if not arrived and SnowIsland.contains(at):
		arrived = true
		screen.hud.show_banner("SNOWY HILL")
	var top := at.distance_to(SnowIsland.HILL) < TOP_REACH
	if top and not on_top:
		screen.hud.show_banner("TOP OF THE HILL!")
	on_top = top

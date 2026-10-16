class_name CandyLand
extends Node
## What happens in candy land (docs/DESIGN.md §34; CandyIsland has where things are, Town
## builds the jelly pads that bounce a car):
##   - sprinkles fall while the player is out there, in all the colours (they stop back over
##     the bridge);
##   - the first time across the bridge each drive, CANDY LAND comes up, and driving into the
##     chocolate lake says so too.

## Sprinkles fall this far out from the island's shore, and stop beyond it.
const SPRINKLE_REACH := 900.0
const SPRINKLE_COLOURS: Array[Color] = [Color(0.95, 0.25, 0.4), Color(0.3, 0.75, 1.0), Color(1.0, 0.85, 0.2),
	Color(0.45, 0.85, 0.35), Color(0.75, 0.45, 0.95), Color(1.0, 0.55, 0.15), Color.WHITE]

## The town screen (TownScreen): the player, the HUD.
var screen: Node
var sprinkling := false
var arrived := false
var in_chocolate := false
var _layer: CanvasLayer
var _sprinkles: GPUParticles2D


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "Sprinkles"
	_layer.layer = 1
	add_child(_layer)
	_sprinkles = make_sprinkles()
	_sprinkles.position = Vector2(960, -40)
	_layer.add_child(_sprinkles)


func _physics_process(_delta: float) -> void:
	var player: Car = screen.player
	if player == null:
		return
	var at := player.global_position
	var near := at.x > CandyIsland.shore_x() - SPRINKLE_REACH and CandyIsland.this_side(at) and \
		Rect2(CandyIsland.CENTRE - CandyIsland.RADII, CandyIsland.RADII * 2.0).grow(SPRINKLE_REACH).has_point(at)
	if near != sprinkling:
		sprinkling = near
		_sprinkles.emitting = near
	if not arrived and CandyIsland.contains(at):
		arrived = true
		screen.hud.show_banner("CANDY LAND")
	var chocolate := CandyIsland.contains(at) and CandyIsland.surface(at) == &"chocolate"
	if chocolate and not in_chocolate:
		screen.hud.show_banner("CHOCOLATE LAKE!")
	in_chocolate = chocolate


## Sprinkles falling over the screen, like Weather's snow: little sticks of every colour,
## tumbling as they fall.
static func make_sprinkles() -> GPUParticles2D:
	var image := Image.create(8, 22, false, Image.FORMAT_RGBA8)
	for y in 22:
		for x in 8:
			# A rounded white stick, tinted per sprinkle by the colour ramp.
			var d := Vector2((x - 3.5) / 3.5, maxf(absf(y - 10.5) - 7.0, 0.0) / 3.5).length()
			image.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) / 0.3, 0.0, 1.0)))
	var colours := Gradient.new()
	colours.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colours.offsets = PackedFloat32Array()
	colours.colors = PackedColorArray()
	for k in SPRINKLE_COLOURS.size():
		colours.add_point(float(k) / SPRINKLE_COLOURS.size(), SPRINKLE_COLOURS[k])
	var ramp := GradientTexture1D.new()
	ramp.gradient = colours
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(1200.0, 10.0, 0.0)
	material.direction = Vector3(0.1, 1.0, 0.0)
	material.spread = 15.0
	material.initial_velocity_min = 200.0
	material.initial_velocity_max = 320.0
	material.gravity = Vector3.ZERO
	material.angle_min = -180.0
	material.angle_max = 180.0
	material.angular_velocity_min = -160.0
	material.angular_velocity_max = 160.0
	material.scale_min = 0.7
	material.scale_max = 1.1
	material.color_initial_ramp = ramp
	var sprinkles := GPUParticles2D.new()
	sprinkles.name = "Sprinkles"
	sprinkles.process_material = material
	sprinkles.texture = ImageTexture.create_from_image(image)
	sprinkles.amount = 180
	sprinkles.lifetime = 6.0
	sprinkles.preprocess = 6.0
	sprinkles.visibility_rect = Rect2(-3000, -200, 6000, 2400)
	sprinkles.emitting = false
	return sprinkles

class_name JungleWoods
extends Node
## What happens in the jungle (docs/DESIGN.md §35; JungleIsland has where things are):
##   - leaves drift down while the player is out there (they stop back over the bridge);
##   - a car that drives through a mud pool comes out muddy (CarMud), and stays muddy until it
##     goes through the car wash; the first time each drive, the banner says so;
##   - the first time across the bridge each drive, JUNGLE comes up, and driving into the
##     temple's courtyard says JUNGLE TEMPLE!

## Leaves fall this far out from the island's shore, and stop beyond it.
const LEAF_REACH := 900.0
const LEAF_COLOURS: Array[Color] = [Color(0.3, 0.62, 0.22), Color(0.48, 0.74, 0.25), Color(0.22, 0.5, 0.2),
	Color(0.85, 0.72, 0.2)]

## The town screen (TownScreen): the player, the HUD.
var screen: Node
var leafy := false
var arrived := false
var in_temple := false
var told_mud := false
var _layer: CanvasLayer
var _leaves: GPUParticles2D


func _enter_tree() -> void:
	EventSystem.CAR_surface_changed.connect(_on_surface_changed)


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "Leaves"
	_layer.layer = 1
	add_child(_layer)
	_leaves = make_leaves()
	_leaves.position = Vector2(960, -40)
	_layer.add_child(_leaves)


func _on_surface_changed(car: Node, surface: StringName) -> void:
	if surface != &"mud" or not car is Car or car is Boat or car is Kid:
		return
	CarMud.splash(car)
	if car == screen.player and not told_mud:
		told_mud = true
		screen.hud.show_banner("MUDDY!  TRY THE CAR WASH")


func _physics_process(_delta: float) -> void:
	var player: Car = screen.player
	if player == null:
		return
	var at := player.global_position
	var near := Rect2(JungleIsland.CENTRE - JungleIsland.RADII, JungleIsland.RADII * 2.0).grow(LEAF_REACH).has_point(at)
	if near != leafy:
		leafy = near
		_leaves.emitting = near
	if not arrived and JungleIsland.contains(at):
		arrived = true
		screen.hud.show_banner("JUNGLE")
	var temple := JungleIsland.courtyard().has_point(at)
	if temple and not in_temple:
		screen.hud.show_banner("JUNGLE TEMPLE!")
	in_temple = temple


## Leaves drifting down over the screen, like Weather's snow: little green leaves, swaying and
## turning as they fall.
static func make_leaves() -> GPUParticles2D:
	var image := Image.create(16, 24, false, Image.FORMAT_RGBA8)
	for y in 24:
		for x in 16:
			# A pointed oval with a paler middle vein, tinted per leaf by the colour ramp.
			var u := (x - 7.5) / 7.5
			var v := (y - 11.5) / 11.5
			var width := sqrt(maxf(1.0 - v * v, 0.0)) * (1.0 - 0.35 * absf(v))
			var inside := absf(u) < width
			var vein := absf(u) < 0.12 and absf(v) < 0.85
			image.set_pixel(x, y, Color.WHITE if inside and vein else (Color(0.8, 0.8, 0.8) if inside else Color(1, 1, 1, 0)))
	var colours := Gradient.new()
	colours.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colours.offsets = PackedFloat32Array()
	colours.colors = PackedColorArray()
	for k in LEAF_COLOURS.size():
		colours.add_point(float(k) / LEAF_COLOURS.size(), LEAF_COLOURS[k])
	var ramp := GradientTexture1D.new()
	ramp.gradient = colours
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(1200.0, 10.0, 0.0)
	material.direction = Vector3(0.3, 1.0, 0.0)
	material.spread = 25.0
	material.initial_velocity_min = 90.0
	material.initial_velocity_max = 160.0
	material.gravity = Vector3.ZERO
	material.angle_min = -180.0
	material.angle_max = 180.0
	material.angular_velocity_min = -90.0
	material.angular_velocity_max = 90.0
	material.turbulence_enabled = true
	material.turbulence_noise_strength = 4.0
	material.turbulence_influence_min = 0.05
	material.turbulence_influence_max = 0.15
	material.scale_min = 0.9
	material.scale_max = 1.5
	material.color_initial_ramp = ramp
	var leaves := GPUParticles2D.new()
	leaves.name = "Leaves"
	leaves.process_material = material
	leaves.texture = ImageTexture.create_from_image(image)
	leaves.amount = 50
	leaves.lifetime = 12.0
	leaves.preprocess = 12.0
	leaves.visibility_rect = Rect2(-3000, -200, 6000, 2400)
	leaves.emitting = false
	return leaves

class_name ToyTown
extends Node
## What happens in toy town (docs/DESIGN.md §36; ToyIsland has where things are, Town builds
## the mat, the blocks and the train):
##   - confetti drifts down while the player is out there (it stops back over the bridge);
##   - the first time across the bridge each drive, TOY TOWN comes up, and pulling up beside the
##     toy train says CHOO CHOO! (again each time, once the train has gone away).

## Confetti falls this far out from the island's shore, and stops beyond it.
const CONFETTI_REACH := 900.0
const CONFETTI_COLOURS: Array[Color] = [Color(0.95, 0.3, 0.35), Color(0.3, 0.6, 1.0), Color(1.0, 0.85, 0.2),
	Color(0.4, 0.85, 0.4), Color(0.8, 0.45, 0.95), Color(1.0, 0.6, 0.2)]
## Near enough the engine to hear it, and far enough to have left it.
const TRAIN_NEAR := 330.0
const TRAIN_FAR := 900.0

## The town screen (TownScreen): the player, the HUD, the town.
var screen: Node
var confetti_on := false
var arrived := false
var by_train := false
var _layer: CanvasLayer
var _confetti: GPUParticles2D


func _ready() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "Confetti"
	_layer.layer = 1
	add_child(_layer)
	_confetti = make_confetti()
	_confetti.position = Vector2(960, -40)
	_layer.add_child(_confetti)


func _physics_process(_delta: float) -> void:
	var player: Car = screen.player
	if player == null:
		return
	var at := player.global_position
	var near := Rect2(ToyIsland.CENTRE - ToyIsland.RADII, ToyIsland.RADII * 2.0).grow(CONFETTI_REACH).has_point(at)
	if near != confetti_on:
		confetti_on = near
		_confetti.emitting = near
	if not arrived and ToyIsland.contains(at):
		arrived = true
		screen.hud.show_banner("TOY TOWN")
	var train: ToyTrain = screen.town.train
	if train == null:
		return
	var gap := at.distance_to(train.engine_at())
	if gap < TRAIN_NEAR and not by_train:
		by_train = true
		screen.hud.show_banner("CHOO CHOO!")
	elif gap > TRAIN_FAR:
		by_train = false


## Confetti over the screen, like Weather's snow: little squares of every colour, fluttering.
static func make_confetti() -> GPUParticles2D:
	var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var colours := Gradient.new()
	colours.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	colours.offsets = PackedFloat32Array()
	colours.colors = PackedColorArray()
	for k in CONFETTI_COLOURS.size():
		colours.add_point(float(k) / CONFETTI_COLOURS.size(), CONFETTI_COLOURS[k])
	var ramp := GradientTexture1D.new()
	ramp.gradient = colours
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(1200.0, 10.0, 0.0)
	material.direction = Vector3(0.0, 1.0, 0.0)
	material.spread = 20.0
	material.initial_velocity_min = 110.0
	material.initial_velocity_max = 190.0
	material.gravity = Vector3.ZERO
	material.angle_min = -180.0
	material.angle_max = 180.0
	material.angular_velocity_min = -220.0
	material.angular_velocity_max = 220.0
	material.scale_min = 0.6
	material.scale_max = 1.1
	material.color_initial_ramp = ramp
	var confetti := GPUParticles2D.new()
	confetti.name = "Confetti"
	confetti.process_material = material
	confetti.texture = ImageTexture.create_from_image(image)
	confetti.amount = 90
	confetti.lifetime = 9.0
	confetti.preprocess = 9.0
	confetti.visibility_rect = Rect2(-3000, -200, 6000, 2400)
	confetti.emitting = false
	return confetti

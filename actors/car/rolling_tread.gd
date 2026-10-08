class_name RollingTread
extends Node
## Wheels that roll (docs/CAR_ANIMATION_PLAN.md). The tyres are part of each car's body
## picture, so a shader on the body sprite draws tread over them and slides it along as the car
## rolls: backwards in reverse, the rear pair locked while the handbrake is held, smeared at
## speed. The front pair turns with the steering (Phase 20b). Where the tyres are comes from
## CarWheels; a body it does not list (the Bubble Car) gets no shader and looks as it always did.
##
## Under a Car it follows the car by itself. Anything else (a GhostCar) calls advance().

const SHADER := preload("res://actors/car/rolling_tread.gdshader")
## Must match PERIOD in the shader: the rolls are wrapped to it.
const PERIOD := 5.0
## Tread px per px driven. A tread sliding at the true rate would strobe from walking pace up;
## a slower one still reads as rolling, and stays crisp until BLUR_FROM.
const ROLL_SCALE := 0.15
## Speeds, px/s, over which the tread smears to flat: past ~0.4 PERIOD per frame it would
## seem to spin backwards. Top speed is 1100, 1430 boosted.
const BLUR_FROM := 700.0
const BLUR_TO := 1100.0
## How far the front wheels turn at full steer, and how fast they get there (1/s).
const MAX_STEER := deg_to_rad(20.0)
const STEER_RATE := 14.0

## The sprite whose texture has the tyres. Defaults to the parent car's Body.
var sprite: Sprite2D
## Tread slid so far, texture px (not wrapped).
var roll_front := 0.0
var roll_rear := 0.0
var blur := 0.0
## How far the front wheels are turned now, radians; positive = to the right.
var steer := 0.0

var _material: ShaderMaterial
var _texture: Texture2D


func _ready() -> void:
	if sprite == null and get_parent() is Car:
		sprite = get_parent().get_node(^"Body")


## True when the current body has tyres to roll.
func active() -> bool:
	return _material != null


## Roll by `distance` px (negative = backwards) at `speed` px/s.
func advance(distance: float, speed: float, rear_locked := false) -> void:
	_fit()
	if _material == null:
		return
	var step := distance * ROLL_SCALE
	roll_front += step
	if not rear_locked:
		roll_rear += step
	blur = smoothstep(BLUR_FROM, BLUR_TO, absf(speed))
	_material.set_shader_parameter(&"roll_front", wrapf(roll_front, 0.0, PERIOD))
	_material.set_shader_parameter(&"roll_rear", wrapf(roll_rear, 0.0, PERIOD))
	_material.set_shader_parameter(&"blur", blur)


## Turn the front wheels towards `input` (-1 left .. 1 right) over `delta` seconds.
func turn(input: float, delta: float) -> void:
	_fit()
	steer = lerpf(steer, clampf(input, -1.0, 1.0) * MAX_STEER, 1.0 - exp(-STEER_RATE * delta))
	if _material:
		_material.set_shader_parameter(&"steer", steer)


func _physics_process(delta: float) -> void:
	var car := get_parent() as Car
	if car == null:
		return
	# The wheels turn even on the grid: something to do while the lights count down.
	turn(car.steer_input, delta)
	if car.frozen:
		_fit()
		return
	var speed := car.forward_speed()
	advance(speed * delta, speed, car.handbrake)


## Give the sprite a tread shader for the tyres of its current texture, or take it away.
func _fit() -> void:
	if sprite == null or sprite.texture == _texture:
		return
	_texture = sprite.texture
	var rects := CarWheels.of(_texture)
	if rects.is_empty():
		if _material and sprite.material == _material:
			sprite.material = null
		_material = null
		return
	if _material == null:
		_material = ShaderMaterial.new()
		_material.shader = SHADER
	var wheels := PackedVector4Array()
	for r: Rect2i in rects:
		wheels.append(Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
	_material.set_shader_parameter(&"wheels", wheels)
	sprite.material = _material

class_name TownSky
extends Node2D
## What passes over Free Drive's town (docs/DESIGN.md §19): soft cloud shadows sliding over
## the streets, hot-air balloons drifting on the wind with their shadows below them, and
## now and then a flock of birds flying across the player's view. All decoration: nothing
## here touches the cars.

const BALLOON := "res://art/town/props/balloon.png"
const BIRD := "res://art/town/animals/bird.png"
const WIND := Vector2(34, 12)
const BALLOONS := 3
## Balloons fly high: drawn larger than anything on the ground.
const BALLOON_SIZE := 1.6
const CLOUDS := 5
const SKY_Z := 20
## Shadows lie on the ground, under the cars.
const SHADOW_Z := 0
const SHADOW_OFFSET := Vector2(180, 260)
const BIRD_SPEED := 300.0
const FLOCK_EVERY := Vector2(14.0, 28.0)

## The town's area: things leaving it come back in on the other side.
var world := Rect2()

var _balloons: Array[Dictionary] = []  # {sprite, shadow, phase}
var _clouds: Array[Sprite2D] = []
var _flock: Array[Dictionary] = []     # {sprite, shadow, velocity}
var _next_flock := 6.0
var _time := 0.0


func _ready() -> void:
	for i in CLOUDS:
		var cloud := Sprite2D.new()
		cloud.texture = _soft_blob()
		cloud.modulate = Color(0.1, 0.12, 0.25, 0.10)
		cloud.scale = Vector2(randf_range(5.0, 8.0), randf_range(3.0, 4.5))
		cloud.position = Vector2(randf_range(world.position.x, world.end.x), randf_range(world.position.y, world.end.y))
		cloud.z_index = SKY_Z - 1
		add_child(cloud)
		_clouds.append(cloud)
	if ResourceLoader.exists(BALLOON):
		var picture: Texture2D = load(BALLOON)
		for i in BALLOONS:
			var sprite := _sky_sprite(picture, BALLOON_SIZE)
			sprite.modulate = Color.from_hsv(float(i) / BALLOONS, 0.25, 1.0) if i > 0 else Color.WHITE
			var start := Vector2(randf_range(world.position.x, world.end.x), randf_range(world.position.y, world.end.y))
			sprite.position = start
			_balloons.append({"sprite": sprite, "shadow": _shadow_of(sprite), "phase": randf() * TAU})


func _process(delta: float) -> void:
	_time += delta
	for cloud in _clouds:
		cloud.position = _wrap(cloud.position + WIND * 1.4 * delta, 700.0)
	for b in _balloons:
		var sprite: Sprite2D = b["sprite"]
		sprite.position = _wrap(sprite.position + WIND * delta, 200.0)
		var breathe := 1.0 + 0.03 * sin(_time * 0.8 + b["phase"])
		sprite.scale = Vector2.ONE * BALLOON_SIZE * breathe
		_place_shadow(b["shadow"], sprite)
	_next_flock -= delta
	if _next_flock <= 0.0:
		_next_flock = randf_range(FLOCK_EVERY.x, FLOCK_EVERY.y)
		_send_flock()
	for i in range(_flock.size() - 1, -1, -1):
		var bird: Dictionary = _flock[i]
		var sprite: Sprite2D = bird["sprite"]
		sprite.position += bird["velocity"] * delta
		sprite.scale.x = 0.55 + 0.45 * absf(sin(_time * 9.0 + i))  # wings flapping
		_place_shadow(bird["shadow"], sprite)
		if not world.grow(600.0).has_point(sprite.position):
			sprite.queue_free()
			bird["shadow"].queue_free()
			_flock.remove_at(i)


## Five birds in a V, flying across what the camera sees.
func _send_flock() -> void:
	var camera := get_viewport().get_camera_2d()
	if camera == null or not ResourceLoader.exists(BIRD):
		return
	var picture: Texture2D = load(BIRD)
	var centre := camera.get_screen_center_position()
	var heading := Vector2.from_angle(randf() * TAU)
	var start := centre - heading * 1500.0 + heading.orthogonal() * randf_range(-300.0, 300.0)
	for i in 5:
		var row := (i + 1) / 2
		var side := -1.0 if i % 2 == 1 else 1.0
		var sprite := _sky_sprite(picture, 1.0)
		sprite.position = start - heading * row * 90.0 + heading.orthogonal() * side * row * 80.0
		sprite.rotation = heading.angle()  # built facing +X, like the cars
		_flock.append({"sprite": sprite, "shadow": _shadow_of(sprite), "velocity": heading * BIRD_SPEED})


func _sky_sprite(picture: Texture2D, size: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = picture
	sprite.scale = Vector2(size, size)
	sprite.z_index = SKY_Z
	add_child(sprite)
	return sprite


func _shadow_of(sprite: Sprite2D) -> Sprite2D:
	var shadow := Sprite2D.new()
	shadow.texture = sprite.texture
	shadow.modulate = Color(0, 0, 0, 0.2)
	shadow.z_index = SHADOW_Z
	add_child(shadow)
	_place_shadow(shadow, sprite)
	return shadow


func _place_shadow(shadow: Sprite2D, sprite: Sprite2D) -> void:
	shadow.position = sprite.position + SHADOW_OFFSET * (0.4 if sprite.texture.get_width() < 100 else 1.0)
	shadow.rotation = sprite.rotation
	shadow.scale = sprite.scale * 0.85


func _wrap(at: Vector2, margin: float) -> Vector2:
	var area := world.grow(margin)
	return Vector2(wrapf(at.x, area.position.x, area.end.x), wrapf(at.y, area.position.y, area.end.y))


static func _soft_blob() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.set_color(0, Color.WHITE)
	gradient.set_color(1, Color(1, 1, 1, 0))
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 128
	texture.height = 128
	return texture

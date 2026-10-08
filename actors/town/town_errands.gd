class_name TownErrands
extends Node2D
## Little jobs the shops give the player's car in Free Drive (docs/DESIGN.md §23), told only
## in pictures:
##   - a treat: the ice cream parlour and the candy shop put an ice cream or a lollipop on
##     the car's roof, and it rides along for TREAT_SECONDS;
##   - a delivery: the pizza place, the bakery and the flower shop put a pizza, a donut or
##     flowers on the roof, and a bubble with the same picture floats over a house. Pulling
##     up at that house's door hands it over: the house bounces, hearts, coins;
##   - the lost puppy: the pet shop's puppy is hiding somewhere in town, under a bubble.
##     Drive up to it and it follows the car; bring it back to the pet shop's door.
## One job at a time, no timer: a job waits, however long the child drives about, and while
## the player is in the boat, the fire engine or the bus. The HUD points the way, and the map
## shows where.

const TREATS := {"ice_cream_shop": "res://art/town/treats/ice_cream_cone.png", "candy_shop": "res://art/props/candy/lollipop.png"}
const DELIVERIES := {"pizza_place": "res://art/town/treats/pizza.png", "bakery": "res://art/props/candy/donut.png",
	"flower_shop": "res://art/town/props/flower_bed.png"}
const PUPPY_SHOP := "pet_shop"
const PUPPY := preload("res://art/town/animals/dog.png")
const PET_SHOP := preload("res://art/town/buildings/pet_shop.png")
const WOOF := "res://art/sfx/woof.wav"
const CHEER := "res://art/sfx/cheer.wav"
const CHIME := "res://art/sfx/sparkle.wav"
const TREAT_SECONDS := 30.0
const DELIVERY_PAY := 10
const PUPPY_PAY := 10
## A house for a delivery is at least this far from the shop, px.
const DELIVERY_AWAY := 1800.0
const PUPPY_AWAY := 2200.0
## Pulling up: this near the door, this slow.
const ARRIVE := 200.0
const ARRIVE_SPEED := 320.0
## Driving this near the puppy finds it.
const FIND := 240.0
## The puppy trots this far behind the car.
const HEEL := 140.0
## What rides on the roof: this big, this far behind the car's middle.
const ROOF_SIZE := 52.0
const ROOF_AT := Vector2(-20, 0)
const MARKER_HEIGHT := 150.0

## The town screen (game/screens/town.gd): the player, the town, the HUD, paying.
var screen: Node
## &"", &"delivery" or &"puppy".
var errand := &""
## Where the job is going: the house's door, the puppy, the pet shop's door.
var target := Vector2.ZERO
var puppy_following := false

var _load: Sprite2D
var _load_time := 0.0
var _picture: Texture2D
## What the HUD's pointer shows: the parcel, the puppy, then the pet shop to take it home to.
var _pointer_picture: Texture2D
var _house: Dictionary
var _shop_door := Vector2.ZERO
var _puppy: Sprite2D
var _trail: Array[Vector2] = []
var _marker: Node2D
var _marker_picture: Sprite2D
var _time := 0.0
## Seconds after a job is done before a shop gives another, so pulling up to bring the puppy
## home does not send it straight off again.
var _rest := 0.0
var _voice: AudioStreamPlayer2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_marker = _make_marker()
	add_child(_marker)
	_marker.visible = false
	if SoundManager.audible():
		_voice = AudioStreamPlayer2D.new()
		_voice.bus = &"SFX"
		_voice.max_distance = 2000.0
		add_child(_voice)


## The player's car pulled up at a shop's door.
func on_place(place_id: String) -> void:
	if _rest > 0.0:
		return
	if TREATS.has(place_id) and errand != &"delivery":
		give_treat(load(TREATS[place_id]))
	elif DELIVERIES.has(place_id) and errand == &"":
		start_delivery(place_id)
	elif place_id == PUPPY_SHOP and errand == &"":
		start_puppy()


## Something nice on the roof for a while.
func give_treat(picture: Texture2D) -> void:
	_put_on_roof(picture, TREAT_SECONDS)
	_play(CHIME, -8.0)


func start_delivery(shop_id: String) -> void:
	var door := _door_of(shop_id)
	var far: Array[Dictionary] = []
	for house: Dictionary in screen.town.houses:
		if house["door"].distance_to(door) > DELIVERY_AWAY:
			far.append(house)
	if far.is_empty():
		return
	_house = far[_rng.randi() % far.size()]
	_picture = load(DELIVERIES[shop_id])
	_put_on_roof(_picture, 0.0)
	_pointer_picture = _picture
	errand = &"delivery"
	target = _house["door"]
	_show_marker(_house["door"] + Vector2(0, -TownLayout.SIDEWALK - MARKER_HEIGHT), _picture)
	_play(CHIME, -8.0)


func start_puppy() -> void:
	_shop_door = _door_of(PUPPY_SHOP)
	var spot := _hiding_spot(_shop_door)
	if spot == Vector2.INF:
		return
	errand = &"puppy"
	puppy_following = false
	_puppy = Sprite2D.new()
	_puppy.texture = PUPPY
	_puppy.scale = Vector2(0.7, 0.7)
	_puppy.z_index = 1
	add_child(_puppy)
	_puppy.global_position = spot
	target = spot
	_pointer_picture = PUPPY
	_show_marker(spot + Vector2(0, -MARKER_HEIGHT * 0.8), PUPPY)
	_play(WOOF, -6.0)


## What the map shows: where the job is going.
func marks() -> Array:
	return [[target, Color(1, 0.824, 0.247)]] if errand != &"" else []


func _physics_process(delta: float) -> void:
	_time += delta
	_rest = maxf(_rest - delta, 0.0)
	_bob_load(delta)
	_bob_marker()
	var car: Car = screen.car
	var driving: bool = screen.player == car and car != null
	if errand == &"delivery" and driving and _arrived(car, target):
		_deliver()
	elif errand == &"puppy":
		_walk_puppy(car, driving, delta)
	if errand != &"":
		screen.hud.point_at(target, _pointer_picture)


func _arrived(car: Car, at: Vector2) -> bool:
	return car.global_position.distance_to(at) < ARRIVE and car.velocity.length() < ARRIVE_SPEED


## The parcel hops from the roof to the door; the house bounces and says thank you.
func _deliver() -> void:
	var from: Vector2 = _load.global_position if _load else screen.car.global_position
	_drop_load()
	var parcel := Sprite2D.new()
	parcel.texture = _picture
	parcel.scale = Vector2.ONE * ROOF_SIZE / maxf(_picture.get_width(), _picture.get_height())
	parcel.z_index = 4
	add_child(parcel)
	parcel.global_position = from
	var door: Vector2 = _house["door"]
	var tween := parcel.create_tween()
	tween.tween_property(parcel, "global_position", door + Vector2(0, -TownLayout.SIDEWALK * 0.6), 0.35) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(parcel, "scale", Vector2.ZERO, 0.2)
	tween.tween_callback(parcel.queue_free)
	_bounce(_house["sprite"])
	TownFx.hearts(screen.get_node(^"World"), door + Vector2(0, -TownLayout.SIDEWALK))
	screen.pay(DELIVERY_PAY, door)
	_play(CHEER if ResourceLoader.exists(CHEER) else CHIME, -4.0)
	_finish()


func _walk_puppy(car: Car, driving: bool, delta: float) -> void:
	if _puppy == null:
		return
	if not puppy_following:
		# Hiding: a wiggle, now and then a little hop.
		_puppy.rotation = sin(_time * 3.0) * 0.25 - PI / 2.0
		_puppy.scale = Vector2.ONE * 0.7 * (1.0 + 0.08 * maxf(sin(_time * 5.0), 0.0))
		if driving and car.global_position.distance_to(_puppy.global_position) < FIND:
			puppy_following = true
			_trail = [car.global_position]
			target = _shop_door
			_pointer_picture = PET_SHOP
			_show_marker(_shop_door + Vector2(0, -TownLayout.SIDEWALK - MARKER_HEIGHT), PUPPY)
			_play(WOOF, -4.0)
		return
	if not driving:
		return  # waits where it is while the car is parked at the harbour, the fire station or the school
	if car.global_position.distance_to(_trail[0]) > 6.0:
		_trail.push_front(car.global_position)
		if _trail.size() > 200:
			_trail.pop_back()
	var spot := _trail_point(HEEL)
	var step := _puppy.global_position.distance_to(spot)
	if step > 1.0:
		var heading := (spot - _puppy.global_position).angle()
		_puppy.rotation = lerp_angle(_puppy.rotation, heading, 1.0 - exp(-10.0 * delta)) + sin(_time * 14.0) * 0.12
	_puppy.global_position = _puppy.global_position.lerp(spot, 1.0 - exp(-12.0 * delta))
	if _arrived(car, _shop_door):
		_puppy_home()


## Home: the puppy runs in at the pet shop's door.
func _puppy_home() -> void:
	var puppy := _puppy
	_puppy = null
	var tween := puppy.create_tween()
	tween.tween_property(puppy, "global_position", _shop_door + Vector2(0, -TownLayout.SIDEWALK * 0.7), 0.5)
	tween.tween_property(puppy, "modulate:a", 0.0, 0.3)
	tween.tween_callback(puppy.queue_free)
	TownFx.hearts(screen.get_node(^"World"), _shop_door + Vector2(0, -TownLayout.SIDEWALK), 8)
	screen.pay(PUPPY_PAY, _shop_door)
	_play(WOOF, -2.0)
	_finish()


func _finish() -> void:
	errand = &""
	_rest = 3.0
	puppy_following = false
	_marker.visible = false
	screen.hud.point_at(Vector2.INF, null)


func _trail_point(distance: float) -> Vector2:
	var walked := 0.0
	for i in range(1, _trail.size()):
		var seg := _trail[i - 1].distance_to(_trail[i])
		if walked + seg >= distance:
			return _trail[i - 1].lerp(_trail[i], (distance - walked) / maxf(seg, 0.001))
		walked += seg
	return _trail[_trail.size() - 1]


## Somewhere on a lawn, away from the pet shop, clear of buildings, trees, ponds and the pitch.
func _hiding_spot(away_from: Vector2) -> Vector2:
	var town: Town = screen.town
	for attempt in 200:
		var lawn: Rect2 = town.lawns[_rng.randi() % town.lawns.size()].grow(-110.0)
		var spot := Vector2(_rng.randf_range(lawn.position.x, lawn.end.x), _rng.randf_range(lawn.position.y, lawn.end.y))
		if spot.distance_to(away_from) < PUPPY_AWAY or town.surface_at(spot) != &"grass":
			continue
		if town.footprints.any(func(r: Rect2) -> bool: return r.grow(80.0).has_point(spot)):
			continue
		if town.tree_spots.any(func(t: Vector2) -> bool: return t.distance_to(spot) < 110.0):
			continue
		if town.pitch.grow(100.0).has_point(spot) or town.fountain_at.distance_to(spot) < 260.0:
			continue
		return spot
	return Vector2.INF


func _door_of(place_id: String) -> Vector2:
	var best := Vector2.INF
	var car_at: Vector2 = screen.car.global_position if screen.car else Vector2.ZERO
	for place: Dictionary in screen.town.places:
		if place["id"] == place_id and place["door"].distance_to(car_at) < best.distance_to(car_at):
			best = place["door"]
	return best


# --- what rides on the roof ------------------------------------------------------------

func _put_on_roof(picture: Texture2D, seconds: float) -> void:
	_drop_load()
	var car: Car = screen.car
	_load = Sprite2D.new()
	_load.name = "RoofLoad"
	_load.texture = picture
	_load.position = ROOF_AT
	_load.z_index = 3
	_load.scale = Vector2.ZERO
	car.get_node(^"Body").add_child(_load)
	_load_time = seconds
	var size := Vector2.ONE * ROOF_SIZE / maxf(picture.get_width(), picture.get_height())
	_load.create_tween().tween_property(_load, "scale", size, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _bob_load(delta: float) -> void:
	if _load == null or not is_instance_valid(_load):
		return
	_load.rotation = sin(_time * 2.5) * 0.12
	if _load_time > 0.0:
		_load_time -= delta
		if _load_time <= 0.0:
			_drop_load(true)


## Off the roof: gone at once, or (a treat eaten up) shrinking away.
func _drop_load(eaten := false) -> void:
	if _load == null or not is_instance_valid(_load):
		_load = null
		return
	var old := _load
	_load = null
	if eaten:
		var tween := old.create_tween()
		tween.tween_property(old, "scale", Vector2.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tween.tween_callback(old.queue_free)
	else:
		old.queue_free()


# --- the bubble over where to go ---------------------------------------------------------

func _make_marker() -> Node2D:
	var marker := Node2D.new()
	marker.name = "ErrandMarker"
	marker.z_index = 5
	var tail := Polygon2D.new()
	tail.polygon = PackedVector2Array([Vector2(-26, 40), Vector2(26, 40), Vector2(0, 92)])
	tail.color = Color.WHITE
	marker.add_child(tail)
	marker.add_child(_disc(Vector2.ZERO, 70.0, Color(0.055, 0.078, 0.11)))
	marker.add_child(_disc(Vector2.ZERO, 62.0, Color.WHITE))
	_marker_picture = Sprite2D.new()
	marker.add_child(_marker_picture)
	return marker


func _show_marker(at: Vector2, picture: Texture2D) -> void:
	_marker.global_position = at
	_marker.set_meta(&"home", at)
	_marker_picture.texture = picture
	_marker_picture.scale = Vector2.ONE * 84.0 / maxf(picture.get_width(), picture.get_height())
	_marker.visible = true
	_marker.scale = Vector2(0.3, 0.3)
	_marker.create_tween().tween_property(_marker, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _bob_marker() -> void:
	if not _marker.visible:
		return
	var home: Vector2 = _marker.get_meta(&"home", _marker.global_position)
	if errand == &"puppy" and not puppy_following and _puppy:
		home = _puppy.global_position + Vector2(0, -MARKER_HEIGHT * 0.8)
	_marker.global_position = home + Vector2(0, sin(_time * 3.0) * 12.0)


## A happy hop: the building jumps up a little and drops back.
func _bounce(sprite: Node2D) -> void:
	if sprite == null or not is_instance_valid(sprite):
		return
	var rest := sprite.position
	var tween := sprite.create_tween()
	tween.tween_property(sprite, "position", rest + Vector2(0, -18), 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(sprite, "position", rest, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _play(path: String, volume_db: float) -> void:
	if _voice == null or not ResourceLoader.exists(path):
		return
	_voice.stream = load(path)
	_voice.volume_db = volume_db
	_voice.global_position = screen.player.global_position
	_voice.play()


static func _disc(at: Vector2, radius: float, colour: Color) -> Polygon2D:
	var points := PackedVector2Array()
	for k in 24:
		points.append(at + Vector2.from_angle(TAU * k / 24.0) * radius)
	var disc := Polygon2D.new()
	disc.polygon = points
	disc.color = colour
	return disc

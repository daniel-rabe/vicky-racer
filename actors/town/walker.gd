class_name Walker
extends Node2D
## An animal out for a walk in Free Drive's town (docs/DESIGN.md §19): a dog or a cat going
## round a block on the pavement, or a mother duck leading her ducklings to and fro across a
## zebra crossing, waiting on each side. It waddles as it goes.
##
## It is in the "walkers" group, so traffic stops for it on a crossing. A car coming fast
## makes it hop out of the way with a little jump; it never gets hurt. It has no body: cars
## drive through the spot it hopped from.
##
## It has a voice (quack, woof, meow): it calls out as it hops, when a horn toots near it,
## and — a duck — as she sets off across the road.
##
## Vicky on foot (Kid, §29) walking up to it pets it: hearts, a happy woof or meow, a jump, and a
## dog or cat trots along after him for a while before going back to its walk. It never hops
## away from him.

signal petted(walker: Walker)

## Its route, world positions. `loop`: round and round; otherwise there and back.
var route := PackedVector2Array()
var loop := true
var speed := 70.0
## Seconds it waits at each end of a there-and-back route.
var pause := 5.0
var picture: Texture2D
## Ducklings: smaller copies following in a line behind.
var followers := 0
var voice: AudioStream

const FLEE_RADIUS := 190.0
const FLEE_SPEED := 120.0
const HOP := 70.0
const FOLLOW_GAP := 34.0
const HEAR_HORN := 520.0
## A crossing animal waits until no vehicle is this near the crossing.
const CLEAR_DISTANCE := 520.0
## Any vehicle this near the crossing's line is on it (a bus is 208 px long).
const ON_CROSSING := 160.0
## Petting (§29): this near, a pet; then it follows this long, this far behind, and wants
## another pet only after a rest.
const PET_REACH := 80.0
const FOLLOW_SECONDS := 9.0
const HEEL := 75.0
const PET_REST := 12.0

var _target := 1
var _step := 1
var _wait := 0.0
var _phase := 0.0
var _hop_offset := Vector2.ZERO
var _hop_tween: Tween
var _trail: Array[Vector2] = []  # where the leader has been, newest first
var _body: Sprite2D
var _young: Array[Sprite2D] = []
var _voice: AudioStreamPlayer2D
var _jump: Tween
var _jump_scale := 1.0
## Following Vicky after a pet, and for how much longer.
var friend: Node2D
var _friend_time := 0.0
var _pet_rest := 0.0


func _enter_tree() -> void:
	EventSystem.CAR_horn.connect(func(car: Node) -> void:
		if car is Node2D and car.global_position.distance_to(global_position) < HEAR_HORN:
			_call_out()
			_bounce())


func _ready() -> void:
	add_to_group(&"walkers")
	_phase = randf() * TAU
	_body = Sprite2D.new()
	_body.texture = picture
	add_child(_body)
	for i in followers:
		var duckling := Sprite2D.new()
		duckling.texture = picture
		duckling.scale = Vector2(0.6, 0.6)
		duckling.top_level = true
		duckling.add_to_group(&"walkers")  # traffic waits for the last duckling too
		add_child(duckling)
		_young.append(duckling)
	if voice and SoundManager.audible():
		_voice = AudioStreamPlayer2D.new()
		_voice.stream = voice
		_voice.bus = &"SFX"
		_voice.volume_db = -6.0
		_voice.max_distance = 1400.0
		add_child(_voice)
	if route.size() > 0:
		global_position = route[0]
	if not loop:
		_wait = randf() * pause  # families set off at different times
	for i in (followers + 1) * 8:
		_trail.append(global_position)


func _physics_process(delta: float) -> void:
	if route.size() < 2:
		return
	_dodge_cars()
	_check_pet(delta)
	var moving := false
	if friend:
		moving = _trot_after_friend(delta)
	elif _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0 and not loop and not _road_clear():
			_wait = 0.5  # look both ways: off again once nothing is coming
	else:
		var goal := route[_target]
		var to_goal := goal - global_position
		var step := speed * delta
		if to_goal.length() <= step:
			global_position = goal
			_next_point()
		else:
			global_position += to_goal.normalized() * step
			rotation = lerp_angle(rotation, to_goal.angle(), 1.0 - exp(-10.0 * delta))
			moving = true
	# The waddle: a sway and a little bounce while walking.
	_phase += delta * (11.0 if moving else 2.0)
	_body.rotation = sin(_phase) * (0.18 if moving else 0.04)
	var bob := 1.0 + (absf(sin(_phase)) * 0.06 if moving else 0.0)
	_body.scale = Vector2(bob, bob) * _jump_scale
	_body.position = _hop_offset.rotated(-rotation)
	_follow(moving)


func _next_point() -> void:
	if loop:
		_target = (_target + 1) % route.size()
		return
	if _target + _step < 0 or _target + _step >= route.size():
		_step = -_step
		_wait = pause * randf_range(0.7, 1.3)
		get_tree().create_timer(_wait, false).timeout.connect(_call_out)
	_target += _step


## Nothing driving near the crossing (a there-and-back route goes across a road).
func _road_clear() -> bool:
	var a := route[0]
	var b := route[route.size() - 1]
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		var p := car.global_position
		var t := clampf((p - a).dot(b - a) / (b - a).length_squared(), 0.0, 1.0)
		var away := p.distance_to(a.lerp(b, t))
		if away < ON_CROSSING:
			return false  # standing on the crossing: wait until it has gone
		if away < CLEAR_DISTANCE and car.velocity.length() >= 40.0:
			return false  # coming; one standing still further off is waiting for us
	return true


## Ducklings walk the leader's trail, one gap apart.
func _follow(moving: bool) -> void:
	if _young.is_empty():
		return
	var here := global_position + _hop_offset
	if moving and here.distance_to(_trail[0]) > 4.0:
		_trail.push_front(here)
		if _trail.size() > 400:
			_trail.pop_back()
	for i in _young.size():
		var spot := _trail_point(FOLLOW_GAP * (i + 1) + 6.0)
		var duckling := _young[i]
		var ahead := _trail_point(FOLLOW_GAP * (i + 1) - 8.0)
		duckling.global_position = spot
		if ahead.distance_to(spot) > 0.5:
			duckling.global_rotation = (ahead - spot).angle() + sin(_phase + i * 1.3) * (0.2 if moving else 0.03)


func _trail_point(distance: float) -> Vector2:
	var walked := 0.0
	for i in range(1, _trail.size()):
		var seg := _trail[i - 1].distance_to(_trail[i])
		if walked + seg >= distance:
			return _trail[i - 1].lerp(_trail[i], (distance - walked) / maxf(seg, 0.001))
		walked += seg
	return _trail[_trail.size() - 1]


## A car coming at it fast: hop to the side, away from the car, then waddle back.
func _dodge_cars() -> void:
	if _hop_tween and _hop_tween.is_running():
		return
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		if car is Kid:
			continue  # a friend, not a car
		var rel := global_position + _hop_offset - car.global_position
		if rel.length() > FLEE_RADIUS or car.velocity.length() < FLEE_SPEED:
			continue
		if car.velocity.dot(rel) <= 0.0:
			continue  # going away
		var away := car.velocity.normalized().orthogonal()
		if away.dot(rel) < 0.0:
			away = -away
		_hop(_hop_offset + away * HOP)
		return


func _hop(to: Vector2) -> void:
	_call_out()
	_hop_tween = create_tween()
	_hop_tween.tween_property(self, "_hop_offset", to, 0.25).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_bounce()
	_hop_tween.tween_interval(1.5)
	_hop_tween.tween_property(self, "_hop_offset", Vector2.ZERO, 1.2).set_trans(Tween.TRANS_SINE)


## A little jump on the spot.
func _bounce() -> void:
	if _jump and _jump.is_running():
		return
	_jump = create_tween()
	_jump.tween_property(self, "_jump_scale", 1.35, 0.12)
	_jump.tween_property(self, "_jump_scale", 1.0, 0.13)


func _call_out() -> void:
	if _voice and is_inside_tree() and not _voice.playing:
		_voice.pitch_scale = randf_range(0.92, 1.12)
		_voice.play()


## Vicky on foot near: a pet. A dog or a cat then follows him; a duck only quacks and jumps.
func _check_pet(delta: float) -> void:
	_pet_rest = maxf(_pet_rest - delta, 0.0)
	if _pet_rest > 0.0:
		return
	for kid: Node in get_tree().get_nodes_in_group(&"kid"):
		if not kid.visible or (kid as Node2D).global_position.distance_to(global_position) > PET_REACH:
			continue
		_pet_rest = PET_REST
		_call_out()
		_bounce()
		TownFx.hearts(get_parent(), global_position + Vector2(0, -30), 4)
		if loop:
			friend = kid
			_friend_time = FOLLOW_SECONDS
		petted.emit(self)
		return


## Trotting along behind Vicky, keeping a little way off; back to its walk when the time is up
## or he has gone (into a car). Returns whether it moved.
func _trot_after_friend(delta: float) -> bool:
	_friend_time -= delta
	if _friend_time <= 0.0 or not is_instance_valid(friend) or not friend.visible:
		friend = null
		return false
	var to_friend := friend.global_position - global_position
	if to_friend.length() <= HEEL:
		return false
	var step := minf(maxf(speed * 4.0, 300.0) * delta, to_friend.length() - HEEL)
	global_position += to_friend.normalized() * step
	rotation = lerp_angle(rotation, to_friend.angle(), 1.0 - exp(-10.0 * delta))
	return true

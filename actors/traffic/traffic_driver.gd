class_name TrafficDriver
extends Node
## Drives its parent Car round Free Drive's town (docs/DESIGN.md §19) by writing the same
## three inputs a player would. It keeps to the right-hand lane, picks a way at random at
## every junction (never straight back, unless the road ends), waits for a junction to be
## free before crossing it, and stops behind whatever is in front of it — another car, the
## player, a duck. Held up by the player for a while, it toots its horn; if the player has
## stopped in its lane, it pulls out and drives round them when the other lane is clear.
##
## Calm town driving: a cruising speed well under a racer's, slower still round corners.

## Every this many seconds of being held up by the player, a toot.
const HONK_AFTER := 2.2
const HONK_EVERY := 4.0
const LOOKAHEAD := 90.0
const LOOKAHEAD_PER_SPEED := 0.3
const STEER_FULL_ANGLE := 0.5
const TURN_SPEED := 190.0
## How far before a junction it asks to cross, and slows for a turn, px.
const ASK_DISTANCE := 150.0
const SLOW_DISTANCE := 320.0
## What counts as in the way: ahead, and within this far either side of its line.
const BLOCK_HALF_WIDTH := 70.0
const STOP_GAP := 150.0
const STUCK_SECONDS := 2.5
const REVERSE_SECONDS := 0.8
## Waited this long for a junction (something has gone wrong), it goes anyway.
const MAX_WAIT := 8.0
## Held up this long by the player standing in its lane, it drives round them — if the
## other lane is clear this far ahead and the junction is far enough off to get back in.
const OVERTAKE_AFTER := 3.0
const OVERTAKE_CLEAR := 1300.0
const OVERTAKE_ROOM := 700.0
const OVERTAKE_SHIFT := 160.0
const SHIFT_RATE := 220.0
## A car with a horn of its own (police siren, ice-cream tune...) sounds it now and then
## when the player is near, just because.
const SHOW_OFF_EVERY := Vector2(14.0, 30.0)
const SHOW_OFF_NEAR := 1100.0

var town: Town
var cruise_speed := 380.0
## Its own extra gap, px, so a queue does not move as one block.
var spacing := 0.0

var _from := Vector2i.ZERO
var _to := Vector2i.ZERO
var _next := Vector2i.ZERO
var _path := PackedVector2Array()
## Where its lane meets the next junction: it waits here until it may cross.
var _lane_end := Vector2.ZERO
var _in_junction := false
var _holds := false
var _wait := 0.0
var _blocked_by_player := 0.0
var _blocker: Node2D
var _honk_timer := 0.0
var _stuck := 0.0
var _reverse := 0.0
var _rng := RandomNumberGenerator.new()
## Pulled out this far to the left of its lane (overtaking), and who it is going round.
var _shift := 0.0
var _passing: Node2D
var _show_off := 0.0

@onready var car: Car = get_parent()


func _ready() -> void:
	process_physics_priority = -1  # write inputs before the car moves this frame
	_rng.randomize()
	_show_off = _rng.randf_range(SHOW_OFF_EVERY.x, SHOW_OFF_EVERY.y)


## Put the car `fraction` of the way along the lane from junction a to junction b.
func place_on(a: Vector2i, b: Vector2i, fraction: float) -> void:
	_from = a
	_to = b
	var lane := town.lane_points(a, b)
	var i := clampi(int(fraction * (lane.size() - 1)), 0, lane.size() - 2)
	car.global_position = lane[i]
	car.rotation = town.heading(a, b).angle()
	car.reset_physics_interpolation()
	_path = lane.slice(i + 1)
	_lane_end = lane[lane.size() - 1]
	_in_junction = false
	_pick_next()


func _pick_next() -> void:
	var ways: Array = town.links[_to].filter(func(j: Vector2i) -> bool: return j != _from)
	if ways.is_empty():
		_next = _from
		return
	# Straight on a little more often than turning: streets read as streets.
	var straight := _to + (_to - _from)
	if straight in ways and _rng.randf() < 0.4:
		_next = straight
	else:
		_next = ways[_rng.randi() % ways.size()]


func _physics_process(delta: float) -> void:
	if town == null or car.frozen:
		return
	_advance()
	var speed := car.velocity.length()
	if _reverse > 0.0:
		_reverse -= delta
		car.throttle_input = -0.7
		car.steer_input = 0.0
		return
	_update_overtake(delta)
	_maybe_show_off(delta)
	var target_speed := _wanted_speed(delta)
	car.steer_input = _steer(speed)
	if target_speed < 10.0:
		# Stopping: brake to a standstill, never into reverse (the car reverses on the brake
		# below Car.REVERSE_SWITCH_SPEED), and let drag hold it there.
		car.throttle_input = -1.0 if car.forward_speed() > Car.REVERSE_SWITCH_SPEED else 0.0
	elif speed < target_speed - 20.0:
		car.throttle_input = 1.0 if target_speed - speed > 80.0 else 0.5
	elif speed > target_speed + 30.0:
		car.throttle_input = -clampf((speed - target_speed) / 250.0, 0.25, 1.0)
	else:
		car.throttle_input = 0.15
	car.handbrake = false
	# Stuck against something that is not in its way (pushed into a wall): back off a little.
	if target_speed > 100.0 and speed < 25.0:
		_stuck += delta
		if _stuck > STUCK_SECONDS:
			_stuck = 0.0
			_reverse = REVERSE_SECONDS
	else:
		_stuck = 0.0


## Drop the points it has passed; at the end of a lane go into the junction, at the end of
## the junction onto the next road.
func _advance() -> void:
	var pos := car.global_position
	var forward := Vector2.RIGHT.rotated(car.rotation)
	while _path.size() > 0 and (pos.distance_to(_path[0]) < 50.0
			or ((_path[0] - pos).dot(forward) < 0.0 and pos.distance_to(_path[0]) < 140.0)):
		_path.remove_at(0)
	if not _path.is_empty():
		return
	if not _in_junction:
		if not _holds:
			return  # waiting at the line
		_in_junction = true
		_path = town.turn_points(_from, _to, _next)
	else:
		town.release(_to, car)
		_holds = false
		_in_junction = false
		_from = _to
		_to = _next
		_path = town.lane_points(_from, _to)
		_lane_end = _path[_path.size() - 1]
		_pick_next()


func _steer(speed: float) -> float:
	var look := LOOKAHEAD + speed * LOOKAHEAD_PER_SPEED
	var target := _point_ahead(look)
	var angle := Vector2.RIGHT.rotated(car.rotation).angle_to(target - car.global_position)
	return clampf(angle / STEER_FULL_ANGLE, -1.0, 1.0)


## The point `distance` px ahead along its line (into the junction once it may cross).
func _point_ahead(distance: float) -> Vector2:
	var pos := car.global_position
	var points := _path
	if _shift > 0.0 and not _in_junction:
		var left := -Town.right_of(town.heading(_from, _to)) * _shift
		points = PackedVector2Array()
		for p in _path:
			points.append(p + left)
	if not _in_junction and _holds:
		points = points + town.turn_points(_from, _to, _next)
	if points.is_empty():
		return pos + Vector2.RIGHT.rotated(car.rotation) * distance
	for p in points:
		if pos.distance_to(p) >= distance:
			return p
	return points[points.size() - 1]


func _wanted_speed(delta: float) -> float:
	var pos := car.global_position
	var turning := not _in_junction and town.heading(_from, _to).dot(town.heading(_to, _next)) < 0.5
	var wanted := cruise_speed
	if _in_junction:
		wanted = TURN_SPEED if town.heading(_from, _to).dot(town.heading(_to, _next)) < 0.5 else cruise_speed * 0.8
	else:
		var to_line := pos.distance_to(_lane_end)
		if turning and to_line < SLOW_DISTANCE:
			wanted = lerpf(TURN_SPEED, cruise_speed, to_line / SLOW_DISTANCE)
		if to_line < ASK_DISTANCE and not _holds:
			# Never into a junction whose way out is a crossing with ducks on it: waiting
			# there would block the junction for everyone.
			_holds = _way_out_clear() and town.try_reserve(_to, car)
			if not _holds:
				_wait += delta
				if _wait > MAX_WAIT:
					_holds = true
				else:
					wanted = minf(wanted, maxf(0.0, (to_line - 80.0) * 2.0))
		if _holds:
			_wait = 0.0
	return minf(wanted, _clear_road_speed(delta))


## Nothing walking across the road just past the junction, where it will come out.
func _way_out_clear() -> bool:
	var out := town.heading(_to, _next)
	var crossing: Vector2 = town.junctions[_to] + out * (TownLayout.ROAD_HALF + 62.0)
	for walker: Node2D in get_tree().get_nodes_in_group(&"walkers"):
		var rel := walker.global_position - crossing
		if absf(rel.dot(out)) < 110.0 and absf(rel.dot(Town.right_of(out))) < TownLayout.ROAD_HALF + 20.0:
			return false
	return true


## Slower the closer whatever is in front: a car, the player, an animal.
func _clear_road_speed(delta: float) -> float:
	var forward := Vector2.RIGHT.rotated(car.rotation)
	var reach := STOP_GAP + spacing + car.velocity.length() * 0.7
	var nearest := INF
	var player_in_way := false
	for group in [&"cars", &"walkers"]:
		for other: Node2D in get_tree().get_nodes_in_group(group):
			if other == car:
				continue
			var rel := other.global_position - car.global_position
			var along := rel.dot(forward)
			if along <= 0.0 or along > reach:
				continue
			if absf(rel.dot(forward.orthogonal())) > BLOCK_HALF_WIDTH:
				continue
			# Facing us head on in the other lane is passing, not blocking.
			if other is Car and Vector2.RIGHT.rotated(other.rotation).dot(forward) < -0.7 \
					and absf(rel.dot(forward.orthogonal())) > 40.0:
				continue
			if other == _passing:
				continue
			if along < nearest:
				nearest = along
				player_in_way = other.has_node(^"PlayerInput")
				_blocker = other
	if player_in_way and nearest < STOP_GAP + 120.0:
		_blocked_by_player += delta
		_honk_timer -= delta
		if _blocked_by_player > HONK_AFTER and _honk_timer <= 0.0:
			_honk_timer = HONK_EVERY
			EventSystem.CAR_horn.emit(car)
	else:
		_blocked_by_player = 0.0
		_honk_timer = 0.0
	if nearest == INF:
		_blocker = null
		return INF
	return maxf(0.0, (nearest - STOP_GAP - spacing) * 2.0)


func _maybe_show_off(delta: float) -> void:
	if car.setup == null or car.setup.horn == null:
		return
	_show_off -= delta
	if _show_off > 0.0:
		return
	_show_off = _rng.randf_range(SHOW_OFF_EVERY.x, SHOW_OFF_EVERY.y)
	for other: Node in get_tree().get_nodes_in_group(&"cars"):
		if other.has_node(^"PlayerInput") and other.global_position.distance_to(car.global_position) < SHOW_OFF_NEAR:
			EventSystem.CAR_horn.emit(car)
			return


## Going round a player who has stopped in the lane: pull out once the other lane is clear,
## back in once past them, or before the junction.
func _update_overtake(delta: float) -> void:
	var to_line := car.global_position.distance_to(_lane_end)
	var forward := town.heading(_from, _to)
	if _passing:
		var gone := not is_instance_valid(_passing) 			or (_passing.global_position - car.global_position).dot(forward) < -170.0
		if gone or _in_junction or to_line < 260.0 or _oncoming_within(450.0):
			_passing = null
	elif _blocker and _blocker.has_node(^"PlayerInput") and _blocked_by_player > OVERTAKE_AFTER 			and not _in_junction and to_line > OVERTAKE_ROOM and not _oncoming_within(OVERTAKE_CLEAR):
		_passing = _blocker
	_shift = move_toward(_shift, OVERTAKE_SHIFT if _passing else 0.0, SHIFT_RATE * delta)


## A car coming the other way in the other lane, within `distance` ahead.
func _oncoming_within(distance: float) -> bool:
	var forward := town.heading(_from, _to)
	var left := -Town.right_of(forward)
	var centre: Vector2 = town.junctions[_from]
	for other: Car in get_tree().get_nodes_in_group(&"cars"):
		if other == car or other == _passing:
			continue
		var along := (other.global_position - car.global_position).dot(forward)
		var lateral := (other.global_position - centre).dot(left)  # > 0: the other lane
		if along > -60.0 and along < distance and lateral > 0.0 and lateral < TownLayout.ROAD_HALF + 40.0:
			return true
	return false


## Dev: what it is doing, for tests and jam hunting.
func describe() -> String:
	return "road %s->%s next %s %s holds=%s wait=%.1f path=%d first=%s shift=%.0f reverse=%.1f reserved_by=%s" % [_from, _to, _next,
		"in junction" if _in_junction else "on road", _holds, _wait, _path.size(),
		_path[0].round() if not _path.is_empty() else Vector2.ZERO, _shift, _reverse,
		town._reserved.get(_to).name if town._reserved.get(_to) else "-"]


func _exit_tree() -> void:
	if town and is_instance_valid(town):
		town.release(_to, car)

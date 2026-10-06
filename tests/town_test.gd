extends Node
## Headless test of Free Drive's town (docs/DESIGN.md §19):
##   - every junction can be reached from every other by road;
##   - every lane and every turn through a junction lies on asphalt, inside the streets;
##   - no building or tree stands on a road or a pavement, and every shop has a doorstep;
##   - surfaces: road and pavement asphalt, lawns grass, the pond water;
##   - a minute of traffic with no jam: nobody stands still for long, nobody leaves the
##     streets, nobody is stuck in a building, nobody drives over a duck;
##   - coins pay out, pulling up at a shop shows it, and the car wash's pad makes the car sparkle.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/town_test.tscn
## Exit code 0 = all passed.

const TOWN_SCENE := preload("res://game/screens/town.tscn")
const SOAK_SECONDS := 60.0
## A car standing this long has jammed (a junction wait is a few seconds at most).
const JAM_SECONDS := 12.0
## Longer than this on the other side of the road is lost, not just steering back in after
## overtaking the parked player (the line moves back first, the car follows within ~1.5 s).
const WRONG_LANE_SECONDS := 2.5

var screen: Node2D
var _time := 0.0
var _still := {}        # car -> seconds standing
var _longest_still := 0.0
var _off_street := 0
var _run_over := 0
var _wrong_lane := {}  # car -> seconds in the oncoming lane (not overtaking)
var _longest_wrong := 0.0
var _coins_found := 0
var _places: Array[String] = []
var _washed: Array[Node] = []
var _done := false


func _enter_tree() -> void:
	EventSystem.UI_settings_requested.connect(func() -> void:
		EventSystem.UI_settings_changed.emit({"sound_volume": 0.0, "music_volume": 0.0, "fullscreen": false,
			"auto_accelerate": false, "steering_help": false, "difficulty": &"normal"}))
	EventSystem.PRO_state_requested.connect(func() -> void:
		EventSystem.PRO_state_changed.emit({"setups": [load("res://game/configs/setups/starter.tres")],
			"equipped": &"starter", "coins": 0, "paint": {}}))
	EventSystem.PRO_coins_found.connect(func(amount: int) -> void: _coins_found += amount)
	EventSystem.CAR_washed.connect(func(car: Node) -> void: _washed.append(car))


func _ready() -> void:
	screen = TOWN_SCENE.instantiate()
	add_child(screen)
	screen.get_node("World/Coins").get_child(0).collected.connect(func(c: TownCoin) -> void:
		print("  coin collected at frame %d" % Engine.get_physics_frames()))
	screen.town.place_reached.connect(func(id: String, _name: String, _picture: Texture2D) -> void:
		_places.append(id))


func _physics_process(delta: float) -> void:
	if _done:
		return
	_time += delta
	var town: Town = screen.town
	var streets := town.streets_rect().grow(40.0)
	for car: Car in screen.traffic:
		var standing := car.velocity.length() < 15.0
		_still[car] = _still.get(car, 0.0) + delta if standing else 0.0
		_longest_still = maxf(_longest_still, _still[car])
		if is_equal_approx(_still[car], JAM_SECONDS) or (_still[car] > JAM_SECONDS and _still[car] - delta < JAM_SECONDS):
			print("  jammed: %s at %s: %s" % [car.name, car.global_position.round(), car.get_node(^"TrafficDriver").describe()])
		if not streets.has_point(car.global_position):
			if _off_street % 600 == 0:
				print("  off the streets: %s at %s rot %.2f v %s: %s" % [car.body_texture.resource_path.get_file(), car.global_position.round(),
					car.rotation, car.velocity.round(), car.get_node(^"TrafficDriver").describe()])
			_off_street += 1
	for car: Car in screen.traffic:
		var driver: TrafficDriver = car.get_node(^"TrafficDriver")
		var wrong := false
		if not driver._in_junction and driver._shift == 0.0:
			var start: Vector2 = town.junctions[driver._from]
			wrong = (car.global_position - start).dot(Town.right_of(town.heading(driver._from, driver._to))) < -20.0
		_wrong_lane[car] = _wrong_lane.get(car, 0.0) + delta if wrong else 0.0
		if _wrong_lane[car] > WRONG_LANE_SECONDS and _wrong_lane[car] - delta <= WRONG_LANE_SECONDS:
			print("  other side: %s at %s rot %.2f v %s: %s" % [car.body_texture.resource_path.get_file(),
				car.global_position.round(), car.rotation, car.velocity.round(), driver.describe()])
		_longest_wrong = maxf(_longest_wrong, _wrong_lane[car])
	for walker: Node2D in get_tree().get_nodes_in_group(&"walkers"):
		for car: Car in screen.traffic:
			if car.global_position.distance_to(walker.global_position) < 50.0:
				if _run_over % 60 == 0:
					print("  over an animal: %s at %s" % [car.body_texture.resource_path.get_file(), car.global_position.round()])
				_run_over += 1
	if _time >= SOAK_SECONDS:
		_done = true
		_finish()


func _finish() -> void:
	var town: Town = screen.town
	var failures: PackedStringArray = []
	var check := func(ok: bool, message: String) -> void:
		print(("  ok   " if ok else "  FAIL ") + message)
		if not ok:
			failures.append(message)

	# The road network is one piece.
	var start: Vector2i = town.junctions.keys()[0]
	var seen := {start: true}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		for n: Vector2i in town.links[queue.pop_front()]:
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	check.call(seen.size() == town.junctions.size(), "every junction is reachable (%d of %d)" % [seen.size(), town.junctions.size()])

	# Every lane and turn is on the road.
	var off_road := 0
	var lanes := 0
	for a: Vector2i in town.links:
		for b: Vector2i in town.links[a]:
			lanes += 1
			var points := town.lane_points(a, b)
			for c: Vector2i in town.links[b]:
				if c != a:
					points += town.turn_points(a, b, c)
			for p in points:
				if not _on_asphalt(town, p):
					off_road += 1
	check.call(off_road == 0, "every lane and turn lies on the road (%d lanes, %d points off)" % [lanes, off_road])

	# Buildings stand on lawns, clear of every road and pavement.
	var misplaced := 0
	for rect in town.footprints:
		if not town.lawns.any(func(lawn: Rect2) -> bool: return lawn.grow(2.0).encloses(rect)):
			misplaced += 1
	check.call(misplaced == 0, "every building stands on its lawn (%d of %d not)" % [misplaced, town.footprints.size()])
	var kinds := {}
	for place in town.places:
		kinds[place["name"]] = true
		if not _on_asphalt(town, place["door"]):
			misplaced += 1
	check.call(kinds.size() == TownLayout.PLACE_NAMES.size(),
		"every kind of place is in town (%d of %d)" % [kinds.size(), TownLayout.PLACE_NAMES.size()])

	# Surfaces.
	var lawn: Rect2 = town.lawns[0]
	var pond := town.ponds[0]
	var j: Vector2 = town.junctions.values()[0]
	check.call(town.surface_at(lawn.get_center() + Vector2(1, 1)) in [&"grass", &"water"], "a lawn is grass")
	check.call(town.surface_at(Vector2(pond.x, pond.y)) == &"water", "the pond is water")
	check.call(town.surface_at(j) == &"asphalt", "a junction is asphalt")
	check.call(town.surface_at(Vector2(lawn.position.x - 20.0, lawn.get_center().y)) == &"asphalt", "the pavement is asphalt")

	# A minute of traffic.
	check.call(_longest_still < JAM_SECONDS, "no jams: the longest any vehicle stood still was %.1f s" % _longest_still)
	check.call(_off_street == 0, "traffic kept to the streets (%d frames off)" % _off_street)
	check.call(_longest_wrong < WRONG_LANE_SECONDS, "traffic keeps to the right-hand lane (longest the other side %.1f s)" % _longest_wrong)
	check.call(_run_over == 0, "traffic never drove over an animal (%d frames)" % _run_over)
	var mean := 0.0
	for car: Car in screen.traffic:
		mean += car.velocity.length() / screen.traffic.size()
	check.call(mean > 150.0, "traffic is moving at the end (mean %.0f px/s)" % mean)

	# Coins and shops, by putting the player on them.
	var player: Car = screen.player
	var coin: TownCoin = screen.get_node("World/Coins").get_child(0)
	player.global_position = coin.global_position
	player.reset_physics_interpolation()
	var place: Dictionary = town.places[0]
	var before := _coins_found
	for i in 6:
		await get_tree().physics_frame
	var paid := _coins_found - before
	player.global_position = place["door"] + Vector2(0, 40)
	player.reset_physics_interpolation()
	for i in 6:
		await get_tree().physics_frame
	check.call(paid == screen.COIN_VALUE, "driving through a coin pays %d (paid %d)" % [screen.COIN_VALUE, paid])
	check.call(place["id"] in _places, "pulling up at the %s shows it (%s)" % [place["name"], _places])

	# The car wash: onto its pad, washed once, then sparkling, the sparkle running down.
	var effects: Node = player.get_node(^"Effects")
	check.call(effects.sparkle_time == 0.0, "the car does not sparkle before the car wash")
	player.global_position = town.wash_pad.get_center()
	player.reset_physics_interpolation()
	for i in 10:
		await get_tree().physics_frame
	check.call(_washed == [player], "driving onto the car wash's pad washes the car (washed: %s)" % [_washed])
	var left: float = effects.sparkle_time
	check.call(left > 0.0 and left < effects.SPARKLE_SECONDS and effects.get_node(^"Sparkle").emitting,
		"and it sparkles, running down (%.2f s left)" % left)
	var lane_car: Car = screen.traffic[0]
	check.call(lane_car.get_node(^"Effects").sparkle_time == 0.0, "traffic is not washed")

	if failures.is_empty():
		print("ALL TOWN TESTS PASSED")
		get_tree().quit(0)
	else:
		get_tree().quit(1)


func _on_asphalt(town: Town, p: Vector2) -> bool:
	return town.streets_rect().has_point(p) and town.surface_at(p) == &"asphalt"

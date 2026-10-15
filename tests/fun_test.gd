extends Node
## Headless checks for the open world's pick-and-mix fun (docs/DESIGN.md §32):
##   - fireworks: none by day; at night on the quay rockets go up, and they stop away from it;
##   - golden stars: COUNT of them, the same every time, spread out, none inside anything solid;
##     driving into one finds it, pays, and the save keeps it;
##   - the jobs board: three different jobs a day, the same all day; doing one pays, the save
##     remembers it for the rest of the day, all three pay the bonus;
##   - the playgrounds: four rides on each; walking up to one plays it and lets him go again
##     where he got on; it does not start again until he walks away; a car does not ride.
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/fun_test.tscn
## Exit code 0 = all passed. Uses its own save and settings files, deleted afterwards.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://fun_test.cfg"
const SETTINGS := "user://fun_test_settings.cfg"
const TESTS := 4

var _failures: PackedStringArray = []
var _main: Node
var _manager: GarageManager
var _finished := 0


func _ready() -> void:
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_main = MAIN.instantiate()
	_main.get_node("GarageManager").save_path = SAVE
	_main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(_main)
	_manager = _main.get_node("GarageManager")
	await _frames(5)
	_screen().get_node("%Play").pressed.emit()
	await _wait_for("Town")
	await _frames(10)
	await _test_fireworks()
	await _test_stars()
	await _test_jobs()
	await _test_playground()
	for path in [SAVE, SETTINGS]:
		DirAccess.remove_absolute(path)
	_check(_finished == TESTS, "every test ran to its end (%d / %d)" % [_finished, TESTS])
	if _failures.is_empty():
		print("ALL FUN TESTS PASSED")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures.append(message)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame


func _screen() -> Node:
	for child in _main.get_node("ScreenSlot").get_children():
		if not child.is_queued_for_deletion():
			return child
	return null


func _wait_for(screen_name: String, seconds := 3.0) -> Node:
	for i in int(seconds * 60.0):
		var screen := _screen()
		if screen and screen.name == screen_name:
			await _frames(3)
			return screen
		await _frames(1)
	return _screen()


func _put(node: Node2D, at: Vector2, angle := 0.0) -> void:
	node.global_position = at
	node.rotation = angle
	if node is CharacterBody2D:
		node.velocity = Vector2.ZERO
	node.reset_physics_interpolation()


func _test_fireworks() -> void:
	print("fireworks")
	var town: TownScreen = _screen()
	var quay := Island.QUAY.get_center() + Vector2(300, 0)
	_put(town.player, quay)
	await _frames(90)
	_check(not town.fireworks.showing and town.fireworks.rockets.is_empty(), "none by day on the quay")
	EventSystem.PRO_night_requested.emit(true)
	var seen := 0
	for i in 150:
		await _frames(1)
		seen = maxi(seen, town.fireworks.rockets.size() + town.fireworks.bursts.size())
	_check(town.fireworks.showing and seen > 0, "  at night on the quay, rockets go up (%d at once)" % seen)
	_put(town.player, town.town.fountain_at + Vector2(-420, 0))
	await _frames(150)
	_check(not town.fireworks.showing and town.fireworks.rockets.is_empty(), "  and stop back in town")
	EventSystem.PRO_night_requested.emit(false)
	await _frames(5)
	_finished += 1


func _test_stars() -> void:
	print("golden stars")
	var town: TownScreen = _screen()
	var spots := town.stars.spots
	_check(spots.size() == GoldenStars.COUNT, "there are %d of them (%d)" % [GoldenStars.COUNT, spots.size()])
	_check(GoldenStars.plan(town.town) == spots, "  in the same places every time")
	var closest := INF
	for i in spots.size():
		for j in range(i + 1, spots.size()):
			closest = minf(closest, spots[i].distance_to(spots[j]))
	_check(closest > 300.0, "  spread out (closest two %.0f px apart)" % closest)
	var query := PhysicsPointQueryParameters2D.new()
	query.collision_mask = town.car.collision_mask
	query.collide_with_areas = false
	var space := town.get_viewport().world_2d.direct_space_state
	var stuck: Array[int] = []
	for i in spots.size():
		query.position = spots[i]
		if not space.intersect_point(query).is_empty():
			stuck.append(i)
			print("    star %d at %s hits %s" % [i, spots[i], space.intersect_point(query)[0]["collider"].get_path()])
	_check(stuck.is_empty(), "  none inside anything solid (%s)" % str(stuck))
	var lawn_star := -1
	for i in spots.size():
		if town.town.surface_at(spots[i]) == &"grass":
			lawn_star = i
			break
	var coins := _manager.profile.coins
	_put(town.player, spots[lawn_star] + Vector2(0, 400), -PI / 2.0)
	await _frames(3)
	_put(town.player, spots[lawn_star], -PI / 2.0)
	await _frames(10)
	_check(town.stars.found.has(lawn_star), "  driving into one finds it")
	_check(_manager.profile.coins - coins >= GoldenStars.PAY, "  and pays (%d)" % (_manager.profile.coins - coins))
	_check(lawn_star in SaveGame.load_from(SAVE).golden_stars, "  and the save keeps it")
	_put(town.player, spots[lawn_star] + Vector2(0, 400), -PI / 2.0)
	await _frames(3)
	_finished += 1


func _test_jobs() -> void:
	print("the jobs board")
	var town: TownScreen = _screen()
	var day := JobsBoard.pick("2026-10-15")
	var kinds := {}
	for d in 30:
		for kind in JobsBoard.pick("2026-11-%02d" % (d + 1)):
			kinds[kind] = true
	_check(day.size() == 3 and day[0] != day[1] and day[1] != day[2] and day[0] != day[2], "three different jobs a day %s" % str(day))
	_check(JobsBoard.pick("2026-10-15") == day, "  the same all day")
	_check(kinds.size() >= 6, "  and other jobs on other days (%d kinds in a month)" % kinds.size())
	var board := town.jobs
	board.begin("2026-10-15", {}, [&"coins", &"pet", &"wash"])
	var coins := _manager.profile.coins
	for i in 10:
		town.job(&"coins")
	_check(board.today[0]["have"] == 10 and _manager.profile.coins - coins == JobsBoard.JOB_PAY,
		"  picking up ten coins does the coins job and pays %d (%d)" % [JobsBoard.JOB_PAY, _manager.profile.coins - coins])
	board.begin("2026-10-15", _manager.profile.jobs, [&"coins", &"pet", &"wash"])
	_check(board.today[0]["have"] == 10, "  the save remembers it for the rest of the day")
	board.begin("2026-10-16", _manager.profile.jobs, [&"coins", &"pet", &"wash"])
	_check(board.today[0]["have"] == 0, "  and a new day starts afresh")
	board.begin("2026-10-15", _manager.profile.jobs, [&"coins", &"pet", &"wash"])
	coins = _manager.profile.coins
	town.job(&"pet")
	town.job(&"pet")
	EventSystem.CAR_washed.emit(town.player)
	await _frames(2)
	_check(board.all_done(), "  petting twice and the car wash do the other two")
	_check(_manager.profile.coins - coins == 2 * JobsBoard.JOB_PAY + JobsBoard.ALL_PAY,
		"  all three pay the bonus too (%d)" % (_manager.profile.coins - coins))
	_finished += 1


func _test_playground() -> void:
	print("the playground")
	var town: TownScreen = _screen()
	var rides := town.rides
	_check(rides.rides.size() == 4 * town.town.playgrounds.size(), "four rides on each playground (%d)" % rides.rides.size())
	var slide: Dictionary = rides.rides[2]
	_put(town.player, slide["entry"], 0.0)
	await _frames(20)
	_check(rides.on_ride.is_empty(), "  a car does not ride")
	_put(town.player, slide["entry"] + Vector2(-400, 0), 0.0)
	await _frames(5)
	town.get_out()
	await _frames(5)
	var kid := town.kid
	_check(town.riding == &"foot", "  out of the car")
	var mask := kid.collision_mask
	_put(kid, slide["entry"] + Vector2(-20, 0), 0.0)
	await _frames(5)
	_check(not rides.on_ride.is_empty() and kid.frozen, "  walking up to the slide puts him on it")
	var lowest := -INF
	for i in 180:
		await _frames(1)
		lowest = maxf(lowest, kid.global_position.y)
		if rides.on_ride.is_empty():
			break
	_check(lowest > slide["path"][1].y - 20.0, "  down the slide he goes")
	_check(rides.on_ride.is_empty() and not kid.frozen and kid.collision_mask == mask, "  then he can walk again")
	_check(kid.global_position.distance_to(slide["entry"]) < 30.0, "  where he got on")
	await _frames(30)
	_check(rides.on_ride.is_empty(), "  standing there, it does not start again")
	_put(kid, slide["entry"] + Vector2(-300, 0), 0.0)
	await _frames(5)
	_put(kid, slide["entry"], 0.0)
	await _frames(5)
	_check(not rides.on_ride.is_empty(), "  but walking away and back does")
	_finished += 1

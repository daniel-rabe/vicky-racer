extends Node
## Headless checks for coins, buying, equipping and the save file (docs/DESIGN.md §9).
##   Godot_console.exe --path . --headless res://tests/economy_test.tscn
## Exit code 0 = all passed. Uses its own save file, never the player's.

const SAVE := "user://economy_test.cfg"
const ECONOMY := preload("res://game/configs/economy.tres")
const TRACK := &"track_01"

var _failures: PackedStringArray = []
var _refusals := 0


func _ready() -> void:
	EventSystem.PRO_purchase_refused.connect(func(_id: StringName, _r: StringName) -> void: _refusals += 1)
	_test_fresh_profile()
	_test_payouts_and_first_finish_bonus()
	_test_buying()
	_test_best_lap_only_improves()
	_test_save_round_trip()
	_test_unreadable_files_give_fresh_profile()
	_test_two_last_places_afford_cheapest_setup()
	_test_paint()
	_test_version_1_save_migrates()
	_test_every_car_loads()
	_wipe()
	if _failures.is_empty():
		print("ALL ECONOMY TESTS PASSED")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures.append(message)


func _wipe() -> void:
	for path in [SAVE, SAVE + ".bak"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)


func _manager() -> GarageManager:
	var m := GarageManager.new()
	if m == null:
		_failures.append("GarageManager script failed to compile")
		print("  FAIL GarageManager script failed to compile")
		get_tree().quit(1)
	m.economy = ECONOMY
	m.save_path = SAVE
	add_child(m)
	# A script error would leave m half-built and every later check silently skipped;
	# make that a failure instead of a pass.
	_check(m.profile != null, "GarageManager builds and loads a profile")
	return m


func _drop(m: GarageManager) -> void:
	remove_child(m)
	m.free()


func _finish(position: int, best_lap := 40.0) -> void:
	var results := []
	for p in range(1, 5):
		results.append({"name": "YOU" if p == position else "AI", "is_player": p == position,
			"position": p, "time": 120.0 + p, "best_lap": best_lap if p == position else 39.0})
	EventSystem.RAC_race_finished.emit(results, TRACK)


func _test_fresh_profile() -> void:
	print("fresh profile")
	_wipe()
	var m := _manager()
	_check(m.profile.coins == 0, "starts with 0 coins")
	# The Starter car, and the Speedboat for racing on water (docs/DESIGN.md §20).
	_check(m.owns(&"starter") and m.owns(&"speedboat") and m.profile.owned_setups.size() == 2,
		"owns only the Starter car and the Speedboat")
	_check(m.profile.equipped_setup == &"starter", "Starter equipped")
	_drop(m)


func _test_payouts_and_first_finish_bonus() -> void:
	print("payouts")
	_wipe()
	var m := _manager()
	_finish(2)
	_check(m.last_race["amount"] == 175, "first finish in 2nd pays 75 + 100 bonus (got %d)" % m.last_race["amount"])
	var expected := {1: 100, 2: 75, 3: 60, 4: 50}
	for position in expected:
		var before := m.profile.coins
		_finish(position)
		_check(m.profile.coins - before == expected[position],
			"place %d pays %d, no repeat bonus (got %d)" % [position, expected[position], m.profile.coins - before])
	_drop(m)


func _test_buying() -> void:
	print("buying")
	_wipe()
	var m := _manager()
	_refusals = 0
	m.buy(&"banana")
	_check(_refusals == 1 and not m.owns(&"banana") and m.profile.coins == 0, "buying with 0 coins is refused")
	m.profile.coins = 300
	m.buy(&"slider")
	_check(m.owns(&"slider") and m.profile.coins == 50, "buying Slider costs 250 (left %d)" % m.profile.coins)
	_check(m.profile.equipped_setup == &"slider", "a fresh purchase is equipped straight away")
	m.buy(&"slider")
	_check(m.profile.coins == 50, "buying an owned setup again costs nothing")
	m.equip(&"banana")
	_check(m.profile.equipped_setup == &"slider", "cannot equip a setup you do not own")
	_drop(m)


func _test_best_lap_only_improves() -> void:
	print("best lap")
	_wipe()
	var m := _manager()
	_finish(1, 41.0)
	_finish(1, 43.0)
	_check(is_equal_approx(m.profile.best_laps[TRACK], 41.0), "a slower lap does not replace the best")
	_check(not m.last_race["new_best_lap"], "and is not reported as a new best")
	_finish(1, 38.5)
	_check(is_equal_approx(m.profile.best_laps[TRACK], 38.5) and m.last_race["new_best_lap"], "a faster lap does")
	_drop(m)


func _test_save_round_trip() -> void:
	print("save round trip")
	_wipe()
	var m := _manager()
	_finish(1, 37.25)
	m.profile.coins = 400
	m.buy(&"rocket")
	_drop(m)
	var again := _manager()
	var p := again.profile
	_check(p.coins == 150, "coins survive a reload (%d)" % p.coins)
	_check(p.owned_setups == ([&"starter", &"speedboat", &"rocket"] as Array[StringName]), "owned setups survive (%s)" % [p.owned_setups])
	_check(p.equipped_setup == &"rocket", "equipped setup survives")
	_check(TRACK in p.completed_tracks and is_equal_approx(p.best_laps[TRACK], 37.25), "completed tracks and best laps survive")
	_drop(again)


func _test_unreadable_files_give_fresh_profile() -> void:
	print("broken save files")
	_wipe()
	var f := FileAccess.open(SAVE, FileAccess.WRITE)
	f.store_string("this is [not a valid = config file\n")
	f.store_buffer(PackedByteArray([0, 1, 255, 254]))
	f.close()
	var m := _manager()
	_check(m.profile.coins == 0 and m.owns(&"starter"), "a corrupt file gives a fresh profile, no error")
	_check(FileAccess.file_exists(SAVE + ".bak"), "the corrupt file is kept as .bak, not destroyed")
	_drop(m)

	_wipe()
	var future := ConfigFile.new()
	future.set_value("profile", "schema_version", 99)
	future.set_value("profile", "coins", 5000)
	future.save(SAVE)
	m = _manager()
	_check(m.profile.coins == 0, "an unknown schema version gives a fresh profile")
	_drop(m)

	_wipe()
	var odd := ConfigFile.new()
	odd.set_value("profile", "schema_version", SaveGame.SCHEMA_VERSION)
	odd.set_value("profile", "coins", -20)
	odd.set_value("profile", "owned_setups", PackedStringArray(["grippy"]))
	odd.set_value("profile", "equipped_setup", "banana")
	odd.save(SAVE)
	m = _manager()
	_check(m.profile.coins == 0, "negative coins are clamped to 0")
	_check(m.owns(&"starter") and m.owns(&"grippy"), "Starter is always owned")
	_check(m.profile.equipped_setup == &"starter", "equipping an unowned setup falls back to Starter")
	_drop(m)


func _test_two_last_places_afford_cheapest_setup() -> void:
	print("design promise: progress never stalls")
	_wipe()
	var m := _manager()
	m.profile.completed_tracks.append(TRACK)  # no bonus: the worst case
	_finish(4)
	_finish(4)
	_check(m.can_afford(&"grippy"), "two last places afford Grippy (%d coins)" % m.profile.coins)
	_drop(m)


func _test_paint() -> void:
	print("paint shop")
	_wipe()
	var m := _manager()
	m.repaint(&"grippy")
	_check(not m.profile.paint.has(&"grippy"), "a car you do not own cannot be painted")
	m.repaint(&"starter")
	_check(m.profile.paint.get(&"starter") == &"blue", "painting cycles original -> blue")
	for i in Paint.COLOURS.size() - 1:
		m.repaint(&"starter")
	_check(not m.profile.paint.has(&"starter"), "and round the palette back to the original")
	m.repaint(&"starter")
	m.repaint(&"starter")
	_drop(m)
	m = _manager()
	_check(m.profile.paint.get(&"starter") == &"yellow", "paint survives a save and load (%s)" % m.profile.paint)
	var starter: DriftSetup = load("res://game/configs/setups/starter.tres")
	_check(Paint.body(starter, &"yellow") != starter.body, "a painted car has its own race body")
	_check(Paint.body(starter, Paint.ORIGINAL) == starter.body, "the original paint is the car's own body")
	_drop(m)


func _test_version_1_save_migrates() -> void:
	print("save version 1 -> 2")
	_wipe()
	var old := ConfigFile.new()
	old.set_value("profile", "schema_version", 1)
	old.set_value("profile", "coins", 480)
	old.set_value("profile", "owned_setups", PackedStringArray(["starter", "kart"]))
	old.set_value("profile", "equipped_setup", "kart")
	old.save(SAVE)
	var m := _manager()
	_check(m.profile.coins == 480 and m.owns(&"kart") and m.profile.equipped_setup == &"kart",
		"a version 1 save keeps its coins, cars and equipped car (%d coins)" % m.profile.coins)
	_check(m.profile.paint.is_empty(), "with no paint yet")
	m.repaint(&"kart")
	var saved := ConfigFile.new()
	saved.load(SAVE)
	_check(int(saved.get_value("profile", "schema_version")) == SaveGame.SCHEMA_VERSION,
		"it is written back as the current version")
	_drop(m)
	var v2 := ConfigFile.new()
	v2.set_value("profile", "schema_version", 2)
	v2.set_value("profile", "coins", 300)
	v2.set_value("best_laps", "track_01", 15.2)
	v2.save(SAVE)
	m = _manager()
	_check(m.profile.coins == 300 and m.profile.best_laps.is_empty(),
		"a version 2 save keeps its coins but drops best laps set on the old, shorter tracks")
	_drop(m)


func _test_every_car_loads() -> void:
	print("the roster")
	_wipe()
	var m := _manager()
	var cars := m.setups.values().filter(func(s: DriftSetup) -> bool: return s.kind == &"car")
	_check(cars.size() == 13, "thirteen cars in the garage (%d)" % cars.size())
	for id in GarageManager.SETUP_ORDER:
		var setup: DriftSetup = m.setups[id]
		_check(setup != null and setup.id == id and setup.card_art != null and setup.body != null,
			"%s loads with its card and body" % id)
		for colour in Paint.COLOURS:
			if Paint.body(setup, colour) == null or (colour != Paint.ORIGINAL and Paint.body(setup, colour) == setup.body):
				_check(false, "%s has a %s paint job" % [id, colour])
	var prices := GarageManager.SETUP_ORDER.map(func(id: StringName) -> int: return m.setups[id].price)
	var sorted := prices.duplicate()
	sorted.sort()
	_check(prices == sorted, "the garage is in price order (%s)" % [prices])
	_drop(m)

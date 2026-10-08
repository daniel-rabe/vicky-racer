extends Node
## Headless checks for stickers and the trophy shelf (docs/DESIGN.md §14).
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/sticker_test.tscn -- --autopilot
## Part 1 triggers every sticker through the event bus, as the race and the garage send it,
## and checks each is earned exactly once, only by the player and only in a race, and is
## kept across closing the game. Part 2 earns the two drift stickers with a real car's
## physics. Part 3 races Track 01 through the real screens (the player's car on autopilot)
## and opens the shelf. Exit code 0 = all passed. Uses its own save and settings files.
## With a window and `--screenshots=<dir>`, also saves the shelf and a sticker popping in.

const MAIN := preload("res://game/main.tscn")
const ECONOMY := preload("res://game/configs/economy.tres")
const CAR_SCENE := preload("res://actors/car/car.tscn")
const BOAT_SCENE := preload("res://actors/boat/boat.tscn")
const SHIP_SCENE := preload("res://actors/ship/ship.tscn")
const SAVE := "user://sticker_test.cfg"
const SETTINGS := "user://sticker_test_settings.cfg"

var _failures: PackedStringArray = []
var _garage: GarageManager
var _cups: CupManager
var _stickers: StickerManager
var _popup: StickerPopup
var _player: Node2D
var _ai: Node2D
## Every PRO_sticker_earned, in order: a sticker earned twice would show up twice here.
var _emitted: Array[StringName] = []
var _shots_dir := ""


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			_shots_dir = arg.get_slice("=", 1)
	EventSystem.PRO_sticker_earned.connect(func(id: StringName) -> void: _emitted.append(id))
	_player = _fake_car("PlayerMarker")
	_ai = _fake_car("Driver")
	_wipe()
	_test_definitions()
	_test_drift_stickers()
	_test_clean_lap()
	_test_first_win_and_coins()
	_test_every_track_and_all_cars()
	await _test_boat_and_space_stickers()
	_test_never_twice_never_lost()
	await _test_popup()
	_drop()
	_wipe()
	await _test_real_drift()
	_wipe()
	await _test_race_and_shelf()
	_wipe()
	if _failures.is_empty():
		print("ALL STICKER TESTS PASSED")
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
	for path in [SAVE, SAVE + ".bak", SETTINGS]:
		DirAccess.remove_absolute(path)


## A stand-in for a car: the sticker rules only ask whether it is the player's.
func _fake_car(child_name: String) -> Node2D:
	var car := Node2D.new()
	var child := Node.new()
	child.name = child_name
	car.add_child(child)
	add_child(car)
	return car


## The shell's managers on the test save, in the shell's order.
func _managers() -> void:
	_drop()
	_garage = GarageManager.new()
	_garage.economy = ECONOMY
	_garage.save_path = SAVE
	add_child(_garage)
	_cups = CupManager.new()
	add_child(_cups)
	_stickers = StickerManager.new()
	_stickers.economy = ECONOMY
	add_child(_stickers)
	_popup = StickerPopup.new()
	add_child(_popup)


func _drop() -> void:
	for node in [_popup, _stickers, _cups, _garage]:
		if is_instance_valid(node):
			remove_child(node)
			node.free()


func _finish(position: int, track_id := &"track_01") -> void:
	var results := []
	var others := ["BLUE", "YELLOW", "GREEN"]
	for place in range(1, 5):
		var is_player := place == position
		results.append({"name": "YOU" if is_player else others.pop_front(), "body": "res://art/cars/car_red.png",
			"is_player": is_player, "position": place, "time": 60.0 + place, "best_lap": 20.0})
	EventSystem.RAC_race_finished.emit(results, track_id)


func _count(id: StringName) -> int:
	return _emitted.count(id)


func _test_definitions() -> void:
	print("the sticker book")
	_managers()
	_check(_stickers.stickers.size() == StickerManager.ORDER.size() and StickerManager.ORDER.size() == 11,
		"eleven stickers (%d)" % _stickers.stickers.size())
	for id: StringName in StickerManager.ORDER:
		var sticker: StickerConfig = _stickers.stickers[id]
		_check(sticker != null and sticker.id == id and sticker.texture != null and sticker.hint != "",
			"%s has its id, picture and hint" % id)
	_check(_stickers.earned.is_empty() and _garage.profile.stickers.is_empty(), "a new save has no stickers")


func _test_drift_stickers() -> void:
	print("drift stickers")
	EventSystem.CAR_drift_started.emit(_player)
	_check(_count(&"drift") == 0, "no sticker outside a race (the title's attract mode, the test field)")
	EventSystem.RAC_race_started.emit()
	EventSystem.CAR_drift_started.emit(_ai)
	EventSystem.CAR_drift_ended.emit(_ai, 5.0)
	_check(_emitted.is_empty(), "an opponent's drift earns nothing")
	EventSystem.CAR_drift_started.emit(_player)
	_check(_count(&"drift") == 1 and _stickers.has(&"drift"), "the player's first drift earns FIRST DRIFT")
	_check(&"drift" in _garage.profile.stickers, "and it is saved")
	EventSystem.CAR_drift_ended.emit(_player, StickerManager.LONG_DRIFT_SECONDS - 0.1)
	_check(_count(&"long_drift") == 0, "a drift just under 3 s is not a super drift")
	EventSystem.CAR_drift_started.emit(_player)
	EventSystem.CAR_drift_ended.emit(_player, StickerManager.LONG_DRIFT_SECONDS + 0.1)
	_check(_count(&"long_drift") == 1, "a drift over 3 s earns SUPER DRIFT")
	_check(_count(&"drift") == 1, "drifting again does not earn FIRST DRIFT again")


func _test_clean_lap() -> void:
	print("clean lap")
	EventSystem.RAC_race_started.emit()
	EventSystem.CAR_wall_hit.emit(_player, 300.0)
	EventSystem.RAC_lap_completed.emit(_player, 1, 30.0)
	_check(_count(&"clean_lap") == 0, "a lap with a wall hit earns nothing")
	EventSystem.CAR_wall_hit.emit(_ai, 300.0)
	EventSystem.RAC_lap_completed.emit(_ai, 1, 30.0)
	_check(_count(&"clean_lap") == 0, "an opponent's clean lap earns nothing")
	EventSystem.RAC_lap_completed.emit(_player, 2, 30.0)
	_check(_count(&"clean_lap") == 1, "the next lap, with no wall hit, earns CAREFUL DRIVER")


func _test_first_win_and_coins() -> void:
	print("first win and a pile of coins")
	EventSystem.RAC_race_started.emit()
	_finish(2, &"track_02")  # 75 + 100 for a new track: 175
	_check(_count(&"first_win") == 0 and _count(&"coins") == 0, "2nd on a new track (175 coins): neither")
	EventSystem.RAC_race_started.emit()
	_finish(4)  # 50 + 100 (track 01 is new too): 150
	_check(_count(&"coins") == 0, "150 coins from a race is not the pile")
	EventSystem.RAC_race_started.emit()
	_finish(4)
	EventSystem.CUP_finished.emit(&"sunshine", [], &"silver")  # 50 + the 200 silver bonus
	_check(_count(&"coins") == 1, "the cup bonus counts: 50 + 200 earns PILE OF COINS")
	EventSystem.RAC_race_started.emit()
	_finish(1)
	_check(_count(&"first_win") == 1, "a win earns FIRST WIN")
	EventSystem.RAC_race_started.emit()
	_finish(1)
	_check(_count(&"first_win") == 1, "and a second win does not earn it again")


func _test_every_track_and_all_cars() -> void:
	print("every track, every car")
	var rest := GarageManager.TRACK_ORDER.slice(2)  # track_01 and track_02 are finished above
	for id: StringName in rest.slice(0, rest.size() - 1):
		EventSystem.RAC_race_started.emit()
		_finish(3, id)
	_check(_count(&"every_track") == 0, "every track but one: not yet")
	EventSystem.RAC_race_started.emit()
	_finish(3, rest[-1])
	_check(_count(&"every_track") == 1, "the last track earns EXPLORER")
	_garage.profile.coins = 100000
	var ids := GarageManager.SETUP_ORDER.filter(func(id: StringName) -> bool: return not _garage.owns(id))
	for id: StringName in ids.slice(0, ids.size() - 1):
		EventSystem.PRO_buy_requested.emit(id)
	_check(_count(&"all_cars") == 0, "all cars but one: not yet")
	EventSystem.PRO_buy_requested.emit(ids[-1])
	_check(_count(&"all_cars") == 1, "buying the last car earns CAR COLLECTOR")


## A race finished in a boat, then in a ship (docs/DESIGN.md §20, §24); the boat and space cups won.
func _test_boat_and_space_stickers() -> void:
	print("boats and spaceships")
	for pair in [[BOAT_SCENE, &"first_splash"], [SHIP_SCENE, &"first_flight"]]:
		var vehicle: Car = (pair[0] as PackedScene).instantiate()
		var marker := Node2D.new()
		marker.name = "PlayerMarker"
		vehicle.add_child(marker)
		add_child(vehicle)
		await get_tree().physics_frame
		EventSystem.RAC_race_started.emit()
		_finish(3, &"boat_01" if pair[1] == &"first_splash" else &"space_01")
		_check(_count(pair[1]) == 1, "finishing a race in a %s earns %s" % ["boat" if pair[1] == &"first_splash" else "ship", pair[1]])
		vehicle.free()
	EventSystem.CUP_finished.emit(&"splash", [], &"silver")
	_check(_count(&"splash_cup") == 0, "2nd in the Splash Cup does not earn its sticker")
	EventSystem.CUP_finished.emit(&"splash", [], &"gold")
	EventSystem.CUP_finished.emit(&"comet", [], &"gold")
	_check(_count(&"splash_cup") == 1 and _count(&"comet_cup") == 1, "winning the Splash and Comet Cups earns theirs")


func _test_never_twice_never_lost() -> void:
	print("never twice, never lost")
	var all := StickerManager.ORDER.size()
	_check(_stickers.earned.size() == all and _garage.profile.stickers.size() == all, "all %d are in the book" % all)
	for id: StringName in StickerManager.ORDER:
		_check(_count(id) == 1, "%s was earned exactly once" % id)
	_emitted.clear()
	_managers()  # as if the game was closed and opened again
	_check(_garage.profile.stickers.size() == all and _stickers.earned.size() == all, "the book survives closing the game")
	_check(_emitted.is_empty(), "loading the save awards nothing again, though every condition still holds")
	EventSystem.RAC_race_started.emit()
	EventSystem.CAR_drift_started.emit(_player)
	_finish(1)
	_check(_emitted.is_empty(), "nor does doing it all again")
	_garage.profile.stickers.clear()
	_garage.profile.save_to(SAVE)
	_garage.profile.stickers.append(&"drift")
	_garage.profile.save_to(SAVE)
	var file := ConfigFile.new()
	file.load(SAVE)
	_check(Array(file.get_value("stickers", "earned", [])) == ["drift"], "the save keeps them in [stickers] earned")


func _test_popup() -> void:
	print("the popup")
	_wipe()
	_managers()
	EventSystem.RAC_race_started.emit()
	_finish(1, &"track_01")  # a win on a new track: 200 coins, and the first win
	_check(_popup.current != null and _popup.current.id == &"coins", "a new sticker pops up straight away")
	await get_tree().create_timer(1.0).timeout
	_check(_popup.current.id == &"coins", "a second one, earned at the same moment, waits its turn")
	await get_tree().create_timer(3.0).timeout
	_check(_popup.current != null and _popup.current.id == &"first_win", "then pops up after the first")
	await get_tree().create_timer(3.0).timeout
	_check(_popup.current == null, "and the screen is clear again after both")


## Real physics: hold the handbrake and steer round in a circle.
func _test_real_drift() -> void:
	print("drifting a real car")
	_managers()
	var car: Car = CAR_SCENE.instantiate()
	car.setup = load("res://game/configs/setups/starter.tres")
	car.position = Vector2(5000, 5000)
	var marker := Node2D.new()
	marker.name = "PlayerMarker"
	car.add_child(marker)
	add_child(car)
	EventSystem.RAC_race_started.emit()
	for i in 90:  # get up to speed
		car.throttle_input = 1.0
		await get_tree().physics_frame
	for i in 300:  # five seconds sliding round in a circle
		car.throttle_input = 1.0
		car.steer_input = 1.0
		car.handbrake = true
		await get_tree().physics_frame
	for i in 60:  # straighten up, so the drift ends
		car.steer_input = 0.0
		car.handbrake = false
		car.throttle_input = -1.0
		await get_tree().physics_frame
	_check(_stickers.has(&"drift"), "a real handbrake slide earns FIRST DRIFT")
	_check(_stickers.has(&"long_drift"), "holding it round a circle earns SUPER DRIFT")
	car.queue_free()
	_drop()


## The real thing: a race on Track 01 (autopilot), then the shelf from the title.
func _test_race_and_shelf() -> void:
	print("a race and the shelf on screen")
	if not Array(OS.get_cmdline_user_args()).has("--autopilot"):
		_check(false, "run with -- --autopilot, or the player's car never moves")
		return
	var main := MAIN.instantiate()
	main.get_node("GarageManager").save_path = SAVE
	main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(main)
	await get_tree().process_frame
	EventSystem.UI_screen_requested.emit(&"race")
	var popup: StickerPopup = main.get_node("StickerPopup")
	var waited := 0.0
	while popup.current == null and waited < 120.0:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	_check(popup.current != null, "a sticker pops up during the race (%s)" % (popup.current.id if popup.current else &"none"))
	await get_tree().create_timer(0.8).timeout
	await _shot("sticker_popup")
	var results := await _wait_for_screen(main, "ResultsScreen", 200.0)
	_check(results != null, "the race finishes")
	var garage: GarageManager = main.get_node("GarageManager")
	var earned := garage.profile.stickers
	_check(&"clean_lap" in earned or &"drift" in earned or &"first_win" in earned,
		"a real race earns stickers (%s)" % [earned])
	EventSystem.UI_screen_requested.emit(&"title")
	var title := await _wait_for_screen(main, "TitleScreen", 5.0)
	_check(title != null and title.get_node("%Shelf").visible, "the title has the trophy-shelf button")
	if title:
		title.get_node("%Shelf").pressed.emit()
	var shelf := await _wait_for_screen(main, "ShelfScreen", 5.0)
	_check(shelf != null, "it opens the shelf")
	if shelf:
		var won := 0
		for id: StringName in StickerManager.ORDER:
			var slot: Button = shelf.get_node("Sticker_" + String(id))
			won += 1 if slot.get_meta(&"won") else 0
		_check(won == earned.size(), "the book shows exactly the stickers earned (%d)" % won)
		_check(shelf.has_node("Trophy_sunshine") and shelf.has_node("Trophy_snowflake"), "a shelf place for each cup")
		_check(not shelf.get_node("Trophy_sunshine").get_meta(&"won"), "no cup raced: the trophies are outlines")
		var focused := shelf.get_viewport().gui_get_focus_owner()
		_check(focused != null and focused.name == "Trophy_sunshine", "the first trophy has the focus")
		while popup.current != null:  # the race's last stickers may still be popping up
			await get_tree().create_timer(0.25).timeout
		await get_tree().create_timer(1.0).timeout
		await _shot("shelf")
		shelf.get_node("Back").pressed.emit()
		_check(await _wait_for_screen(main, "TitleScreen", 5.0) != null, "BACK returns to the title")
	main.queue_free()
	await get_tree().create_timer(0.5).timeout  # let audio mix once before quitting (see main.gd)


func _shot(shot_name: String) -> void:
	if _shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(shot_name + ".png"))


func _wait_for_screen(main: Node, screen_name: String, seconds: float) -> Node:
	var waited := 0.0
	while waited < seconds:
		for child in main.get_node("ScreenSlot").get_children():
			if child.name == screen_name and not child.is_queued_for_deletion():
				return child
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	return null

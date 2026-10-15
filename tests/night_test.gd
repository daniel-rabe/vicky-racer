extends Node
## Headless checks for night (docs/DESIGN.md §27).
##   Godot_console.exe --path . --headless --fixed-fps 60 res://tests/night_test.tscn
## The title's sun / moon button turns night on and off (the race behind the menu with it);
## a race at night has the dark and every car's lights, also in the rain (one CanvasModulate,
## the weather's) and on the boats, but not in space; Free Drive at night lights the
## player's car, the traffic, the boat made at the harbour and every house's porch. With a
## window and `--screenshots=<dir>`, also saves the race and the town. N switches day and night
## mid-race, mid-drive, paused and on a menu. Exit code 0 = all passed.

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://night_test.cfg"
const SETTINGS := "user://night_test_settings.cfg"

var _failures: PackedStringArray = []
var _shots_dir := ""
var _main: Node


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshots="):
			_shots_dir = arg.get_slice("=", 1)
	_wipe()
	var save := ConfigFile.new()  # every track open
	save.set_value("profile", "schema_version", SaveGame.SCHEMA_VERSION)
	save.set_value("profile", "completed_tracks", PackedStringArray(GarageManager.TRACK_ORDER
		+ GarageManager.BOAT_TRACK_ORDER + GarageManager.SHIP_TRACK_ORDER))
	save.save(SAVE)
	_main = MAIN.instantiate()
	_main.get_node("GarageManager").save_path = SAVE
	_main.get_node("SettingsManager").settings_path = SETTINGS
	add_child(_main)
	await get_tree().process_frame
	await _test_title()
	await _test_race(&"car", &"track_01", true)
	await _test_rain()
	await _test_race(&"boat", &"boat_01", true)
	await _test_race(&"ship", &"space_01", false)
	await _test_town()
	await _test_day()
	await _test_key()
	_main.queue_free()
	await get_tree().create_timer(0.5).timeout
	_wipe()
	if _failures.is_empty():
		print("ALL NIGHT TESTS PASSED")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _test_title() -> void:
	print("the title's sun / moon button")
	EventSystem.UI_screen_requested.emit(&"title")
	await _frames(3)
	var title := _screen()
	var button: Button = title.find_child("DayNight", true, false)
	_check(button != null, "a day / night button on the title")
	if button == null:
		return
	_check(button.icon == SkyIcons.sun(), "it shows the sun by day")
	button.pressed.emit()
	await _frames(3)
	_check(_main.get_node("GarageManager").night, "pressing it turns night on")
	_check(button.icon == SkyIcons.moon(), "and it shows the moon")
	_check(title.get_node("World").has_node("Night"), "the race behind the menu goes dark")
	_check(_all_lit(title), "and its cars have their lights on")


func _test_race(kind: StringName, track: StringName, dark: bool) -> void:
	print("a %s race at night" % kind)
	EventSystem.PRO_vehicle_kind_requested.emit(kind)
	EventSystem.PRO_track_select_requested.emit(track)
	EventSystem.PRO_race_mode_requested.emit(&"race")
	EventSystem.UI_screen_requested.emit(&"race")
	await _frames(5)
	var race := _screen()
	var night: Night = race.get_node_or_null("Night")
	if not dark:
		_check(night == null and _modulates(race).is_empty(), "space stays as it is: it is night there already")
		return
	_check(night != null, "the race has a Night")
	var modulates := _modulates(race)
	_check(modulates.size() == 1 and modulates[0].color == Night.TINT, "the world is dark blue (one CanvasModulate)")
	var lit: Array = race.racers.filter(func(r: Dictionary) -> bool: return r["car"].has_node("Body/Lights"))
	_check(race.racers.size() == 4 and lit.size() == 4, "all four have their lights on (%d of %d)" % [lit.size(), race.racers.size()])
	if kind == &"car":
		await get_tree().create_timer(6.0).timeout
		await _shot("race_night")


func _test_rain() -> void:
	print("rain at night")
	EventSystem.PRO_vehicle_kind_requested.emit(&"car")
	EventSystem.PRO_track_select_requested.emit(&"track_01")
	EventSystem.UI_screen_requested.emit(&"race")
	await _frames(5)
	var race := _screen()
	# The race's own pick is random: if it is dry, start again with a shower, as the race would.
	var weather: Weather = race.get_node_or_null("Weather")
	if weather == null:
		var night: Night = race.get_node("Night")
		race.remove_child(night)
		night.queue_free()
		await _frames(2)
		weather = RaceWeather.new()
		weather.name = "Weather"
		weather.track = race.track
		weather.repeat = false
		weather.rain_now(30.0)
		race.add_child(weather)
		night = Night.new()
		night.weather = weather
		race.add_child(night)
	elif weather.kind == &"rain":
		weather.rain_now(30.0)
	await get_tree().create_timer(4.0).timeout
	var modulates := _modulates(race)
	_check(modulates.size() == 1, "still one CanvasModulate, the weather's (%d)" % modulates.size())
	_check(weather.tint == Night.TINT and modulates[0].color.b < Night.TINT.b, "the rain darkens the night more")
	_check(_all_lit(race), "the cars keep their lights")


func _test_town() -> void:
	print("Free Drive at night")
	EventSystem.PRO_vehicle_kind_requested.emit(&"car")
	EventSystem.UI_screen_requested.emit(&"town")
	await _frames(5)
	var town := _screen()
	_check(town.night != null and town.night.weather == town.weather, "the town has a Night, darkening the weather's light")
	_check(town.weather.tint == Night.TINT, "the town is dark blue")
	_check(town.player.has_node("Body/Lights"), "the player's car has its lights on")
	_check(not town.traffic.is_empty() and town.traffic.all(func(car: Car) -> bool: return car.has_node("Body/Lights")),
		"so has all the traffic (%d cars)" % town.traffic.size())
	var porches: Node = town.get_node("World/PorchLights")
	_check(porches.get_child_count() == town.town.houses.size(), "a lamp by every front door (%d)" % porches.get_child_count())
	await get_tree().create_timer(3.0).timeout
	await _shot("town_night")
	town._swap_now(&"boat")
	await _frames(5)
	_check(town.boat and town.boat.has_node("Body/Lights"), "the boat made at the harbour gets lights too")


func _test_day() -> void:
	print("back to day")
	EventSystem.UI_screen_requested.emit(&"title")
	await _frames(3)
	var title := _screen()
	(title.find_child("DayNight", true, false) as Button).pressed.emit()
	await _frames(3)
	_check(not _main.get_node("GarageManager").night, "pressing it again turns night off")
	_check(not title.get_node("World").has_node("Night") and _modulates(title).is_empty(), "the race behind the menu is day again")
	_check(get_tree().get_nodes_in_group(&"cars").all(func(car: Node) -> bool: return not car.has_node("Body/Lights")),
		"and the lights are off")
	EventSystem.UI_screen_requested.emit(&"race")
	await _frames(5)
	_check(not _screen().has_node("Night"), "races are in the day again")


func _test_key() -> void:
	print("the N key")
	var garage: GarageManager = _main.get_node("GarageManager")
	EventSystem.PRO_vehicle_kind_requested.emit(&"car")
	EventSystem.PRO_track_select_requested.emit(&"track_01")
	EventSystem.UI_screen_requested.emit(&"race")
	await _frames(5)
	var race := _screen()
	_check(not race.has_node("Night"), "the race starts in the day")
	await _press_n()
	_check(garage.night and race.has_node("Night"), "N mid-race: night at once")
	await get_tree().create_timer(0.3).timeout
	await _shot("key_race_moon")
	_check(_all_lit(race) and _modulates(race).size() == 1, "the lights come on, one CanvasModulate")
	get_tree().paused = true
	await _press_n()
	_check(not garage.night and not race.has_node("Night"), "N while paused: day again")
	await _frames(2)
	var weather: Weather = race.get_node_or_null("Weather")  # a shower keeps its own gloom
	var dark := _modulates(race).filter(func(m: CanvasModulate) -> bool: return m.name == "NightDark")
	_check(dark.is_empty() and (weather == null or weather.tint == Color.WHITE) and not _all_lit(race),
		"the dark and the lights go")
	get_tree().paused = false
	EventSystem.UI_screen_requested.emit(&"garage")
	await _frames(3)
	await _press_n()
	_check(garage.night, "N on a menu switches too")
	EventSystem.UI_screen_requested.emit(&"town")
	await _frames(5)
	var town := _screen()
	_check(town.night != null and town.get_node("World").has_node("PorchLights"), "so the town starts at night")
	await _press_n()
	await get_tree().create_timer(0.3).timeout
	await _shot("key_town_sun")
	_check(town.night == null and not town.get_node("World").has_node("PorchLights") and town.weather.tint == Color.WHITE,
		"N mid-drive: the porch lamps go out and the town is light")
	await _press_n()
	await _frames(2)
	_check(town.night != null and town.player.has_node("Body/Lights"), "and N again: night once more")
	await _press_n()


func _press_n() -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = KEY_N
		event.pressed = pressed
		Input.parse_input_event(event)
		await _frames(2)


func _all_lit(screen: Node) -> bool:
	var cars := get_tree().get_nodes_in_group(&"cars").filter(func(car: Node) -> bool: return screen.is_ancestor_of(car))
	return not cars.is_empty() and cars.all(func(car: Node) -> bool: return car.has_node("Body/Lights"))


func _modulates(screen: Node) -> Array:
	return screen.find_children("*", "CanvasModulate", true, false).filter(func(n: Node) -> bool:
		return not n.is_queued_for_deletion())


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures.append(message)


func _screen() -> Node:
	for child in _main.get_node("ScreenSlot").get_children():
		if not child.is_queued_for_deletion():
			return child
	return null


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	if _shots_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(_shots_dir.path_join(shot_name + ".png"))


func _wipe() -> void:
	for path in [SAVE, SAVE + ".bak", SETTINGS]:
		DirAccess.remove_absolute(path)

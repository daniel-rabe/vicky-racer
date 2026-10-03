extends Node
## Regression test: the setup equipped in the garage is the one the player's car races with.
## Starts the real game shell with a save that has Grippy equipped and opens the race.
##   Godot_console.exe --path . --headless res://tests/race_setup_test.tscn -- --save=user://race_setup_test.cfg --screen=race

const MAIN := preload("res://game/main.tscn")
const SAVE := "user://race_setup_test.cfg"

var _failures: PackedStringArray = []


func _ready() -> void:
	var save := ConfigFile.new()
	save.set_value("profile", "schema_version", SaveGame.SCHEMA_VERSION)
	save.set_value("profile", "coins", 0)
	save.set_value("profile", "owned_setups", PackedStringArray(["starter", "grippy"]))
	save.set_value("profile", "equipped_setup", "grippy")
	save.save(SAVE)
	var main := MAIN.instantiate()
	add_child(main)
	await get_tree().create_timer(0.5).timeout
	var player: Car = null
	for car: Car in get_tree().get_nodes_in_group(&"cars"):
		if car.has_node("PlayerInput"):
			player = car
	_check(player != null, "the race has a player car")
	if player:
		var grippy: DriftSetup = load("res://game/configs/setups/grippy.tres")
		_check(player.setup != null and player.setup.id == &"grippy",
			"the player's car carries the equipped setup (got %s)" % (player.setup.id if player.setup else &"none"))
		_check(is_equal_approx(player.config.lateral_grip, 9.0 * grippy.lateral_grip_mult),
			"its handling is Grippy's (lateral grip %.2f, expected %.2f)" % [player.config.lateral_grip, 9.0 * grippy.lateral_grip_mult])
		_check(player.get_node("Body").texture == grippy.body,
			"it looks like the Grippy car (body %s)" % player.get_node("Body").texture.resource_path.get_file())
	DirAccess.remove_absolute(SAVE)
	if _failures.is_empty():
		print("ALL RACE SETUP TESTS PASSED")
		get_tree().quit(0)
	else:
		for f in _failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check(condition: bool, message: String) -> void:
	print(("  ok   " if condition else "  FAIL ") + message)
	if not condition:
		_failures.append(message)

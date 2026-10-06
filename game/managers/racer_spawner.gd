class_name RacerSpawner
extends Node
## Puts the cars on the grid: the player (or both players) in their car and paint, with
## camera and controls, and the opponents in the cars and paints from the TrackConfig, with
## AI drivers in staggered lanes.
## Returns one Dictionary per racer, the shape RaceManager and the HUD work with:
## car, name, body (sprite path), colour, is_player, player (1 or 2; 0 for the AI), driver.

const CAR_SCENE := preload("res://actors/car/car.tscn")
const CAMERA_SCRIPT := preload("res://actors/car/chase_camera.gd")
const PLAYER_INPUT := preload("res://actors/car/player_input.gd")
const PLAYER_MARKER := preload("res://actors/car/player_marker.gd")
const PLAYER_COLOUR := Color(0.902, 0.224, 0.275)
## AI lanes, px either side of the racing line, so the pack spreads across the road.
const LANES: Array[float] = [-70.0, 70.0, 0.0]


## One player's car, in their car and paint (`humans`, one Dictionary per player: setup,
## paint, and in a two-player race name, colour, number and action_prefix).
## `autopilot`: the players' cars are driven by AIDrivers too (headless race tests).
## `difficulty` shifts every opponent's skill (DifficultyConfig.skill_offset).
## `with_ai`: false leaves the opponents out (two players racing only each other).
func spawn(track: Track, config: TrackConfig, humans: Array[Dictionary], parent: Node,
		autopilot := false, difficulty: DifficultyConfig = null, with_ai := true) -> Array[Dictionary]:
	var skill_offset := difficulty.skill_offset if difficulty else 0.0
	var grid := track.grid_transforms()
	var human_slots := _human_slots(config.player_slot - 1, humans.size(), grid.size())
	var racers: Array[Dictionary] = []
	var opponent := 0
	# Cars, or boats on a water course (docs/DESIGN.md §20): whatever the race is raced in.
	var scene: PackedScene = config.vehicle_scene if config.vehicle_scene else CAR_SCENE
	for slot in grid.size():
		var car: Car = scene.instantiate()
		var human := human_slots.find(slot)
		var racer := {"car": car, "is_player": human >= 0, "player": human + 1}
		if human >= 0:
			var who: Dictionary = humans[human]
			car.setup = who["setup"]
			car.body_texture = Paint.body(who["setup"], who.get("paint", Paint.ORIGINAL))
			racer.merge({"name": who.get("name", "YOU"), "body": car.body_texture.resource_path,
				"colour": who.get("colour", PLAYER_COLOUR)})
			if autopilot:
				racer["driver"] = _ai(car, track, 1.0, 0.0)
			else:
				var input := Node.new()
				input.name = "PlayerInput"
				input.set_script(PLAYER_INPUT)
				input.track = track  # for steering help
				input.action_prefix = who.get("action_prefix", "")
				car.add_child(input)
			car.add_child(_camera_rig())
			var marker := Node2D.new()
			marker.name = "PlayerMarker"
			marker.set_script(PLAYER_MARKER)
			if humans.size() > 1:
				marker.fill = racer["colour"]
			car.add_child(marker)
		else:
			if not with_ai or opponent >= config.opponent_setups.size():
				car.free()
				continue
			var setup: DriftSetup = config.opponent_setups[opponent]
			car.setup = setup
			var body := Paint.body(setup, config.opponent_paints[opponent])
			car.body_texture = body
			racer.merge({"name": config.opponent_names[opponent], "body": body.resource_path,
				"colour": config.opponent_colours[opponent]})
			var skill := clampf(config.opponent_skills[opponent] + skill_offset, 0.0, 1.0)
			racer["driver"] = _ai(car, track, skill, LANES[opponent % LANES.size()])
			racer["driver"].pace_from_base = true
			opponent += 1
		car.name = racer["name"].capitalize()
		car.frozen = true
		car.transform = grid[slot]
		parent.add_child(car)
		car.reset_physics_interpolation()
		racers.append(racer)
	return racers


## Grid slots (0-based) for the players: the track's player slot, and for a second player
## the slot beside it in the same row (the grid is two wide), so neither starts ahead.
static func _human_slots(first: int, count: int, slots: int) -> Array[int]:
	var out: Array[int] = [clampi(first, 0, slots - 1)]
	if count > 1:
		var beside := out[0] + 1 if out[0] % 2 == 0 else out[0] - 1
		out.append(beside if beside < slots else out[0] - 1)
	return out


func _ai(car: Car, track: Track, skill: float, lane: float) -> AIDriver:
	var driver := AIDriver.new()
	driver.name = "AIDriver"
	driver.skill = skill
	driver.line_offset = lane
	driver.track = track
	car.add_child(driver)
	return driver


func _camera_rig() -> Node2D:
	var rig := Node2D.new()
	rig.name = "ChaseCamera"
	rig.set_script(CAMERA_SCRIPT)
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	rig.add_child(camera)
	return rig

class_name RacerSpawner
extends Node
## Puts the four cars on the grid: the player in their equipped car and paint, with camera
## and controls, and the opponents in the cars and paints from the TrackConfig, with AI
## drivers in staggered lanes.
## Returns one Dictionary per racer, the shape RaceManager and the HUD work with:
## car, name, body (sprite path), colour, is_player, driver.

const CAR_SCENE := preload("res://actors/car/car.tscn")
const CAMERA_SCRIPT := preload("res://actors/car/chase_camera.gd")
const PLAYER_INPUT := preload("res://actors/car/player_input.gd")
const PLAYER_MARKER := preload("res://actors/car/player_marker.gd")
const PLAYER_COLOUR := Color(0.902, 0.224, 0.275)
## AI lanes, px either side of the racing line, so the pack spreads across the road.
const LANES: Array[float] = [-70.0, 70.0, 0.0]


## `autopilot`: the player's car is driven by an AIDriver too (headless race tests).
## `difficulty` shifts every opponent's skill (DifficultyConfig.skill_offset).
func spawn(track: Track, config: TrackConfig, player_setup: DriftSetup, parent: Node,
		autopilot := false, difficulty: DifficultyConfig = null, player_paint := Paint.ORIGINAL) -> Array[Dictionary]:
	var skill_offset := difficulty.skill_offset if difficulty else 0.0
	var grid := track.grid_transforms()
	var racers: Array[Dictionary] = []
	var opponent := 0
	for slot in grid.size():
		var car: Car = CAR_SCENE.instantiate()
		var is_player := slot + 1 == config.player_slot
		var racer := {"car": car, "is_player": is_player}
		if is_player:
			car.setup = player_setup
			car.body_texture = Paint.body(player_setup, player_paint)
			racer.merge({"name": "YOU", "body": car.body_texture.resource_path, "colour": PLAYER_COLOUR})
			if autopilot:
				racer["driver"] = _ai(car, track, 1.0, 0.0)
			else:
				var input := Node.new()
				input.name = "PlayerInput"
				input.set_script(PLAYER_INPUT)
				input.track = track  # for steering help
				car.add_child(input)
			car.add_child(_camera_rig())
			var marker := Node2D.new()
			marker.name = "PlayerMarker"
			marker.set_script(PLAYER_MARKER)
			car.add_child(marker)
		else:
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

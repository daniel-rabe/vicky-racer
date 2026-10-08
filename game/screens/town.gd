class_name TownScreen
extends Node2D
## Free Drive (docs/DESIGN.md §19): no race, no laps, no timer — the player drives their own
## car round a little town. Shops, a fire station, a school and a park line the streets;
## buses, vans and cars drive about keeping to their lanes; dogs and cats walk the
## pavements and duck families cross at the zebras; balloons and birds pass overhead.
## Coins lie about the streets to pick up (banked straight away), and pulling up at a shop
## door shows its sign. Visiting every kind of place once pays a bonus. Driving onto the car
## wash's pad washes the car: foam and soap bubbles, then it sparkles for a while.
##
## The town is an island (§21). At the harbour, driving slowly onto the land pad swaps the
## car for the boat equipped in the Boat Dock, waiting at the end of the pier; sailing back
## into the mooring swaps back. At sea there are coins, a lighthouse, ramp islets, a slalom,
## a wreck, dolphins, gulls and sailboats.
##
## More to do (§23): a football to kick into the goals, beach balls, cones to knock over,
## the fountain splashing the car, jump ramps on the grass, treats and deliveries from the
## shops (TownErrands), the pet shop's lost puppy, the paint shop's pad, the fire engine at
## the fire station (FireDuty: put out the bonfires) and the school bus (BusRoute: take
## animals from stop to stop), and now and then a shower of rain (TownWeather). The fire
## engine and the bus are swapped to on their pads just as the boat is at the harbour.
##
## Escape / Start pauses (RESUME / SETTINGS / GARAGE; the Boat Dock while sailing).
##
## Dev flags, after `--`:
##   --overview    frame the whole town in one view
##   --autodrive   the player's car drives itself like traffic (screenshots, soak tests)
##   --traffic-report  print, every 10 s, how much of the traffic is moving (jams, deadlocks)
##   --start=x,y   start the player there instead (screenshots of one corner of town)
##   --start=duck  start the player by the first duck family's crossing
##   --start=wash  start the player on the car wash's pad (it is washed at once)
##   --start=harbour  start the player on the quay, next to the land pad
##   --start=sea   start the player sailing, in the boat, at the mooring
##   --start=pitch / fountain / paint / ramp  start by the football pitch, the fountain, the
##                 paint shop's pad, or at the foot of the first ramp's run-up
##   --start=fire / bus  start in the fire engine / the school bus, on its pad
##   --start=stop  start in the school bus, at the first bus stop
##   --errand=pizza / puppy  start a delivery from the pizza place, or the lost puppy
##   --rain        start a shower straight away

const CAR_SCENE := preload("res://actors/car/car.tscn")
const BOAT_SCENE := preload("res://actors/boat/boat.tscn")
const BOAT_DIR := "res://game/configs/boats/"
const DEFAULT_BOAT := &"speedboat"
const CAMERA_SCRIPT := preload("res://actors/car/chase_camera.gd")
const PLAYER_INPUT := preload("res://actors/car/player_input.gd")
const PLAYER_MARKER := preload("res://actors/car/player_marker.gd")
const MUSIC := preload("res://game/configs/music/race_town.tres")
const SETUP_DIR := "res://game/configs/setups/"
## Big town vehicles: picture, and how many drive about.
const VEHICLES := {
	"res://art/town/vehicles/bus.png": 2,
	"res://art/town/vehicles/fire_engine.png": 1,
	"res://art/town/vehicles/delivery_van.png": 2,
	"res://art/town/vehicles/garbage_truck.png": 1,
}
const CARS := 18
const DOGS_AND_CATS := 8
const DUCK_CROSSINGS := 4
## Their voices, if built (tools/comfy/sfx_manifest.json).
const VOICES := {"dog": "res://art/sfx/woof.wav", "cat": "res://art/sfx/meow.wav", "duck": "res://art/sfx/quack.wav"}
const AMBIENCE := "res://art/sfx/town_ambience.wav"
## Under the town's ambience, louder while sailing (the boat races' waves).
const WAVES := "res://art/sfx/wave_ambience.wav"
const WAVES_DB := Vector2(-34.0, -12.0)  # driving, sailing
const SWAP_SOUND := "res://art/sfx/harbour_swap.wav"
const SEA_VOICES := {"dolphin": "res://art/sfx/dolphin.wav", "seagull": "res://art/sfx/seagull.wav"}
## A pad swaps only a vehicle going slower than this, so racing across it does nothing.
const SWAP_MAX_SPEED := 300.0
const FIRE_ENGINE_ART := "res://art/town/vehicles/fire_engine.png"
const BUS_ART := "res://art/town/vehicles/bus.png"
const SIREN := "res://art/sfx/horn_police.wav"
const SPLASH := "res://art/sfx/splash.wav"
const WASH_SOUND := "res://art/sfx/car_wash.wav"
const CHEER := "res://art/sfx/cheer.wav"
const CHIME := "res://art/sfx/sparkle.wav"
const BALL := preload("res://art/props/beach/beach_ball.png")
const CONE := preload("res://art/props/town/traffic_cone.png")
## The fire engine and the bus are a little slower than a car.
const BIG_VEHICLE_SPEED := 0.8
## Driving this near the fountain splashes the car, at most once every FOUNTAIN_REST s.
const FOUNTAIN_REACH := 330.0
const FOUNTAIN_REST := 4.0
const GOAL_PAY := 5
## Cones: a little stack beyond each ramp's landing, and one on the quay.
const QUAY_CONES := Vector2(5080.0, 8470.0)
const CONE_GAP := 64.0
## Coins in the air beyond each ramp.
const RAMP_COINS := 5
const COINS := 36
const COIN_VALUE := 2
const COIN_GAP := 300.0
const COIN_RESPAWN := 40.0
## Every kind of place visited in one drive pays this.
const ALL_PLACES_BONUS := 50
## Where the player starts: on this road, this far along, facing along it.
const START_ROAD := [Vector2i(1, 1), Vector2i(2, 1)]  # by the candy shop and the ice cream parlour
const START_AT := 0.35
## Traffic keeps this far from the player's start.
const START_CLEAR := 900.0

var town: Town
## The vehicle the player is driving now: the car, the boat, the fire engine or the bus.
var player: Car
## The player's car and boat. The one not being driven waits at the harbour; the boat is
## made at the first swap. The fire engine and the bus are made the first time too; whichever
## of them and the car is not being driven is put away out of sight (on its pad).
var car: Car
var boat: Boat
var fire_engine: Car
var bus: Car
## &"car", &"boat", &"fire_engine" or &"bus".
var riding := &"car"
var sailing: bool:
	get:
		return riding == &"boat"
## The things to do (§23).
var errands: TownErrands
var fire_duty: FireDuty
var bus_route: BusRoute
var weather: TownWeather
var ball: Kickable
var kickables: Array[Kickable] = []
var traffic: Array[Car] = []
var visited: Dictionary = {}  # place id -> true, this drive
var _setup: DriftSetup
var _paint: StringName = Paint.ORIGINAL
var _boat_setup: DriftSetup
var _boat_paint: StringName = Paint.ORIGINAL
## A pad swaps once the vehicle that came off it has left it again.
var _pad_armed := true
var _swapping := false
var _sea_life: SeaLife
var _waves: AudioStreamPlayer
var _bell: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
var _fountain_rest := 0.0
var _goal_rest := 0.0
var _voice: AudioStreamPlayer

@onready var _world: Node2D = $World
@onready var _cars: Node2D = $World/Cars
@onready var _walkers: Node2D = $World/Walkers
@onready var _coins: Node2D = $World/Coins
@onready var _sky: Node2D = $World/Sky
@onready var hud: TownHUD = $TownHUD


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_state_changed)
	EventSystem.CAR_washed.connect(func(car: Node) -> void:
		if car == player:
			hud.bubbles())


func _on_state_changed(state: Dictionary) -> void:
	# Free Drive is driven in the equipped car, whichever kind the garage is showing.
	var equipped: StringName = state.get("equipped_car", state["equipped"])
	for setup: DriftSetup in state.get("car_setups", state["setups"]):
		if setup.id == equipped:
			_setup = setup
	_paint = state.get("paint", {}).get(equipped, Paint.ORIGINAL)
	# And the equipped boat, for the harbour.
	var boat_id: StringName = state.get("equipped_boat", DEFAULT_BOAT)
	if _boat_setup == null or _boat_setup.id != boat_id:
		_boat_setup = load(BOAT_DIR + String(boat_id) + ".tres")
	_boat_paint = state.get("paint", {}).get(boat_id, Paint.ORIGINAL)
	if hud and is_node_ready():
		hud.show_coins(state["coins"])


func _ready() -> void:
	_rng.seed = 7
	EventSystem.PRO_state_requested.emit()
	town = Town.new()
	town.name = "Town"
	_world.add_child(town)
	_world.move_child(town, 0)
	EventSystem.UI_music_requested.emit(MUSIC)
	var args := OS.get_cmdline_user_args()
	_spawn_player("--autodrive" in args)
	_spawn_traffic()
	_spawn_walkers()
	_spawn_coins()
	_spawn_kickables()
	_add_sky()
	_add_sea_life()
	_add_ambience()
	_add_jobs()
	town.place_reached.connect(_on_place_reached)
	town.pad_reached.connect(_on_pad_reached)
	EventSystem.CAR_surface_changed.connect(_on_surface_changed)
	hud.setup(town, player, traffic, TownLayout.PLACE_NAMES.size())
	EventSystem.PRO_state_requested.emit()  # the HUD's coin count
	for arg in args:
		if arg.begins_with("--start="):
			_dev_start(arg.get_slice("=", 1))
		elif arg.begins_with("--errand="):
			if arg.ends_with("puppy"):
				errands.start_puppy()
			else:
				errands.start_delivery("pizza_place")
	if "--rain" in args:
		weather.rain_now()
	if "--overview" in args:
		_show_overview()
	if "--traffic-report" in args:
		_report_traffic()


func _report_traffic() -> void:
	var still := {}  # car -> seconds standing
	var timer := Timer.new()
	timer.wait_time = 1.0
	timer.autostart = true
	add_child(timer)
	var ticks := [0]
	timer.timeout.connect(func() -> void:
		ticks[0] += 1
		for car in traffic:
			still[car] = still.get(car, 0.0) + 1.0 if car.velocity.length() < 15.0 else 0.0
		if ticks[0] % 10 == 0:
			var speeds := traffic.map(func(c: Car) -> float: return c.velocity.length())
			var longest: float = still.values().max()
			print("t=%ds moving %d/%d  mean speed %.0f  longest standing %.0fs  player at %s" % [ticks[0],
				speeds.filter(func(v: float) -> bool: return v > 15.0).size(), traffic.size(),
				speeds.reduce(func(a: float, b: float) -> float: return a + b, 0.0) / traffic.size(), longest,
				player.global_position.round()]))


func _spawn_player(autodrive: bool) -> void:
	car = CAR_SCENE.instantiate()
	car.name = "Player"
	if _setup:
		car.setup = _setup
		car.body_texture = Paint.body(_setup, _paint)
	car.driver_id = DriverLook.VICKY
	_cars.add_child(car)
	var a: Vector2i = START_ROAD[0]
	var b: Vector2i = START_ROAD[1]
	var lane := town.lane_points(a, b)
	car.global_position = lane[int(START_AT * (lane.size() - 1))]
	car.rotation = town.heading(a, b).angle()
	car.reset_physics_interpolation()
	if autodrive:
		var driver := TrafficDriver.new()
		driver.name = "TrafficDriver"
		driver.town = town
		driver.cruise_speed = 520.0
		car.add_child(driver)
		driver.place_on(a, b, START_AT)
	_drive(car, autodrive)


## Hand the player `vehicle`: their controls (or, autodriving, a stand-in with PlayerInput's
## name, which the shops and coins look for), the chase camera and the marker over it.
func _drive(vehicle: Car, autodrive := false) -> void:
	player = vehicle
	var input := Node.new()
	input.name = "PlayerInput"
	if not autodrive:
		input.set_script(PLAYER_INPUT)
	vehicle.add_child(input)
	var rig := Node2D.new()
	rig.name = "ChaseCamera"
	rig.set_script(CAMERA_SCRIPT)
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	rig.add_child(camera)
	vehicle.add_child(rig)
	var marker := Node2D.new()
	marker.name = "PlayerMarker"
	marker.set_script(PLAYER_MARKER)
	vehicle.add_child(marker)
	rig.set_world_bounds(town.map_rect())
	rig.snap_to_car()
	vehicle.frozen = false
	vehicle.get_node(^"Audio").process_mode = Node.PROCESS_MODE_INHERIT


## Leave `vehicle` waiting at the harbour: still, quiet, nobody's.
func _park(vehicle: Car) -> void:
	for part in [^"PlayerInput", ^"ChaseCamera", ^"PlayerMarker"]:
		var node := vehicle.get_node_or_null(part)
		if node:
			vehicle.remove_child(node)
			node.queue_free()
	vehicle.frozen = true
	vehicle.velocity = Vector2.ZERO
	vehicle.get_node(^"Audio").process_mode = Node.PROCESS_MODE_DISABLED


## The equipped boat, in its paint, made the first time it is needed.
func _the_boat() -> Boat:
	if boat == null:
		boat = BOAT_SCENE.instantiate()
		boat.name = "PlayerBoat"
		if _boat_setup:
			boat.setup = _boat_setup
			boat.body_texture = Paint.body(_boat_setup, _boat_paint)
		boat.driver_id = DriverLook.VICKY
		_cars.add_child(boat)
	return boat


# --- swapping vehicles: the harbour (§21.3), the fire station and the school (§23) -------

func _physics_process(delta: float) -> void:
	if player == null:
		return
	_check_fountain(delta)
	_check_goal(delta)
	hud.set_marks(errands.marks() + fire_duty.marks())
	if _swapping or player.has_node(^"TrafficDriver"):
		return
	var near_a_pad := false
	for pad: Array in _pads():
		var rect: Rect2 = pad[0]
		if pad[1] != riding or rect == Rect2():
			continue
		if rect.grow(60.0).has_point(player.global_position):
			near_a_pad = true
		if rect.has_point(player.global_position) and _pad_armed and player.velocity.length() < SWAP_MAX_SPEED:
			_swap(pad[2])
			return
	if not near_a_pad:
		_pad_armed = true


## Every pad that swaps the player: [where, driving what, into what].
func _pads() -> Array:
	return [[Island.LAND_PAD, &"car", &"boat"], [Island.MOORING, &"boat", &"car"],
		[town.fire_pad, &"car", &"fire_engine"], [town.fire_pad, &"fire_engine", &"car"],
		[town.bus_pad, &"car", &"bus"], [town.bus_pad, &"bus", &"car"]]


## The bell, a quick fade to white, and on the far side the other vehicle: the boat at the
## mooring pointing out to sea, or the car on the land pad facing up the harbour road; the
## fire engine or the bus on its pad facing the road, or the car back there.
func _swap(to := &"") -> void:
	_swapping = true
	_pad_armed = false
	_ring_bell()
	await hud.fade(true)
	_swap_now(to)
	await hud.fade(false)
	_swapping = false


## Swap to `to` (&"": between the car and the boat, the other one).
func _swap_now(to := &"") -> void:
	if to == &"":
		to = &"car" if sailing else &"boat"
	var from := player
	var from_kind := riding
	var next := _vehicle(to)
	_park(from)
	if &"boat" in [from_kind, to]:
		# The boat is tied up at the mooring, pointing out to sea, whether it is leaving or
		# arriving; the car comes back on the land pad, facing up the harbour road.
		_place(boat, Island.MOORING.get_center(), PI / 2.0)
		if to == &"car":
			_place(car, Island.LAND_PAD.get_center(), -PI / 2.0)
	else:
		# The fire engine and the bus: whichever is left behind is put away, and the other
		# comes out on the pad, facing the road.
		var pad := town.fire_pad if &"fire_engine" in [from_kind, to] else town.bus_pad
		_stow(from)
		_unstow(next)
		_place(next, pad.get_center(), PI / 2.0)
	if from_kind == &"fire_engine":
		fire_duty.stop()
	elif from_kind == &"bus":
		bus_route.stop()
	_drive(next)
	riding = to
	if to == &"fire_engine":
		fire_duty.start(next)
	elif to == &"bus":
		bus_route.start(next)
	_pad_armed = false
	_sea_life.player = player
	hud.set_vehicle(player, riding)
	EventSystem.PRO_vehicle_kind_requested.emit(&"boat" if sailing else &"car")  # the pause menu's GARAGE
	if _waves:
		_waves.create_tween().tween_property(_waves, "volume_db", WAVES_DB.y if sailing else WAVES_DB.x, 1.0)


func _vehicle(kind: StringName) -> Car:
	match kind:
		&"boat":
			return _the_boat()
		&"fire_engine":
			if fire_engine == null:
				fire_engine = _town_vehicle("PlayerFireEngine", load(FIRE_ENGINE_ART), load(SIREN))
			return fire_engine
		&"bus":
			if bus == null:
				bus = _town_vehicle("PlayerBus", load(BUS_ART), null)
			return bus
	return car


## A big town vehicle for the player: Vicky behind its windscreen, a little slower than a car,
## no drifting (the drift button is the fire engine's hose).
func _town_vehicle(vehicle_name: String, picture: Texture2D, horn: AudioStream) -> Car:
	var vehicle: Car = CAR_SCENE.instantiate()
	vehicle.name = vehicle_name
	var setup: DriftSetup = load(SETUP_DIR + "starter.tres").duplicate()
	if horn:
		setup.horn = horn
	vehicle.setup = setup
	vehicle.body_texture = picture
	vehicle.driver_id = DriverLook.VICKY
	_fit_body(vehicle, picture)
	_cars.add_child(vehicle)
	vehicle.config.max_speed *= BIG_VEHICLE_SPEED
	vehicle.config.handbrake_lateral_grip = vehicle.config.lateral_grip
	_stow(vehicle)
	return vehicle


## Out of sight and out of the way: not drawn, touching nothing, not a car to anyone.
func _stow(vehicle: Car) -> void:
	vehicle.visible = false
	vehicle.collision_layer = 0
	vehicle.collision_mask = 0
	vehicle.remove_from_group(&"cars")


func _unstow(vehicle: Car) -> void:
	vehicle.visible = true
	vehicle.add_to_group(&"cars")
	vehicle.set_level(0)


func _place(vehicle: Car, at: Vector2, angle: float) -> void:
	vehicle.global_position = at
	vehicle.rotation = angle
	vehicle.velocity = Vector2.ZERO
	vehicle.reset_physics_interpolation()


func _ring_bell() -> void:
	if _bell == null:
		_bell = AudioStreamPlayer.new()
		_bell.name = "Bell"
		_bell.stream = _sound(SWAP_SOUND)
		_bell.bus = &"SFX"
		add_child(_bell)
	if _bell.stream:
		_bell.play()


## Town vehicles and cars in every paint, spread round the roads away from the player.
func _spawn_traffic() -> void:
	var bodies: Array[Array] = []  # [picture, setup or null]
	for path: String in VEHICLES:
		if ResourceLoader.exists(path):
			for i in VEHICLES[path]:
				bodies.append([load(path), null])
	var setups: Array[DriftSetup] = []
	for id in GarageManager.SETUP_ORDER:
		setups.append(load(SETUP_DIR + String(id) + ".tres"))
	for i in CARS:
		# Every car once before any twice, so the police car and the ice-cream van are about.
		var setup := setups[i % setups.size()]
		bodies.append([Paint.body(setup, Paint.COLOURS[_rng.randi() % Paint.COLOURS.size()]), setup])
	var taken: Array[Vector2] = [player.global_position]
	for entry in bodies:
		var body: Texture2D = entry[0]
		var car: Car = CAR_SCENE.instantiate()
		if entry[1]:
			car.setup = entry[1]  # its own horn: the police car's siren, the ice-cream van's tune
		car.body_texture = body
		# Grown-ups drive the big vehicles; the other children are out in the little cars.
		car.driver_id = DriverLook.for_traffic(body) if entry[1] == null 			else DriverLook.KIDS[1 + _rng.randi() % (DriverLook.KIDS.size() - 1)]
		_fit_body(car, body)
		var driver := TrafficDriver.new()
		driver.name = "TrafficDriver"
		driver.town = town
		driver.cruise_speed = _rng.randf_range(300.0, 430.0) * (0.85 if body.get_width() > 140 else 1.0)
		driver.spacing = _rng.randf_range(0.0, 60.0)
		car.add_child(driver)
		_cars.add_child(car)
		car.config.steer_speed_ref = 150.0  # town driving: tight corners at low speed
		car.config.lateral_grip = 14.0
		car.get_node(^"Audio").engine_offset_db = -12.0
		for attempt in 40:
			var road: Array = town.roads[_rng.randi() % town.roads.size()]
			var forward := _rng.randf() < 0.5
			var a: Vector2i = road[0] if forward else road[1]
			var b: Vector2i = road[1] if forward else road[0]
			driver.place_on(a, b, _rng.randf_range(0.1, 0.8))
			var here := car.global_position
			if here.distance_to(player.global_position) > START_CLEAR \
					and taken.all(func(p: Vector2) -> bool: return p.distance_to(here) > 320.0):
				break
		taken.append(car.global_position)
		traffic.append(car)


## A bigger vehicle gets a bigger body: its collision box follows its picture.
func _fit_body(car: Car, body: Texture2D) -> void:
	if body.get_width() <= 140:
		return
	var shape := RectangleShape2D.new()
	shape.size = Vector2(body.get_width() - 16.0, body.get_height() - 12.0)
	car.get_node(^"Collision").shape = shape


func _spawn_walkers() -> void:
	var pets: Array[Texture2D] = []
	var voices: Array[AudioStream] = []
	for kind in ["dog", "cat"]:
		var path := "res://art/town/animals/%s.png" % kind
		if ResourceLoader.exists(path):
			pets.append(load(path))
			voices.append(_sound(VOICES[kind]))
	var mid := TownLayout.SIDEWALK * 0.5
	for i in (DOGS_AND_CATS if not pets.is_empty() else 0):
		var lawn := town.lawns[_rng.randi() % town.lawns.size()].grow(mid)
		var route := PackedVector2Array([lawn.position, Vector2(lawn.end.x, lawn.position.y), lawn.end,
			Vector2(lawn.position.x, lawn.end.y)])
		if _rng.randf() < 0.5:
			route.reverse()
		var start := _rng.randi() % 4
		route = route.slice(start) + route.slice(0, start)
		var walker := Walker.new()
		walker.picture = pets[i % pets.size()]
		walker.voice = voices[i % voices.size()]
		walker.route = route
		walker.speed = _rng.randf_range(55.0, 85.0)
		_walkers.add_child(walker)
	var duck_path := "res://art/town/animals/duck.png"
	if not ResourceLoader.exists(duck_path):
		return
	var duck: Texture2D = load(duck_path)
	var crossings := _zebra_crossings()
	for i in mini(DUCK_CROSSINGS, crossings.size()):
		var crossing: Array = crossings[(i * 5 + 3) % crossings.size()]
		var walker := Walker.new()
		walker.picture = duck
		walker.route = PackedVector2Array(crossing)
		walker.loop = false
		walker.speed = 70.0
		walker.pause = 16.0
		walker.followers = 3
		walker.voice = _sound(VOICES["duck"])
		_walkers.add_child(walker)


## Both ends of every zebra crossing, on the grass beyond the pavement either side: far
## enough that a resting duck's ducklings, in a line behind her, are off the road too.
func _zebra_crossings() -> Array:
	var out := []
	var across := TownLayout.ROAD_HALF + TownLayout.SIDEWALK + Walker.FOLLOW_GAP * 3.0
	for road in town.roads:
		var a: Vector2 = town.junctions[road[0]]
		var b: Vector2 = town.junctions[road[1]]
		var d := (b - a).normalized()
		for end in [[road[0], a, d], [road[1], b, -d]]:
			var cell: Vector2i = end[0]
			if cell.x > 0 and cell.y > 0 and cell.x < TownLayout.COLS and cell.y < TownLayout.ROWS:
				var centre: Vector2 = end[1] + end[2] * (TownLayout.ROAD_HALF + 62.0)
				var side := Town.right_of(end[2]) * across
				out.append([centre - side, centre + side])
	return out


func _spawn_coins() -> void:
	for i in COINS:
		var coin := TownCoin.new()
		coin.position = _coin_spot()
		coin.collected.connect(_on_coin_collected)
		_coins.add_child(coin)
	# At sea the coins lie in trails and come back where they were; those over the ramp
	# islets are picked up in the air.
	for at in Island.sea_coins():
		var coin := TownCoin.new()
		coin.position = at
		coin.set_meta(&"fixed", true)
		coin.collected.connect(_on_coin_collected)
		_coins.add_child(coin)
		coin.collision_mask |= Car.LAYER_AIRBORNE
	# Over each ramp's landing: a line of coins to catch in the air (§23).
	for ramp: Dictionary in town.ramps:
		for k in RAMP_COINS:
			var coin := TownCoin.new()
			coin.position = ramp["at"] + ramp["throw"] * (230.0 + 110.0 * k)
			coin.set_meta(&"fixed", true)
			coin.collected.connect(_on_coin_collected)
			_coins.add_child(coin)


## Somewhere on a road, in a lane or between them, clear of the junctions and of the other
## coins (two together would pay twice for one pass).
func _coin_spot() -> Vector2:
	var spot := Vector2.ZERO
	for attempt in 30:
		var road: Array = town.roads[_rng.randi() % town.roads.size()]
		var a: Vector2 = town.junctions[road[0]]
		var b: Vector2 = town.junctions[road[1]]
		var d := (b - a).normalized()
		var along := _rng.randf_range(TownLayout.ROAD_HALF + 120.0, a.distance_to(b) - TownLayout.ROAD_HALF - 120.0)
		spot = a + d * along + Town.right_of(d) * _rng.randf_range(-110.0, 110.0)
		if _coins.get_children().all(func(c: Node2D) -> bool: return not c.visible or c.position.distance_to(spot) > COIN_GAP):
			break
	return spot


func _on_coin_collected(coin: TownCoin) -> void:
	coin.pop()
	pay(COIN_VALUE, coin.global_position)
	get_tree().create_timer(COIN_RESPAWN, false).timeout.connect(func() -> void:
		if is_instance_valid(coin):
			coin.reappear(coin.position if coin.has_meta(&"fixed") else _coin_spot()))


## Coins earned at `at`: banked at once, and a +N floats up from there.
func pay(amount: int, at: Vector2) -> void:
	EventSystem.PRO_coins_found.emit(amount)
	hud.coin_popped(at, amount)


func _on_place_reached(place_id: String, display_name: String, picture: Texture2D) -> void:
	if player == car:
		errands.on_place(place_id)
	var first := not visited.has(display_name)
	visited[display_name] = true
	hud.show_place(display_name, picture, visited.size(), first)
	if first and visited.size() == TownLayout.PLACE_NAMES.size():
		EventSystem.PRO_coins_found.emit(ALL_PLACES_BONUS)
		hud.show_banner("YOU VISITED EVERY PLACE!  +%d" % ALL_PLACES_BONUS)



# --- things to do (§23) -------------------------------------------------------------------

## The football on the pitch, a beach ball by every parasol, and stacks of cones beyond the
## ramps' landings and on the quay.
func _spawn_kickables() -> void:
	ball = _kickable(Kickable.Kind.BALL, BALL, 84.0, town.pitch.get_center())
	ball.roam = town.pitch.size.length() * 0.5 + 300.0
	for spot in town.beach_balls:
		_kickable(Kickable.Kind.BALL, BALL, 70.0, spot).roam = 700.0
	var stacks: Array[Array] = [[QUAY_CONES, Vector2.DOWN]]
	for ramp: Dictionary in town.ramps:
		stacks.append([ramp["at"] + ramp["throw"] * (TownLayout.RUNWAY_AFTER + 220.0), ramp["throw"]])
	for stack in stacks:
		# A little triangle, its point towards whoever comes: rows of 1, 2 and 3.
		var facing: Vector2 = stack[1]
		for row in 3:
			for k in row + 1:
				var across := Town.right_of(facing) * (k - row / 2.0) * CONE_GAP
				_kickable(Kickable.Kind.CONE, CONE, 52.0, stack[0] + facing * row * CONE_GAP * 0.85 + across)


func _kickable(kind: Kickable.Kind, picture: Texture2D, size: float, at: Vector2) -> Kickable:
	var thing := Kickable.new()
	thing.kind = kind
	thing.picture = picture
	thing.size = size
	thing.home = at
	_walkers.add_child(thing)
	kickables.append(thing)
	return thing


## Into a goal: confetti, a cheer, coins, and the ball back on the centre spot.
func _check_goal(delta: float) -> void:
	_goal_rest = maxf(_goal_rest - delta, 0.0)
	if _goal_rest > 0.0 or ball == null:
		return
	for goal in town.goals:
		if goal.has_point(ball.global_position):
			_goal_rest = 2.5
			TownFx.confetti(_world, goal.get_center())
			pay(GOAL_PAY, goal.get_center())
			hud.show_banner("GOAL!")
			_play(CHEER if ResourceLoader.exists(CHEER) else CHIME, -2.0)
			get_tree().create_timer(1.2, false).timeout.connect(ball.stand_up)
			return


## Splashing past the fountain: it shoots up high, and drops fly all over the car.
func _check_fountain(delta: float) -> void:
	_fountain_rest = maxf(_fountain_rest - delta, 0.0)
	if _fountain_rest > 0.0 or town.fountain_spray == null:
		return
	if player.global_position.distance_to(town.fountain_at) > FOUNTAIN_REACH or player.velocity.length() < 60.0:
		return
	_fountain_rest = FOUNTAIN_REST
	var spray := town.fountain_spray
	var tween := spray.create_tween()
	tween.tween_property(spray, "initial_velocity_max", 300.0, 0.2)
	tween.parallel().tween_property(spray, "scale_amount_max", 14.0, 0.2)
	tween.tween_interval(1.4)
	tween.tween_property(spray, "initial_velocity_max", 90.0, 1.0)
	tween.parallel().tween_property(spray, "scale_amount_max", 8.0, 1.0)
	TownFx.drops(_world, player.global_position, 36)
	var body: CanvasItem = player.get_node(^"Body")
	var shine := body.create_tween()
	shine.tween_property(body, "self_modulate", Color(0.75, 0.9, 1.3), 0.12)
	shine.tween_property(body, "self_modulate", Color.WHITE, 0.6)
	_play(SPLASH, -4.0)


## The paint shop's pad: the car comes out in its next colour, in a cloud of it.
func _on_pad_reached(kind: StringName, vehicle: Car) -> void:
	if kind != &"paint" or vehicle != car or _setup == null:
		return
	EventSystem.PRO_paint_requested.emit(_setup.id)
	EventSystem.PRO_state_requested.emit()  # _on_state_changed takes the new paint
	car.body_texture = Paint.body(_setup, _paint)
	TownFx.paint_cloud(_world, car.global_position, Paint.SWATCHES.get(_paint, Color(1, 1, 1)))
	_play(WASH_SOUND, -4.0)


## Into a puddle: a splash.
func _on_surface_changed(changed: Node, surface: StringName) -> void:
	if changed == player and surface == &"puddle" and player.velocity.length() > 150.0:
		TownFx.drops(_world, player.global_position, 18)
		_play(SPLASH, -10.0)


func _add_jobs() -> void:
	errands = TownErrands.new()
	errands.name = "Errands"
	errands.screen = self
	_world.add_child(errands)
	fire_duty = FireDuty.new()
	fire_duty.name = "FireDuty"
	fire_duty.screen = self
	_world.add_child(fire_duty)
	bus_route = BusRoute.new()
	bus_route.name = "BusRoute"
	bus_route.screen = self
	_world.add_child(bus_route)
	weather = TownWeather.new()
	weather.name = "Weather"
	weather.town = town
	add_child(weather)
	move_child(weather, hud.get_index())  # its rain falls under the HUD
	_voice = AudioStreamPlayer.new()
	_voice.name = "Voice"
	_voice.bus = &"SFX"
	add_child(_voice)


func _play(path: String, volume_db: float) -> void:
	if not SoundManager.audible() or not ResourceLoader.exists(path):
		return
	_voice.stream = load(path)
	_voice.volume_db = volume_db
	_voice.play()


## Things in the sky: hot-air balloons drifting over, and now and then a flock of birds.
func _add_sky() -> void:
	var sky := TownSky.new()
	sky.name = "TownSky"
	sky.world = town.world_rect()
	_sky.add_child(sky)


## The sailboats, the dolphins, the gulls and the lighthouse's beam.
func _add_sea_life() -> void:
	_sea_life = SeaLife.new()
	_sea_life.name = "SeaLife"
	_sea_life.player = player
	_sea_life.dolphin_voice = _sound(SEA_VOICES["dolphin"])
	_sea_life.gull_voice = _sound(SEA_VOICES["seagull"])
	_world.add_child(_sea_life)


func _sound(path: String) -> AudioStream:
	return load(path) if ResourceLoader.exists(path) else null


## Birdsong and a breeze under everything, very quietly.
func _add_ambience() -> void:
	var stream := _sound(AMBIENCE)
	if stream == null or not SoundManager.audible():
		return
	var player := AudioStreamPlayer.new()
	player.name = "Ambience"
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = -14.0
	add_child(player)
	player.finished.connect(player.play)
	player.play()
	var waves := _sound(WAVES)
	if waves:
		_waves = AudioStreamPlayer.new()
		_waves.name = "Waves"
		_waves.stream = waves
		_waves.bus = &"SFX"
		_waves.volume_db = WAVES_DB.y if sailing else WAVES_DB.x
		add_child(_waves)
		_waves.finished.connect(_waves.play)
		_waves.play()


func _dev_start(where: String) -> void:
	var at := Vector2.ZERO
	if where == "duck":
		var duck: Walker = _walkers.get_children().filter(func(w: Walker) -> bool: return w.followers > 0)[0]
		at = duck.route[0].lerp(duck.route[1], 0.5) + Vector2(-260, 120)
	elif where == "wash":
		at = town.wash_pad.get_center() + Vector2(0, 40)
		player.rotation = -PI / 2.0  # facing the car wash
	elif where == "harbour":
		at = Vector2(Island.LAND_PAD.end.x + 260.0, Island.LAND_PAD.get_center().y)
		player.rotation = PI  # facing the land pad
	elif where == "sea":
		_swap_now(&"boat")
		return
	elif where in ["fire", "bus", "stop"]:
		_swap_now(&"fire_engine" if where == "fire" else &"bus")
		if where == "stop":
			var stop: Dictionary = town.bus_stops[0]
			player.global_position = stop["stop"] - stop["along"] * 500.0
			player.rotation = stop["along"].angle()
			player.reset_physics_interpolation()
		player.get_node(^"ChaseCamera").snap_to_car()
		return
	elif where == "pitch":
		at = town.pitch.get_center() + Vector2(-260, 60)
	elif where == "fountain":
		at = town.fountain_at + Vector2(-420, 0)
		player.rotation = 0.0
	elif where == "paint":
		at = town.paint_pad.get_center() + Vector2(0, 260)
		player.rotation = -PI / 2.0
	elif where == "ramp":
		var ramp: Dictionary = town.ramps[0]
		at = ramp["at"] - ramp["throw"] * (TownLayout.RUNWAY_BEFORE - 80.0)
		player.rotation = ramp["throw"].angle()
	else:
		at = Vector2(float(where.get_slice(",", 0)), float(where.get_slice(",", 1)))
	player.global_position = at
	player.reset_physics_interpolation()
	player.get_node(^"ChaseCamera").snap_to_car()


func _show_overview() -> void:
	var rect := town.map_rect()
	var view := Camera2D.new()
	var fit := minf(1920.0 / rect.size.x, 1080.0 / rect.size.y)
	view.zoom = Vector2(fit, fit)
	view.position = rect.get_center()
	add_child(view)
	view.make_current()
	hud.visible = false

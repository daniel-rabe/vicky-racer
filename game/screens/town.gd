extends Node2D
## Free Drive (docs/DESIGN.md §19): no race, no laps, no timer — the player drives their own
## car round a little town. Shops, a fire station, a school and a park line the streets;
## buses, vans and cars drive about keeping to their lanes; dogs and cats walk the
## pavements and duck families cross at the zebras; balloons and birds pass overhead.
## Coins lie about the streets to pick up (banked straight away), and pulling up at a shop
## door shows its sign. Visiting every kind of place once pays a bonus. Driving onto the car
## wash's pad washes the car: foam and soap bubbles, then it sparkles for a while.
##
## Escape / Start pauses (RESUME / SETTINGS / GARAGE).
##
## Dev flags, after `--`:
##   --overview    frame the whole town in one view
##   --autodrive   the player's car drives itself like traffic (screenshots, soak tests)
##   --traffic-report  print, every 10 s, how much of the traffic is moving (jams, deadlocks)
##   --start=x,y   start the player there instead (screenshots of one corner of town)
##   --start=duck  start the player by the first duck family's crossing
##   --start=wash  start the player on the car wash's pad (it is washed at once)

const CAR_SCENE := preload("res://actors/car/car.tscn")
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
var player: Car
var traffic: Array[Car] = []
var visited: Dictionary = {}  # place id -> true, this drive
var _setup: DriftSetup
var _paint: StringName = Paint.ORIGINAL
var _rng := RandomNumberGenerator.new()

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
	_add_sky()
	_add_ambience()
	town.place_reached.connect(_on_place_reached)
	hud.setup(town, player, traffic, TownLayout.PLACE_NAMES.size())
	EventSystem.PRO_state_requested.emit()  # the HUD's coin count
	for arg in args:
		if arg.begins_with("--start="):
			_dev_start(arg.get_slice("=", 1))
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
	player = CAR_SCENE.instantiate()
	player.name = "Player"
	if _setup:
		player.setup = _setup
		player.body_texture = Paint.body(_setup, _paint)
	if autodrive:
		var driver := TrafficDriver.new()
		driver.name = "TrafficDriver"
		driver.town = town
		driver.cruise_speed = 520.0
		player.add_child(driver)
	else:
		var input := Node.new()
		input.name = "PlayerInput"
		input.set_script(PLAYER_INPUT)
		player.add_child(input)
	var rig := Node2D.new()
	rig.name = "ChaseCamera"
	rig.set_script(CAMERA_SCRIPT)
	var camera := Camera2D.new()
	camera.name = "Camera"
	camera.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	rig.add_child(camera)
	player.add_child(rig)
	var marker := Node2D.new()
	marker.name = "PlayerMarker"
	marker.set_script(PLAYER_MARKER)
	player.add_child(marker)
	_cars.add_child(player)
	rig.set_world_bounds(town.world_rect())
	var a: Vector2i = START_ROAD[0]
	var b: Vector2i = START_ROAD[1]
	var lane := town.lane_points(a, b)
	player.global_position = lane[int(START_AT * (lane.size() - 1))]
	player.rotation = town.heading(a, b).angle()
	player.reset_physics_interpolation()
	rig.snap_to_car()
	if autodrive:
		player.get_node(^"TrafficDriver").place_on(a, b, START_AT)
		# Autodrive keeps PlayerInput's name for the shops and coins, without its controls.
		var stand_in := Node.new()
		stand_in.name = "PlayerInput"
		player.add_child(stand_in)


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
	EventSystem.PRO_coins_found.emit(COIN_VALUE)
	hud.coin_popped(coin.global_position)
	get_tree().create_timer(COIN_RESPAWN, false).timeout.connect(func() -> void:
		if is_instance_valid(coin):
			coin.reappear(_coin_spot()))


func _on_place_reached(_place_id: String, display_name: String, picture: Texture2D) -> void:
	var first := not visited.has(display_name)
	visited[display_name] = true
	hud.show_place(display_name, picture, visited.size(), first)
	if first and visited.size() == TownLayout.PLACE_NAMES.size():
		EventSystem.PRO_coins_found.emit(ALL_PLACES_BONUS)
		hud.show_banner("YOU VISITED EVERY PLACE!  +%d" % ALL_PLACES_BONUS)



## Things in the sky: hot-air balloons drifting over, and now and then a flock of birds.
func _add_sky() -> void:
	var sky := TownSky.new()
	sky.name = "TownSky"
	sky.world = town.world_rect()
	_sky.add_child(sky)


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


func _dev_start(where: String) -> void:
	var at := Vector2.ZERO
	if where == "duck":
		var duck: Walker = _walkers.get_children().filter(func(w: Walker) -> bool: return w.followers > 0)[0]
		at = duck.route[0].lerp(duck.route[1], 0.5) + Vector2(-260, 120)
	elif where == "wash":
		at = town.wash_pad.get_center() + Vector2(0, 40)
		player.rotation = -PI / 2.0  # facing the car wash
	else:
		at = Vector2(float(where.get_slice(",", 0)), float(where.get_slice(",", 1)))
	player.global_position = at
	player.reset_physics_interpolation()
	player.get_node(^"ChaseCamera").snap_to_car()


func _show_overview() -> void:
	var rect := town.world_rect()
	var view := Camera2D.new()
	var fit := minf(1920.0 / rect.size.x, 1080.0 / rect.size.y)
	view.zoom = Vector2(fit, fit)
	view.position = rect.get_center()
	add_child(view)
	view.make_current()
	hud.visible = false

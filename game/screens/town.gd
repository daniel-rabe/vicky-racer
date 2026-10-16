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
## The open world is the game (§28): PLAY on the title comes here, and the child drives to
## everything else. A race gate (RaceGate) for every car track stands on the grass round the
## town, and one for every boat course floats at sea, with the track's racers waiting; pulling up
## on its glowing place shows the track's card, and Y / R (or Enter) starts the race. Afterwards
## DRIVE ON comes back to the gate. The garage's and the trophy house's pads open the garage and
## the shelf, and the rocket pad the Hangar. Leaving, the place and the vehicle are saved, so PLAY
## carries on where the child left off. The pause menu's MAP shows the whole island (WorldMap):
## choosing a place there points the way to it.
##
## Out of the car (§29): stopped, E / Y lets Vicky climb out (Kid) and walk, the car left parked
## where it stood. Walking up to it (or to one of the cars parked in the driveways, free to
## borrow) and pressing E / Y again gets in. On foot, the horn is a whistle: the car comes and
## parks by the kerb nearby. Traffic stops for him and drives round him; dogs and cats he walks
## up to are petted and trot along for a while; the shops' treats and parcels go in his hands.
##
## Street races (§30): a checkered line across the road starts each of the town's own races
## (StreetRace). Pulled up on it, the route's card shows, and R / Y races the three racers round
## glowing rings in the streets while the traffic waits. Pop-up challenges (TownChallenges):
## every ramp jump is measured, and drifting in the zone on the quay earns stars.
## Pick-and-mix fun (§32): golden stars to find (GoldenStars), the jobs board in the park
## (JobsBoard), rides on the playgrounds on foot (PlaygroundRides), fireworks at night (Fireworks).
## The snowy hill (§33): a snow island over a bridge east of town (SnowIsland, SnowHill).
##
## Escape / Start pauses (RESUME / MAP / SETTINGS / GARAGE; the Boat Dock while sailing).
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
##   --start=gate  start on the first race gate's place (its card shows); gate4 the fifth
##   --start=garage / trophies / stadium / workshop / rocket  start just below that building's pad,
##                 or beside the rocket pad
##   --start=watch  start on the first car gate's stopwatch (TIME TRIAL); watch3 the fourth
##   --map         open the pause menu's map straight away
##   --start=foot  start on foot, beside the car; --start=driveway on foot by the first driveway car
##   --start=street  start on the first street race's start line (its card shows); street1, street2
##   --street-race  and start that race straight away
##   --start=drift  start by the drift zone on the quay
##   --start=board  start by the jobs board in the park; --jobs=coins,pet,star picks today's jobs
##   --start=playground  start on foot by the park's playground; --start=ride straight down a slide
##   --start=star  start by the first golden star (the end of the pier)
##   --fireworks   fireworks over the player wherever, day or night
##   --start=snow  start on the bridge, about to reach the snowy hill; --start=hill on its slope

const CAR_SCENE := preload("res://actors/car/car.tscn")
const BOAT_SCENE := preload("res://actors/boat/boat.tscn")
const BOAT_DIR := "res://game/configs/boats/"
const DEFAULT_BOAT := &"speedboat"
const CAMERA_SCRIPT := preload("res://actors/car/chase_camera.gd")
## A porch lamp's glow at night (docs/DESIGN.md §27).
const PORCH_GLOW := preload("res://actors/weather/porch_glow.tres")
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
## The world's spot is saved this often while driving (and on leaving), s.
const SAVE_EVERY := 10.0
## The jobs board stands in the park, this far from the fountain (§32).
const JOBS_BOARD_AT := Vector2(0, 420)
## Within this of a place chosen on the map, the way is found: the arrow goes.
const PIN_REACH := 450.0
const WORLD_MAP := preload("res://ui/town/world_map.gd")
const HARBOUR_ART := preload("res://art/town/buildings/harbour.png")
const ROCKET_ART := preload("res://art/ships/cardboard_rocket.png")
## On foot (§29).
const KID_INPUT := preload("res://actors/kid/kid_input.gd")
const KID_ZOOM := 1.25
## Slower than this, the car can be left.
const GET_OUT_SPEED := 60.0
## This near a parked car, he can get in.
const HOP_REACH := 150.0
## Further off than this, a whistle brings the car.
const WHISTLE_AWAY := 900.0
const WHISTLE := "res://art/sfx/comet_chime.wav"
const DOOR := "res://art/sfx/wall_bump.wav"
const BEEP := "res://art/sfx/countdown_beep.wav"
const LIFT_OFF := "res://art/sfx/comet_whoosh.wav"

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
## &"car", &"boat", &"fire_engine", &"bus" or &"foot".
var riding := &"car"
var sailing: bool:
	get:
		return riding == &"boat"
## The things to do (§23).
var errands: TownErrands
var fire_duty: FireDuty
var bus_route: BusRoute
var weather: TownWeather
## Free Drive at night (the title's moon button, docs/DESIGN.md §27).
var night: Night
var _night := false
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
## The open world (§28): the race gates, every track's entry from the garage's state (by id),
## where the child was last time, the place chosen on the map ({} = none), and whether the screen
## is on its way to another one (a race, the garage), its spot already saved.
var gates: Array[RaceGate] = []
var _world_tracks := {}
var _world_spot := {}
var _jobs_saved := {}
var _pin := {}
var _leaving := false
var _save_in := SAVE_EVERY
var _map: WorldMap
var _map_layer: CanvasLayer
## On foot (§29): Vicky himself, the parked cars he can get into (his own, left where he got
## out, and the driveway cars), the bubble over the one he can get into now, and the cars a
## child can borrow.
var kid: Kid
var hop_ins: Array[Car] = []
var _prompt: HopPrompt
var _stopped := 0.0
var _car_setups: Array = []
## The town's own races (§30).
var street_race: StreetRace
var challenges: TownChallenges
## Pick-and-mix fun (§32): golden stars, the jobs board, the playgrounds, fireworks.
var stars: GoldenStars
var jobs: JobsBoard
var rides: PlaygroundRides
var fireworks: Fireworks
## The snowy hill (§33): its snowfall and its slope.
var snow_hill: SnowHill

@onready var _world: Node2D = $World
@onready var _cars: Node2D = $World/Cars
@onready var _walkers: Node2D = $World/Walkers
@onready var _coins: Node2D = $World/Coins
@onready var _sky: Node2D = $World/Sky
@onready var hud: TownHUD = $TownHUD


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_state_changed)
	EventSystem.UI_screen_requested.connect(_on_screen_requested)
	EventSystem.CAR_washed.connect(func(car: Node) -> void:
		if car == player:
			hud.bubbles())
	EventSystem.CAR_horn.connect(func(by: Node) -> void:
		if by == kid and riding == &"foot":
			_whistle())


func _on_state_changed(state: Dictionary) -> void:
	# Free Drive is driven in the equipped car, whichever kind the garage is showing.
	var equipped: StringName = state.get("equipped_car", state["equipped"])
	for setup: DriftSetup in state.get("car_setups", state["setups"]):
		if setup.id == equipped:
			_setup = setup
	_paint = state.get("paint", {}).get(equipped, Paint.ORIGINAL)
	_car_setups = state.get("car_setups", state["setups"])
	if state.get("night", false) != _night:
		_night = state.get("night", false)
		if weather:
			_show_night()  # N switched it mid-drive
	# And the equipped boat, for the harbour.
	var boat_id: StringName = state.get("equipped_boat", DEFAULT_BOAT)
	if _boat_setup == null or _boat_setup.id != boat_id:
		_boat_setup = load(BOAT_DIR + String(boat_id) + ".tres")
	_boat_paint = state.get("paint", {}).get(boat_id, Paint.ORIGINAL)
	_world_spot = state.get("world", {})
	_jobs_saved = state.get("jobs", {})
	for entry: Dictionary in state.get("world_tracks", []):
		_world_tracks[entry["config"].track_id] = entry
	for gate in gates:
		if _world_tracks.has(gate.config.track_id):
			gate.set_unlocked(_world_tracks[gate.config.track_id]["unlocked"])
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
	EventSystem.PRO_home_requested.emit(&"town")
	EventSystem.PRO_back_to_requested.emit(&"")  # the track select's usual way back, until a door says
	_spawn_player("--autodrive" in args)
	var dev_start := Array(args).any(func(a: String) -> bool: return a.begins_with("--start="))
	if not dev_start and "--autodrive" not in args:
		_restore_car_spot()
	_spawn_traffic()
	_spawn_walkers()
	_spawn_coins()
	_spawn_kickables()
	_add_sky()
	_add_sea_life()
	_add_ambience()
	_add_jobs()
	_add_gates()
	_add_map()
	_add_driveway_cars()
	street_race = StreetRace.new()
	street_race.name = "StreetRace"
	street_race.screen = self
	_world.add_child(street_race)
	_world.move_child(street_race, _cars.get_index())  # the lines and rings under the cars
	challenges = TownChallenges.new()
	challenges.name = "Challenges"
	challenges.screen = self
	_world.add_child(challenges)
	_world.move_child(challenges, _cars.get_index())
	_add_fun(args)
	_prompt = HopPrompt.new()
	_prompt.name = "HopPrompt"
	_world.add_child(_prompt)
	town.place_reached.connect(_on_place_reached)
	town.pad_reached.connect(_on_pad_reached)
	EventSystem.CAR_surface_changed.connect(_on_surface_changed)
	hud.setup(town, player, traffic, TownLayout.PLACE_NAMES.size())
	EventSystem.PRO_state_requested.emit()  # the HUD's coin count
	if not dev_start and "--autodrive" not in args:
		_restore_boat_spot()
	EventSystem.PRO_vehicle_kind_requested.emit(&"boat" if sailing else &"car")  # the pause menu's GARAGE
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
	if "--map" in args:
		$PauseMenu.pause()
		_open_map()
	if "--street-race" in args:
		var nearest: Array = street_race.starts.duplicate()
		nearest.sort_custom(func(x: Dictionary, y: Dictionary) -> bool:
			return x["at"].distance_to(player.global_position) < y["at"].distance_to(player.global_position))
		street_race.start(nearest[0]["route"])


## The pick-and-mix fun (§32): golden stars hidden round the island, the jobs board in the
## park, rides on the playgrounds, fireworks over the harbour at night.
func _add_fun(args: PackedStringArray) -> void:
	stars = GoldenStars.new()
	stars.name = "GoldenStars"
	stars.screen = self
	_world.add_child(stars)
	jobs = JobsBoard.new()
	jobs.name = "JobsBoard"
	jobs.screen = self
	jobs.position = town.fountain_at + JOBS_BOARD_AT
	_world.add_child(jobs)
	_world.move_child(jobs, _cars.get_index())
	var forced: Array = []
	for arg in args:
		if arg.begins_with("--jobs="):
			forced = Array(arg.get_slice("=", 1).split(",")).map(func(k: String) -> StringName: return StringName(k))
	jobs.begin(Time.get_date_string_from_system(), _jobs_saved, forced)
	rides = PlaygroundRides.new()
	rides.name = "PlaygroundRides"
	rides.screen = self
	_world.add_child(rides)
	fireworks = Fireworks.new()
	fireworks.name = "Fireworks"
	fireworks.screen = self
	fireworks.always = "--fireworks" in args
	add_child(fireworks)
	move_child(fireworks, hud.get_index())
	snow_hill = SnowHill.new()
	snow_hill.name = "SnowHill"
	snow_hill.screen = self
	add_child(snow_hill)
	move_child(snow_hill, hud.get_index())
	for walker in _walkers.get_children():
		if walker is Walker:
			walker.petted.connect(func(_w: Walker) -> void: job(&"pet"))
	EventSystem.CAR_washed.connect(func(washed: Node) -> void:
		if washed == player:
			job(&"wash"))
	EventSystem.CAR_landed.connect(func(landed: Node) -> void:
		if landed == player and not landed is Boat:
			job(&"jump"))


## Something on the jobs board happened (§32).
func job(kind: StringName, count := 1) -> void:
	if jobs:
		jobs.progress(kind, count)


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
		input.set_script(KID_INPUT if vehicle is Kid else PLAYER_INPUT)
	vehicle.add_child(input)
	var rig := Node2D.new()
	rig.name = "ChaseCamera"
	rig.set_script(CAMERA_SCRIPT)
	if vehicle is Kid:
		rig.zoom_level = KID_ZOOM  # closer in on foot
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


# --- the open world (§28): race gates, doors, the saved spot, the map ----------------------

## A gate for every track: the car tracks' on the grass, the boat courses' at sea. Under the cars.
func _add_gates() -> void:
	var layer := Node2D.new()
	layer.name = "Gates"
	_world.add_child(layer)
	_world.move_child(layer, _cars.get_index())
	for spec: Dictionary in town.gates:
		var id: StringName = spec["track_id"]
		var entry: Dictionary = _world_tracks.get(id, {})
		var config: TrackConfig = entry["config"] if entry.has("config") else load(GarageManager.TRACK_DIR + String(id) + ".tres")
		var gate := RaceGate.new()
		gate.name = String(id).to_pascal_case() + "Gate"
		gate.config = config
		gate.kind = spec["kind"]
		gate.unlocked = entry.get("unlocked", true)
		gate.position = spec["at"]
		gate.rotation = (spec["facing"] as Vector2).angle()
		gate.watch = player
		layer.add_child(gate)
		gates.append(gate)


## On a gate's place, in the right vehicle for it: its card (and the racers toot hello); off it,
## no card.
func _check_gates() -> void:
	for gate in gates:
		if gate.kind != riding:
			continue
		var mode := &"race" if gate.is_on_slot(player.global_position) else \
			(&"time_trial" if gate.is_on_stopwatch(player.global_position) else &"")
		if mode == &"":
			continue
		if hud.gate_shown != gate or hud.gate_mode != mode:
			var entry: Dictionary = _world_tracks.get(gate.config.track_id, {})
			hud.show_gate(gate, gate.config, gate.unlocked, entry.get("best_lap", 0.0), entry.get("completed", false),
				_opened_by(gate).config.display_name if _opened_by(gate) else "", mode)
			if gate.unlocked and mode == &"race":
				gate.cheer()
		return
	hud.hide_gate()


## The gate whose race opens `gate` (the one before it of its kind), or null.
func _opened_by(gate: RaceGate) -> RaceGate:
	var same := gates.filter(func(g: RaceGate) -> bool: return g.kind == gate.kind)
	var i := same.find(gate)
	return same[i - 1] if i > 0 else null


## Y / R or Enter on a gate's card: the race (or, locked, the way to the race that opens it).
func _unhandled_input(event: InputEvent) -> void:
	var gate := hud.gate_shown as RaceGate
	if _leaving or _swapping:
		return
	if not street_race.shown.is_empty() and not street_race.running:
		var go: bool = event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)
		if go or event.is_action_pressed("race_start"):
			get_viewport().set_input_as_handled()
			street_race.start(street_race.shown["route"])
			return
	if gate == null:
		if event.is_action_pressed(&"get_in_out") and not event.is_echo():
			if riding == &"foot" and _hop_in_near():
				get_viewport().set_input_as_handled()
				get_in(_hop_in_near())
			elif riding == &"car" and can_get_out():
				get_viewport().set_input_as_handled()
				get_out()
		return
	var enter: bool = event is InputEventKey and event.pressed and not event.echo \
		and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER)
	if not (enter or event.is_action_pressed("race_start")):
		return
	get_viewport().set_input_as_handled()
	if gate.unlocked:
		_start_race(gate, hud.gate_mode)
	else:
		var opener := _opened_by(gate)
		if opener:
			set_pin(opener.slot, opener.racers[0].body_texture if not opener.racers.is_empty() else null)


## Off to the race on `gate`'s track: the spot saved on its place, so DRIVE ON comes back here.
func _start_race(gate: RaceGate, mode := &"race") -> void:
	_leaving = true
	if mode == &"time_trial":
		save_spot(gate.stopwatch, gate.slot_angle())
	else:
		save_spot(gate.slot, gate.slot_angle())
	EventSystem.PRO_vehicle_kind_requested.emit(gate.kind)
	EventSystem.PRO_track_select_requested.emit(gate.config.track_id)
	EventSystem.PRO_race_mode_requested.emit(mode)
	await hud.fade(true)
	EventSystem.UI_screen_requested.emit(&"race")


## Pads that open a screen: [where, the screen, the vehicle kind it shows, the way the car
## comes back out]. The garage and the trophy house face the road below them; the rocket pad
## sends the car back east, towards the town.
func _doors() -> Array:
	var out := []
	for door: Dictionary in town.doors:
		out.append([door["pad"], door["screen"], &"car", PI / 2.0])
	out.append([town.rocket_pad, &"garage", &"ship", 0.0])
	return out


## Into the garage (in the cars' or the ships' colours) or the trophy house. Coming back, the car
## is on the pad, which does nothing until it has been left.
func _go_inside(screen: StringName, pad: Rect2, kind: StringName, angle: float) -> void:
	_leaving = true
	save_spot(pad.get_center(), angle)
	EventSystem.PRO_vehicle_kind_requested.emit(kind)
	if screen in [&"tracks", &"editor"]:
		EventSystem.PRO_back_to_requested.emit(&"town")  # the stadium, the workshop: BACK comes out here
	if kind == &"ship":
		await _launch()
	await hud.fade(true)
	EventSystem.UI_screen_requested.emit(screen)


## The rocket pad (§31): the car rolls into the rocket, 3, 2, 1, and the rocket lifts off in a
## roar of flame, up and away off the top of the screen, before the Hangar opens.
func _launch() -> void:
	var rocket := town.rocket
	if rocket == null:
		return
	player.frozen = true
	var into := player.create_tween()
	into.tween_property(player, "global_position", rocket.global_position, 0.4).set_trans(Tween.TRANS_QUAD)
	into.parallel().tween_property(player, "modulate:a", 0.0, 0.4)
	for n in ["3", "2", "1"]:
		hud.show_banner(n)
		_play(BEEP, -8.0)
		await get_tree().create_timer(0.55).timeout
	hud.show_banner("LIFT OFF!")
	_play(LIFT_OFF, -2.0)
	var flame := CPUParticles2D.new()
	flame.name = "Flame"
	flame.position = Vector2(-rocket.texture.get_width() * 0.45, 0)  # its tail: the rocket points up (-X is down)
	flame.amount = 60
	flame.lifetime = 0.6
	flame.direction = Vector2.LEFT
	flame.spread = 18.0
	flame.initial_velocity_min = 300.0
	flame.initial_velocity_max = 520.0
	flame.scale_amount_min = 8.0
	flame.scale_amount_max = 16.0
	flame.color_ramp = Gradient.new()
	flame.color_ramp.set_color(0, Color(1, 0.95, 0.5))
	flame.color_ramp.set_color(1, Color(1, 0.3, 0.1, 0.0))
	flame.show_behind_parent = true
	flame.scale = Vector2.ONE / rocket.scale  # in pixels on screen, whatever size the picture is
	rocket.add_child(flame)
	var up := rocket.create_tween()
	up.tween_interval(0.35)
	up.tween_property(rocket, "global_position", rocket.global_position + Vector2(0, -1500), 1.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	up.parallel().tween_property(rocket, "scale", rocket.scale * 1.5, 1.5)
	await up.finished


## Save where the child is (or `at`, facing `angle`), and in what: the car or the boat. In the
## fire engine or the bus, the car is saved at their pad, where it would come back.
func save_spot(at := Vector2.INF, angle := 0.0) -> void:
	var kind := &"boat" if sailing else &"car"
	if at == Vector2.INF:
		match riding:
			&"fire_engine":
				at = town.fire_pad.get_center()
				angle = PI / 2.0
			&"bus":
				at = town.bus_pad.get_center()
				angle = PI / 2.0
			&"foot":  # the car, where he left it
				at = car.global_position
				angle = car.rotation
			_:
				at = player.global_position
				angle = player.rotation
	var spot := {"x": at.x, "y": at.y, "angle": angle, "riding": kind}
	_world_spot = spot
	EventSystem.PRO_world_spot_saved.emit(spot)


## Leaving for the garage or the title (the pause menu), or the window closing: remember the
## spot, unless leaving for somewhere that saved its own (a gate's place, a pad). Done as the
## screen is asked for, while the car is still in the tree.
func _on_screen_requested(_screen: StringName) -> void:
	if not _leaving and is_inside_tree() and is_instance_valid(player):
		_leaving = true
		street_race.abandon()
		save_spot()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_screen_requested(&"")


## The car back where it was left (on land; at sea the boat follows once the harbour is ready).
## Nothing to do the first time: the car starts by the candy shop.
func _restore_car_spot() -> void:
	if _world_spot.is_empty() or _world_spot.get("riding", &"car") != &"car":
		return
	var at := Vector2(float(_world_spot["x"]), float(_world_spot["y"]))
	if not town.map_rect().has_point(at):
		return
	_place(car, at, float(_world_spot.get("angle", 0.0)))
	_pad_armed = false  # back on a pad: it waits until the car has left it
	car.get_node(^"ChaseCamera").snap_to_car()


## Out at sea last time: the boat, where it was.
func _restore_boat_spot() -> void:
	if _world_spot.get("riding", &"car") != &"boat":
		return
	var at := Vector2(float(_world_spot["x"]), float(_world_spot["y"]))
	if not town.map_rect().has_point(at):
		return
	_swap_now(&"boat")
	_place(boat, at, float(_world_spot.get("angle", 0.0)))
	_pad_armed = false
	boat.get_node(^"ChaseCamera").snap_to_car()


## Show the way to `at` (chosen on the map, or a locked gate's opener): an arrow at the edge of
## the screen with `picture`, and a white dot on the map, until the child gets there. A job's
## own arrow comes first while one is on.
func set_pin(at: Vector2, picture: Texture2D) -> void:
	_pin = {"at": at, "picture": picture}


func _follow_pin() -> void:
	if _pin.is_empty() or street_race.running:
		return
	if player.global_position.distance_to(_pin["at"]) < PIN_REACH:
		_pin = {}
		if errands.errand == &"":
			hud.point_at(Vector2.INF, null)
		return
	if errands.errand == &"":
		hud.point_at(_pin["at"], _pin["picture"])


## The pause menu's MAP: the whole island, over the paused game.
func _add_map() -> void:
	_map_layer = CanvasLayer.new()
	_map_layer.name = "WorldMapLayer"
	_map_layer.layer = 11  # over the pause menu
	_map_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_map_layer)
	var backdrop := ColorRect.new()
	backdrop.name = "Backdrop"
	backdrop.color = Color(0.055, 0.078, 0.11, 0.92)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_layer.add_child(backdrop)
	_map = WORLD_MAP.new()
	_map.name = "WorldMap"
	_map.theme = preload("res://ui/theme/vicky_theme.tres")
	_map.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map.offset_left = 140.0
	_map.offset_right = -140.0
	_map.offset_top = 30.0
	_map.offset_bottom = -170.0
	_map_layer.add_child(_map)
	_map_layer.visible = false
	var pause_menu := $PauseMenu
	pause_menu.enable_map()
	pause_menu.map_requested.connect(_open_map)
	_map.closed.connect(func() -> void:
		_map_layer.visible = false
		pause_menu.back_from_map())
	_map.chosen.connect(func(place: Dictionary) -> void:
		_map_layer.visible = false
		set_pin(place["at"], place["picture"])
		pause_menu.resume())


func _open_map() -> void:
	_map_layer.visible = true
	_map.stars = Vector2i(stars.found.size(), stars.spots.size())
	_map.open(town, player, traffic, map_places())


## What the map shows (WorldMap.places): every race gate, the garage, the trophy house, the
## rocket pad, the harbour and the snowy hill.
func map_places() -> Array:
	var out := []
	for gate in gates:
		var entry: Dictionary = _world_tracks.get(gate.config.track_id, {})
		out.append({"at": gate.slot, "name": gate.config.display_name.to_upper(), "done": entry.get("completed", false),
			"locked": not gate.unlocked, "picture": gate.racers[0].body_texture if not gate.racers.is_empty() else null})
	for door: Dictionary in town.doors:
		out.append({"at": door["pad"].get_center(), "name": TownLayout.DOOR_NAMES[door["id"]],
			"picture": load(Town.BUILDING_ART % door["id"])})
	out.append({"at": town.rocket_pad.get_center(), "name": "ROCKET", "picture": ROCKET_ART})
	out.append({"at": Island.LAND_PAD.get_center(), "name": "HARBOUR", "picture": HARBOUR_ART})
	out.append({"at": SnowIsland.HILL, "name": "SNOWY HILL", "picture": Town.SNOWMAN})
	if riding == &"foot":
		out.append({"at": car.global_position, "name": "MY CAR", "picture": car.body_texture})
	return out


# --- on foot (§29): out of the car, into it or another, the whistle --------------------

## Stopped in a car (not on a pad or a gate's place): he may get out.
func can_get_out() -> bool:
	return riding == &"car" and not street_race.running and player.velocity.length() < GET_OUT_SPEED \
		and not CarHop.airborne(player) \
		and _spot_beside(player) != Vector2.INF


## Out of the car: it stays parked where it stood, its seat empty, and Vicky stands beside it
## (on the driver's side if there is room there, else the other side, else behind).
func get_out() -> void:
	var from := player
	var at := _spot_beside(from)
	if at == Vector2.INF:
		return
	_park(from)
	from.driver_id = &""
	from.add_to_group(&"parked")
	if from not in hop_ins:
		hop_ins.append(from)
	if kid == null:
		kid = Kid.make()
		_cars.add_child(kid)
	else:
		_unstow(kid)
	kid.add_to_group(&"walkers")  # traffic waits for him crossing, as for the ducks
	_place(kid, at, (at - from.global_position).angle())
	_drive(kid)
	riding = &"foot"
	_changed_vehicle()
	_play(DOOR, -14.0)


## Into `vehicle` (his own car, or a driveway car to borrow: then it is the car for now, and his
## own waits parked where he left it, to come back to or whistle for).
func get_in(vehicle: Car) -> void:
	if vehicle == null or riding != &"foot":
		return
	_park(kid)
	_stow(kid)
	kid.remove_from_group(&"walkers")
	vehicle.remove_from_group(&"parked")
	hop_ins.erase(vehicle)
	if vehicle.has_meta(&"sign"):
		var sign: Node2D = vehicle.get_meta(&"sign")
		vehicle.remove_meta(&"sign")
		sign.create_tween().tween_property(sign, "scale", Vector2.ZERO, 0.3).finished.connect(sign.queue_free)
		TownFx.hearts(_world, vehicle.global_position, 5)
	vehicle.driver_id = DriverLook.VICKY
	car = vehicle
	_drive(vehicle)
	riding = &"car"
	_changed_vehicle()
	_play(DOOR, -14.0)


## After getting in or out: everything that follows the player follows the new one.
func _changed_vehicle() -> void:
	_pad_armed = false
	_stopped = 0.0
	_sea_life.player = player
	for gate in gates:
		gate.watch = player
	hud.set_vehicle(player, riding)
	errands.carry(player)


## The parked car he is near enough to get into, nearest first; null if none.
func _hop_in_near() -> Car:
	var best: Car = null
	for vehicle in hop_ins:
		if is_instance_valid(vehicle) and vehicle.global_position.distance_to(kid.global_position) < HOP_REACH \
				and (best == null or vehicle.global_position.distance_to(kid.global_position) < best.global_position.distance_to(kid.global_position)):
			best = vehicle
	return best


## Somewhere to stand beside `vehicle`: its left (the driver's door), its right, behind it.
func _spot_beside(vehicle: Car) -> Vector2:
	var forward := Vector2.RIGHT.rotated(vehicle.rotation)
	for offset in [forward.orthogonal() * 70.0, -forward.orthogonal() * 70.0, -forward * 110.0]:
		var at: Vector2 = vehicle.global_position + offset
		if town.surface_at(at) in [&"water", &"lagoon_water", &"deep_water", &"sandbank"]:
			continue
		if town.footprints.any(func(r: Rect2) -> bool: return r.grow(24.0).has_point(at)):
			continue
		return at
	return Vector2.INF


## The bubble over what E / Y would do now: over a car he can get into, or, stopped in a car
## for a moment, by its door.
func _update_prompt(delta: float) -> void:
	var gamepad: bool = hud.gamepad
	if riding == &"foot":
		var near := _hop_in_near()
		_prompt.show_at(near, gamepad, false)
	elif riding == &"car" and hud.gate_shown == null and street_race.shown.is_empty():
		_stopped = _stopped + delta if can_get_out() else 0.0
		_prompt.show_at(player if _stopped > 0.8 else null, gamepad, true)
	else:
		_prompt.show_at(null, gamepad, false)


## On foot, the horn is a whistle. Far from the car, it comes: gone in a puff, and parked by the
## kerb of the nearest road, facing along it. Near it, the car toots back.
func _whistle() -> void:
	_play(WHISTLE, -6.0)
	if car.global_position.distance_to(kid.global_position) < WHISTLE_AWAY:
		EventSystem.CAR_horn.emit(car)
		return
	var best := Vector2.INF
	var along := Vector2.RIGHT
	for road: Array in town.roads:
		for pair in [[road[0], road[1]], [road[1], road[0]]]:
			var lane := town.lane_points(pair[0], pair[1])
			var heading := town.heading(pair[0], pair[1])
			for i in range(2, lane.size() - 2):  # not in a junction
				var kerb: Vector2 = lane[i] + Town.right_of(heading) * (TownLayout.ROAD_HALF - Town.LANE + 40.0)
				if kerb.distance_to(kid.global_position) < best.distance_to(kid.global_position):
					best = kerb
					along = heading
	if best == Vector2.INF:
		return
	TownFx.confetti(_world, car.global_position)
	_place(car, best, along.angle())
	TownFx.confetti(_world, best)
	EventSystem.CAR_horn.emit(car)


## Cars parked in the driveways (Town.parking), a different one in each, in a paint of its own,
## nobody at the wheel and a sign with a key: free to borrow.
func _add_driveway_cars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2029
	var choices := _car_setups.filter(func(setup: DriftSetup) -> bool: return _setup == null or setup.id != _setup.id)
	if choices.is_empty():
		return
	for i in town.parking.size():
		var spot: Dictionary = town.parking[i]
		var setup: DriftSetup = choices[(i * 5 + rng.randi() % 3) % choices.size()]
		var paint: StringName = Paint.COLOURS[rng.randi() % Paint.COLOURS.size()]
		var parked: Car = CAR_SCENE.instantiate()
		parked.name = "Driveway%d" % i
		parked.setup = setup
		parked.body_texture = Paint.body(setup, paint)
		parked.driver_id = &""
		_cars.add_child(parked)
		_place(parked, spot["at"], spot["angle"])
		parked.frozen = true
		parked.get_node(^"Audio").process_mode = Node.PROCESS_MODE_DISABLED
		parked.add_to_group(&"parked")
		hop_ins.append(parked)
		var sign := KeySign.new()
		sign.name = "KeySign%d" % i
		sign.position = spot["at"] + Vector2(70, -40)
		_world.add_child(sign)
		parked.set_meta(&"sign", sign)


## A little round sign on a post with a key on it: this car is free to borrow.
class KeySign extends Node2D:
	var _time := randf() * TAU

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var top := Vector2(0, -60 + sin(_time * 2.5) * 4.0)
		draw_line(Vector2.ZERO, top, Color(0.45, 0.32, 0.2), 7.0)
		draw_circle(top, 30.0, Color(0.055, 0.078, 0.11))
		draw_circle(top, 26.0, Color(0.18, 0.77, 0.42))
		# The key: a ring and a blade with two teeth.
		var gold := Color(1, 0.86, 0.3)
		draw_arc(top + Vector2(-8, 0), 8.0, 0.0, TAU, 16, gold, 5.0, true)
		draw_line(top + Vector2(0, 0), top + Vector2(16, 0), gold, 5.0)
		draw_line(top + Vector2(12, 0), top + Vector2(12, 7), gold, 4.0)
		draw_line(top + Vector2(17, 0), top + Vector2(17, 7), gold, 4.0)


## The bubble over what E / Y does: a white bubble with the button in it, bobbing, over the car
## to get into, or beside the car to get out of with a little arrow pointing out.
class HopPrompt extends Node2D:
	var _over: Node2D
	var _gamepad := false
	var _out := false
	var _time := 0.0

	func _ready() -> void:
		z_index = 6
		visible = false

	func show_at(over: Node2D, gamepad: bool, out: bool) -> void:
		if over != _over or gamepad != _gamepad or out != _out:
			_over = over
			_gamepad = gamepad
			_out = out
			visible = over != null
			scale = Vector2(0.4, 0.4)
			if visible:
				create_tween().tween_property(self, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	func _process(delta: float) -> void:
		_time += delta
		if _over and is_instance_valid(_over):
			global_position = _over.global_position + Vector2(80, -90 + sin(_time * 4.0) * 6.0)
			queue_redraw()

	func _draw() -> void:
		var ink := Color(0.055, 0.078, 0.11)
		draw_colored_polygon(PackedVector2Array([Vector2(-14, 24), Vector2(14, 24), Vector2(0, 46)]), Color.WHITE)
		draw_circle(Vector2.ZERO, 36.0, ink)
		draw_circle(Vector2.ZERO, 31.0, Color.WHITE)
		var key := "Y" if _gamepad else "E"
		var font := ThemeDB.fallback_font
		var size := font.get_string_size(key, HORIZONTAL_ALIGNMENT_CENTER, -1, 36)
		draw_circle(Vector2.ZERO, 22.0, Color(1, 0.824, 0.247) if _gamepad else Color(0.9, 0.92, 0.95))
		draw_string(font, Vector2(-size.x / 2.0, 13.0), key, HORIZONTAL_ALIGNMENT_CENTER, -1, 36, ink)
		# Getting out: a little arrow out of the bubble; getting in: one into it.
		var y := 0.0
		var x := 48.0
		var tip := Vector2(x + 18.0, y) if _out else Vector2(x - 6.0, y)
		var back := Vector2(x - 6.0, y) if _out else Vector2(x + 18.0, y)
		draw_line(back, tip, ink, 6.0)
		var d := (tip - back).normalized()
		draw_line(tip, tip - d * 10.0 + d.orthogonal() * 8.0, ink, 6.0)
		draw_line(tip, tip - d * 10.0 - d.orthogonal() * 8.0, ink, 6.0)


# --- swapping vehicles: the harbour (§21.3), the fire station and the school (§23) -------

func _physics_process(delta: float) -> void:
	if player == null:
		return
	_check_fountain(delta)
	_check_goal(delta)
	_follow_pin()
	hud.set_marks(errands.marks() + fire_duty.marks() + street_race.marks()
		+ ([[_pin["at"], Color.WHITE]] if not _pin.is_empty() else []))
	_save_in -= delta
	if _save_in <= 0.0 and not _leaving:
		_save_in = SAVE_EVERY
		save_spot()
	if _swapping or _leaving or player.has_node(^"TrafficDriver"):
		hud.hide_gate()
		return
	if street_race.running:
		hud.hide_gate()
		_prompt.show_at(null, false, false)
		return
	street_race.check(player, riding)
	_check_gates()
	var near_a_pad := false
	_update_prompt(delta)
	if riding in [&"car", &"foot"]:
		for door: Array in _doors():
			var rect: Rect2 = door[0]
			if rect.grow(60.0).has_point(player.global_position):
				near_a_pad = true
			if rect.has_point(player.global_position) and _pad_armed and player.velocity.length() < SWAP_MAX_SPEED:
				_go_inside(door[1], door[0], door[2], door[3])
				return
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
	for gate in gates:
		gate.watch = player
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
	job(&"coins")
	get_tree().create_timer(COIN_RESPAWN, false).timeout.connect(func() -> void:
		if is_instance_valid(coin):
			coin.reappear(coin.position if coin.has_meta(&"fixed") else _coin_spot()))


## Coins earned at `at`: banked at once, and a +N floats up from there.
func pay(amount: int, at: Vector2) -> void:
	EventSystem.PRO_coins_found.emit(amount)
	hud.coin_popped(at, amount)


func _on_place_reached(place_id: String, display_name: String, picture: Texture2D) -> void:
	if riding in [&"car", &"foot"]:  # the shops serve him on foot too (§29)
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
	_show_night()
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


## Night on or off as the garage says: when the town is built, and when N switches it. At
## night the town is dark blue, everything that drives has its lights on (Night), and a warm
## lamp glows by every house's front door (docs/DESIGN.md §27).
func _show_night() -> void:
	if _night and night == null:
		night = Night.new()
		night.name = "Night"
		night.weather = weather
		add_child(night)
		_add_porch_lights()
	elif not _night and night:
		remove_child(night)
		night.queue_free()
		night = null
		var lamps := _world.get_node(^"PorchLights")
		_world.remove_child(lamps)
		lamps.queue_free()


func _add_porch_lights() -> void:
	var lamps := Node2D.new()
	lamps.name = "PorchLights"
	_world.add_child(lamps)
	for house in town.houses:
		var lamp := PointLight2D.new()
		lamp.texture = PORCH_GLOW
		lamp.color = Color(1.0, 0.78, 0.42)
		lamp.energy = 1.1
		lamp.texture_scale = 5.0
		lamp.position = house["door"] - Vector2(0, 40)
		lamps.add_child(lamp)


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
	elif where == "board":
		at = jobs.position + Vector2(0, 330)
		player.rotation = -PI / 2.0
	elif where in ["playground", "ride"]:
		var ground: Rect2 = town.playgrounds[0]
		_place(car, Vector2(ground.position.x - 300.0, ground.end.y + 150.0), 0.0)
		get_out()
		kid.global_position = rides.rides[2]["entry"] + Vector2(-110, 0)
		kid.rotation = 0.0
		kid.reset_physics_interpolation()
		kid.get_node(^"ChaseCamera").snap_to_car()
		if where == "ride":
			rides.play(rides.rides[1])
		return
	elif where == "snow":
		at = Vector2(SnowIsland.shore_x() - 500.0, SnowIsland.BRIDGE_Y + 70.0)
		player.rotation = 0.0
	elif where == "hill":
		at = SnowIsland.HILL + Vector2(-300, 700)
		player.rotation = -PI / 2.0
	elif where == "star":
		at = stars.spots[0] + Vector2(0, 260)
		player.rotation = -PI / 2.0
	elif where == "foot":
		get_out()
		return
	elif where == "drift":
		at = TownChallenges.DRIFT_ZONE.position + Vector2(TownChallenges.DRIFT_ZONE.size.x - 90.0, TownChallenges.DRIFT_ZONE.size.y / 2.0)
		player.rotation = PI
	elif where.begins_with("street"):
		var start: Dictionary = street_race.starts[clampi(int(where.substr(6)), 0, street_race.starts.size() - 1)]
		at = start["at"] - Vector2.RIGHT.rotated(start["angle"]) * 60.0
		player.rotation = start["angle"]
	elif where == "driveway":
		var parked: Car = hop_ins[0]
		_place(car, parked.global_position + Vector2(0, 520), -PI / 2.0)
		get_out()
		kid.global_position = parked.global_position + Vector2(0, 150)
		kid.rotation = -PI / 2.0
		kid.reset_physics_interpolation()
		kid.get_node(^"ChaseCamera").snap_to_car()
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
	elif where.begins_with("watch"):
		var gate := gates[clampi(int(where.substr(5)), 0, gates.size() - 1)]
		at = gate.stopwatch + Vector2.RIGHT.rotated(gate.global_rotation) * 40.0
		player.rotation = gate.slot_angle()
	elif where.begins_with("gate"):
		var gate := gates[clampi(int(where.substr(4)), 0, gates.size() - 1)]
		if gate.kind == &"boat":
			_swap_now(&"boat")
		at = gate.slot
		player.rotation = gate.slot_angle()
	elif where in ["garage", "trophies", "stadium", "workshop"]:
		var id: String = {"garage": "garage", "trophies": "trophy_house", "stadium": "stadium", "workshop": "workshop"}[where]
		var door: Dictionary = town.doors.filter(func(d: Dictionary) -> bool: return d["id"] == id)[0]
		at = door["pad"].get_center() + Vector2(0, 280)
		player.rotation = -PI / 2.0
	elif where == "rocket":
		at = town.rocket_pad.get_center() + Vector2(420, 0)
		player.rotation = PI
	elif where == "house":
		at = town.houses[3]["door"] + Vector2(-300, 70)
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

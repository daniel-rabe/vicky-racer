class_name StreetRace
extends Node2D
## Street races through the town itself (docs/DESIGN.md §30), the open-world plan's idea 15: no
## track of their own, just glowing rings round the town's streets. A checkered line across the
## road marks where each route starts; pulling up on it shows the route's card, and R / Y (or
## Enter) starts it: the three racers line up beside the player, the traffic pulls in and waits
## (faded, out of the way), 3, 2, 1, GO. The next ring glows yellow and the arrow at the screen's
## edge points to it; the last ring is the start line again. Can't be lost: there is no clock,
## and finishing in any place pays coins. Then the racers drive off and the traffic goes again.
##
## The racers drive the route with a RouteDriver each. Everything to see is drawn in code.

signal started(route: Dictionary)
signal finished(route: Dictionary, place: int)

## Each route: the junctions it goes round (Town.junctions), in order, back to the first; how
## many laps; how far along the road from the first junction to the second it starts (clear of
## the pads in front of the buildings).
const ROUTES := [
	{"id": &"park", "name": "ROUND THE PARK", "laps": 2, "start": 0.5,
		"cells": [Vector2i(3, 2), Vector2i(2, 2), Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(4, 2)]},
	{"id": &"zigzag", "name": "ZIG ZAG", "laps": 1, "start": 0.5,
		"cells": [Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 3), Vector2i(3, 4), Vector2i(2, 4), Vector2i(1, 4),
			Vector2i(0, 4), Vector2i(0, 3), Vector2i(0, 2), Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2)]},
	{"id": &"big_loop", "name": "THE BIG LOOP", "laps": 1, "start": 0.5,
		"cells": [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2),
			Vector2i(5, 3), Vector2i(5, 4), Vector2i(4, 4), Vector2i(3, 4), Vector2i(2, 4), Vector2i(1, 4),
			Vector2i(0, 4), Vector2i(0, 3), Vector2i(0, 2), Vector2i(0, 1), Vector2i(0, 0), Vector2i(1, 0)]},
]
## Corners are rounded off this far either side of the junction.
const CORNER := 220.0
const STEP := 40.0
const RING_RADIUS := 200.0
const PULL_UP := 260.0
const PULL_UP_SPEED := 320.0
const PAY := [15, 10, 6, 4]
const PLACES := ["1ST", "2ND", "3RD", "4TH"]
const GRID_BACK := 170.0
const GRID_SIDE := 75.0
const BEEP := "res://art/sfx/countdown_beep.wav"
const GO := "res://art/sfx/go_beep.wav"
const CHIME := "res://art/sfx/sparkle.wav"
const FANFARE := "res://art/sfx/finish_fanfare.wav"
const YELLOW := Color(1, 0.824, 0.247)
const INK := Color(0.055, 0.078, 0.11)

## The town screen (TownScreen): the town, the player, the traffic, the HUD.
var screen: Node
## Each route's start: {"route", "at", "angle"}.
var starts: Array[Dictionary] = []
var running := false
var route: Dictionary = {}
var shown: Dictionary = {}  # the start whose card is showing
var racers: Array[Car] = []
var rings: Array[Vector2] = []
var next_ring := 0
## Where the route's line is, and how far along it each ring is.
var _points := PackedVector2Array()
var _lengths := PackedFloat32Array()
var _ring_at: Array[float] = []
var _counting := false
var _traffic_was: Array = []
var _time := 0.0
var _layer: CanvasLayer
var _card: PanelContainer
var _card_name: Label
var _card_go: Label
var _card_map: RouteMap
var _count: Label
var _place: Label
var _plate: PanelContainer
var _voice: AudioStreamPlayer
var _flag: Texture2D


func _ready() -> void:
	z_index = 1
	for spec: Dictionary in ROUTES:
		var cells: Array = spec["cells"]
		var a: Vector2 = screen.town.junctions[cells[0]]
		var b: Vector2 = screen.town.junctions[cells[1]]
		starts.append({"route": spec, "at": a.lerp(b, spec["start"]), "angle": (b - a).angle()})
	_flag = _flag_texture()
	_build_hud()
	_voice = AudioStreamPlayer.new()
	_voice.bus = &"SFX"
	add_child(_voice)


## Every route's junctions are joined by roads (checked by the tests).
static func route_ok(town: Town, spec: Dictionary) -> bool:
	var cells: Array = spec["cells"]
	for i in cells.size():
		if not town.links.get(cells[i], []).has(cells[(i + 1) % cells.size()]):
			return false
	return true


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Each frame from the town screen while not racing: the card while the player's car is pulled
## up on a start line.
func check(player: Car, riding: StringName) -> void:
	if running:
		return
	var here: Dictionary = {}
	if riding == &"car" and player.velocity.length() < PULL_UP_SPEED:
		for start in starts:
			if player.global_position.distance_to(start["at"]) < PULL_UP:
				here = start
	if here != shown:
		shown = here
		_show_card(here)


## R / Y on the card: off we go.
func start(spec: Dictionary) -> void:
	if running:
		return
	running = true
	route = spec
	shown = {}
	_show_card({})
	_build_line(spec)
	next_ring = 0
	var start_spot: Dictionary = starts.filter(func(s: Dictionary) -> bool: return s["route"] == spec)[0]
	var forward := Vector2.RIGHT.rotated(start_spot["angle"])
	var right := -forward.orthogonal()
	var player: Car = screen.player
	_line_up(player, start_spot["at"] - forward * GRID_BACK + right * GRID_SIDE, start_spot["angle"])
	_pull_traffic_in()
	_spawn_racers(start_spot, forward, right)
	player.frozen = true
	started.emit(spec)
	_countdown()


func _line_up(car: Car, at: Vector2, angle: float) -> void:
	car.global_position = at
	car.rotation = angle
	car.velocity = Vector2.ZERO
	car.reset_physics_interpolation()
	var camera := car.get_node_or_null(^"ChaseCamera")
	if camera:
		camera.snap_to_car()


## The route's line: from the start, round every junction (corners rounded off), back to the
## start, as many times as it has laps; a ring at every junction, and the start line last.
func _build_line(spec: Dictionary) -> void:
	var cells: Array = spec["cells"]
	var town: Town = screen.town
	var corners := PackedVector2Array()
	var start: Vector2 = town.junctions[cells[0]].lerp(town.junctions[cells[1]], spec["start"])
	corners.append(start)
	rings.clear()
	for lap in spec["laps"]:
		for i in cells.size():
			var j: Vector2 = town.junctions[cells[(i + 1) % cells.size()]]
			corners.append(j)
			rings.append(j)
		corners.append(start)
		rings.append(start)
	# Round the corners and walk it in even steps.
	var smooth := PackedVector2Array([corners[0]])
	for i in range(1, corners.size() - 1):
		var j := corners[i]
		var din := (j - corners[i - 1]).normalized()
		var dout := (corners[i + 1] - j).normalized()
		if absf(din.angle_to(dout)) < 0.1:
			smooth.append(j)
			continue
		var p0 := j - din * CORNER
		var p2 := j + dout * CORNER
		for k in 9:
			var t := k / 8.0
			smooth.append(p0.lerp(j, t).lerp(j.lerp(p2, t), t))
	smooth.append(corners[corners.size() - 1])
	_points = PackedVector2Array([smooth[0]])
	_lengths = PackedFloat32Array([0.0])
	for i in range(1, smooth.size()):
		var a := _points[_points.size() - 1]
		var b := smooth[i]
		var span := a.distance_to(b)
		var n := maxi(1, int(span / STEP))
		for k in range(1, n + 1):
			var p := a.lerp(b, float(k) / n)
			_lengths.append(_lengths[_lengths.size() - 1] + _points[_points.size() - 1].distance_to(p))
			_points.append(p)
	# Each ring is where the line next comes closest to it.
	_ring_at.clear()
	var from := 0
	for ring in rings:
		var best_i := from
		var best_d := INF
		for i in range(from, _points.size()):
			var d := _points[i].distance_to(ring)
			if d < best_d:
				best_d = d
				best_i = i
			elif best_d < 250.0 and d > best_d + 100.0:
				break
		from = best_i + 1
		_ring_at.append(_lengths[best_i])


## How far along a line (`points`, with `lengths` along it) the nearest point to `at` is,
## looking a little behind and well ahead of `near`.
static func progress_on(points: PackedVector2Array, lengths: PackedFloat32Array, at: Vector2, near: float) -> float:
	var from := maxi(lengths.bsearch(near - 400.0) - 1, 0)
	var to := mini(lengths.bsearch(near + 900.0) + 1, points.size() - 1)
	var best := near
	var best_d := INF
	for i in range(from, to):
		var a := points[i]
		var b := points[i + 1]
		var ab := b - a
		var t := clampf((at - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
		var d := at.distance_squared_to(a + ab * t)
		if d < best_d:
			best_d = d
			best = lengths[i] + (lengths[i + 1] - lengths[i]) * t
	return best


## The traffic pulls in and waits: still, faded, and nothing to bump into.
func _pull_traffic_in() -> void:
	_traffic_was.clear()
	for car: Car in screen.traffic:
		var driver := car.get_node_or_null(^"TrafficDriver")
		if driver:
			driver.process_mode = Node.PROCESS_MODE_DISABLED
		car.frozen = true
		car.velocity = Vector2.ZERO
		car.collision_layer = 0
		car.collision_mask = 0
		car.create_tween().tween_property(car, "modulate:a", 0.4, 0.4)
		_traffic_was.append(car)


func _let_traffic_go() -> void:
	for car: Car in _traffic_was:
		if not is_instance_valid(car):
			continue
		var driver := car.get_node_or_null(^"TrafficDriver")
		if driver:
			driver.process_mode = Node.PROCESS_MODE_INHERIT
		car.frozen = false
		car.set_level(0)
		car.create_tween().tween_property(car, "modulate:a", 1.0, 0.6)
	_traffic_was.clear()


## BLUE, YELLOW and GREEN in cars of their own, on the grid beside and behind the player.
func _spawn_racers(start_spot: Dictionary, forward: Vector2, right: Vector2) -> void:
	var setups: Array = screen._car_setups.filter(func(s: DriftSetup) -> bool:
		return s.id != screen.car.setup.id and s.id != &"soapbox")
	var grid := [start_spot["at"] - forward * GRID_BACK - right * GRID_SIDE,
		start_spot["at"] - forward * (GRID_BACK * 2.0) + right * GRID_SIDE,
		start_spot["at"] - forward * (GRID_BACK * 2.0) - right * GRID_SIDE]
	for i in 3:
		var racer: Car = screen.CAR_SCENE.instantiate()
		racer.name = "StreetRacer%d" % i
		if not setups.is_empty():
			var setup: DriftSetup = setups[(i * 4 + route["cells"].size()) % setups.size()]
			racer.setup = setup
			racer.body_texture = Paint.body(setup, Paint.COLOURS[(i * 3 + 1) % Paint.COLOURS.size()])
		racer.driver_id = DriverLook.OPPONENTS[i]
		screen.get_node(^"World/Cars").add_child(racer)
		_line_up(racer, grid[i], start_spot["angle"])
		racer.frozen = true
		var driver := RouteDriver.new()
		driver.name = "RouteDriver"
		driver.points = _points
		driver.lengths = _lengths
		driver.lane = [-1.0, 1.0, -1.0][i] * 55.0
		driver.skill = [0.9, 0.86, 0.82][i]
		racer.add_child(driver)
		racers.append(racer)


func _countdown() -> void:
	_counting = true
	for n in ["3", "2", "1"]:
		_say(n, BEEP)
		await get_tree().create_timer(0.8, false).timeout
		if not running:
			return
	_say("GO!", GO)
	_counting = false
	_plate.visible = true
	screen.player.frozen = false
	for racer in racers:
		racer.frozen = false
	await get_tree().create_timer(0.7, false).timeout
	_count.modulate.a = 0.0


func _say(text: String, sound: String) -> void:
	_count.text = text
	_count.modulate.a = 1.0
	_count.scale = Vector2(1.6, 1.6)
	_count.create_tween().tween_property(_count, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_play(sound, -4.0)


func _physics_process(_delta: float) -> void:
	if not running or _counting:
		return
	var player: Car = screen.player
	if next_ring < rings.size() and player.global_position.distance_to(rings[next_ring]) < RING_RADIUS:
		next_ring += 1
		if next_ring >= rings.size():
			_finish()
			return
		_play(CHIME, -8.0)
	var mine := player_progress()
	for racer in racers:
		(racer.get_node(^"RouteDriver") as RouteDriver).player_progress = mine
	_place.text = "%s     %d / %d" % [PLACES[place() - 1], next_ring, rings.size()]
	screen.hud.point_at(rings[next_ring], _flag)


## How far round the player is: the last ring passed, and how near the next one.
func player_progress() -> float:
	if next_ring >= _ring_at.size():
		return _lengths[_lengths.size() - 1]
	return _ring_at[next_ring] - screen.player.global_position.distance_to(rings[next_ring])


## 1 to 4: one more than the racers ahead.
func place() -> int:
	var mine := player_progress()
	var ahead := 1
	for racer in racers:
		var driver: RouteDriver = racer.get_node(^"RouteDriver")
		if driver.finished or driver.progress > mine:
			ahead += 1
	return ahead


## Over the line: the place, the coins, confetti; the racers slow down and drive off.
func _finish() -> void:
	var where := place() if next_ring < rings.size() else _final_place()
	running = false
	var pay: int = PAY[where - 1]
	EventSystem.PRO_coins_found.emit(pay)
	screen.hud.show_banner("%s!   +%d" % [PLACES[where - 1], pay])
	screen.hud.point_at(Vector2.INF, null)
	TownFx.confetti(screen.get_node(^"World"), screen.player.global_position)
	_play(FANFARE, -6.0)
	_plate.visible = false
	finished.emit(route, where)
	route = {}
	_let_traffic_go()
	var leaving := racers.duplicate()
	racers.clear()
	for racer: Car in leaving:
		var tween := racer.create_tween()
		tween.tween_interval(2.0)
		tween.tween_property(racer, "modulate:a", 0.0, 0.8)
		tween.tween_callback(racer.queue_free)


func _final_place() -> int:
	var ahead := 1
	for racer in racers:
		if (racer.get_node(^"RouteDriver") as RouteDriver).finished:
			ahead += 1
	return ahead


## Stop at once (leaving the town mid-race).
func abandon() -> void:
	if not running:
		return
	running = false
	_counting = false
	_let_traffic_go()
	for racer in racers:
		racer.queue_free()
	racers.clear()
	_plate.visible = false
	_count.modulate.a = 0.0
	screen.player.frozen = false


## What the map shows: the next ring, and every route's start line.
func marks() -> Array:
	if running and next_ring < rings.size():
		return [[rings[next_ring], YELLOW]]
	return []


func _play(path: String, volume_db: float) -> void:
	if not SoundManager.audible() or not ResourceLoader.exists(path):
		return
	_voice.stream = load(path)
	_voice.volume_db = volume_db
	_voice.play()


# --- what is drawn: the start lines, the rings ---------------------------------------------

func _draw() -> void:
	for start in starts:
		_draw_start(start)
	if running:
		for i in range(next_ring, rings.size()):
			if i == next_ring:
				var pulse := 1.0 + 0.06 * sin(_time * 6.0)
				draw_arc(rings[i], RING_RADIUS * pulse, 0.0, TAU, 48, Color(YELLOW, 0.95), 18.0, true)
				draw_arc(rings[i], RING_RADIUS * pulse - 16.0, 0.0, TAU, 48, Color(1, 1, 1, 0.6), 6.0, true)
			elif i < next_ring + 3:
				draw_arc(rings[i], RING_RADIUS, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 10.0, true)


## A checkered line across the road, with a flag on a pole either side.
func _draw_start(start: Dictionary) -> void:
	var forward := Vector2.RIGHT.rotated(start["angle"])
	var across := forward.orthogonal()
	var half := TownLayout.ROAD_HALF
	var square := 32.0
	var at: Vector2 = start["at"]
	var n := int(half * 2.0 / square)
	for row in 2:
		for k in n:
			var c := at + across * (-half + (k + 0.5) * square) + forward * ((row - 0.5) * square)
			var white := (k + row) % 2 == 0
			var box := PackedVector2Array()
			for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
				box.append(c + forward * corner.x * square + across * corner.y * square)
			draw_colored_polygon(box, Color(1, 1, 1, 0.9) if white else Color(0.1, 0.1, 0.12, 0.9))
	for side in [-1.0, 1.0]:
		var pole: Vector2 = at + across * side * (half + 40.0)
		draw_circle(pole, 9.0, INK)
		var wave := sin(_time * 5.0 + side) * 6.0
		var flag := PackedVector2Array([pole, pole + Vector2(52, 12 + wave), pole + Vector2(0, 30)])
		draw_colored_polygon(flag, YELLOW if shown.get("at") != at else Color(1, 0.45, 0.2))
		draw_polyline(PackedVector2Array([pole, pole + Vector2(52, 12 + wave), pole + Vector2(0, 30)]), INK, 3.0)


# --- the HUD: the card, the countdown, the place --------------------------------------------

func _build_hud() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "StreetRaceHUD"
	_layer.layer = 2
	add_child(_layer)
	var root := Control.new()
	root.theme = preload("res://ui/theme/vicky_theme.tres")
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(root)
	# The card: the route's little map, its name, and RACE!
	_card = PanelContainer.new()
	_card.name = "StreetCard"
	_card.anchor_top = 0.5
	_card.anchor_bottom = 0.5
	_card.offset_left = 32.0
	_card.offset_top = -170.0
	_card.custom_minimum_size = Vector2(620, 330)
	_card.visible = false
	root.add_child(_card)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	_card.add_child(row)
	_card_map = RouteMap.new()
	_card_map.custom_minimum_size = Vector2(260, 260)
	row.add_child(_card_map)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(words)
	var kind := Label.new()
	kind.text = "STREET RACE"
	kind.add_theme_font_size_override("font_size", 24)
	kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_child(kind)
	_card_name = Label.new()
	_card_name.add_theme_font_size_override("font_size", 32)
	_card_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_name.autowrap_mode = TextServer.AUTOWRAP_WORD
	words.add_child(_card_name)
	_card_go = Label.new()
	_card_go.add_theme_font_size_override("font_size", 44)
	_card_go.add_theme_color_override("font_color", YELLOW)
	_card_go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	words.add_child(_card_go)
	# The countdown, big in the middle.
	_count = Label.new()
	_count.name = "Countdown"
	_count.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_count.offset_left = -300.0
	_count.offset_right = 300.0
	_count.offset_top = -200.0
	_count.offset_bottom = 0.0
	_count.pivot_offset = Vector2(300, 100)
	_count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_count.add_theme_font_size_override("font_size", 160)
	_count.add_theme_color_override("font_color", YELLOW)
	_count.add_theme_color_override("font_outline_color", INK)
	_count.add_theme_constant_override("outline_size", 24)
	_count.modulate.a = 0.0
	root.add_child(_count)
	# The place and the rings, top middle.
	var plate := PanelContainer.new()
	plate.name = "PlacePlate"
	plate.anchor_left = 0.5
	plate.anchor_right = 0.5
	plate.offset_left = -220.0
	plate.offset_right = 220.0
	plate.offset_top = 28.0
	plate.visible = false
	root.add_child(plate)
	var inner := CenterContainer.new()
	plate.add_child(inner)
	_place = Label.new()
	_place.add_theme_font_size_override("font_size", 48)
	_place.add_theme_color_override("font_color", YELLOW)
	inner.add_child(_place)
	_plate = plate


func _show_card(start: Dictionary) -> void:
	if start.is_empty():
		_card.visible = false
		return
	var spec: Dictionary = start["route"]
	_card_name.text = spec["name"]
	_card_go.text = ("Y" if screen.hud.gamepad else "R") + " RACE!"
	_card_map.show_route(screen.town, spec)
	_card.visible = true
	_card.scale = Vector2(0.6, 0.6)
	_card.create_tween().tween_property(_card, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## A little checkered flag for the arrow at the screen's edge.
static func _flag_texture() -> Texture2D:
	var image := Image.create(48, 36, false, Image.FORMAT_RGBA8)
	for y in 36:
		for x in 48:
			var white := (x / 12 + y / 12) % 2 == 0
			image.set_pixel(x, y, Color.WHITE if white else Color(0.1, 0.1, 0.12))
	return ImageTexture.create_from_image(image)


## The card's picture: the town's streets in grey and the route round them in yellow, with the
## start line's flag.
class RouteMap extends Control:
	var _town: Town
	var _cells: Array = []
	var _start := 0.5

	func show_route(town: Town, spec: Dictionary) -> void:
		_town = town
		_cells = spec["cells"]
		_start = spec["start"]
		queue_redraw()

	func _draw() -> void:
		if _town == null:
			return
		var area := _town.streets_rect()
		var fit := minf(size.x / area.size.x, size.y / area.size.y) * 0.92
		var offset := (size - area.size * fit) / 2.0 - area.position * fit
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.36, 0.62, 0.3), true)
		for road: Array in _town.roads:
			draw_line(_town.junctions[road[0]] * fit + offset, _town.junctions[road[1]] * fit + offset,
				Color(0.55, 0.57, 0.6), 7.0)
		var line := PackedVector2Array()
		for cell in _cells:
			line.append(_town.junctions[cell] * fit + offset)
		line.append(line[0])
		draw_polyline(line, YELLOW, 8.0, true)
		var start: Vector2 = line[0].lerp(line[1], _start)
		draw_circle(start, 12.0, Color.WHITE)
		draw_circle(start, 7.0, INK)

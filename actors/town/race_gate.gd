class_name RaceGate
extends Node2D
## A race gate in the open world (docs/DESIGN.md §28): one track's start grid, out on the grass
## round the town (or floating at sea, for a boat course), with the track's three racers
## waiting on it in their paints and an empty, glowing place for the child. An inflatable arch
## stands over the start line, and a sign behind the grid shows the track's shape and name.
##
## The screen does the rest: driving into the glowing place shows the track's card, and Y / R
## starts the race on it. Nearby, now and then one of the racers bounces and toots — "race me!" —
## and all three do when the card comes up. A locked gate keeps its racers (they are waiting for
## the day it opens), but its place and its sign are grey, with a padlock.
##
## The gate's own frame faces +X: the grid's front is to the right, across it is Y.
##
## A car gate also has a big stopwatch on a post behind its sign (§31): pulling up on the glowing
## ring under it shows the track's card with TIME TRIAL, for a time trial with the ghosts.

## The four grid places, front first, two by two and staggered (the race's own order, so the
## player's place is TrackConfig.player_slot).
const SLOTS: Array[Vector2] = [Vector2(110, -85), Vector2(40, 85), Vector2(-100, -85), Vector2(-170, 85)]
## Boats are a little longer: their grid is spread a little more.
const BOAT_SPREAD := 1.25
const START_LINE := 205.0
const ARCH_HALF := 250.0
const PILLAR_RADIUS := 44.0
const SIGN_AT := Vector2(-430, 0)
const SIGN_SIZE := Vector2(300, 230)
## The stopwatch's ring, behind the sign (car gates).
const STOPWATCH_AT := Vector2(-760, 0)
## The child's place glows this big; inside REACH of it counts as on it.
const RING_RADIUS := 105.0
const REACH := 150.0
## A racer toots now and then while the child is this near, but not on the grid.
const HONK_REACH := 1300.0
const HONK_EVERY := Vector2(2.5, 5.0)
const YELLOW := Color(1, 0.824, 0.247)
const GREY := Color(0.62, 0.66, 0.72)
const DARK := Color(0.055, 0.078, 0.11)
const CAR_SCENE := preload("res://actors/car/car.tscn")
const THEME := preload("res://ui/theme/vicky_theme.tres")

var config: TrackConfig
## &"car" or &"boat".
var kind := &"car"
var unlocked := true
## Where the child goes, in world space; set in _ready.
var slot := Vector2.ZERO
## Where the stopwatch's ring is, in world space; Vector2.INF on a boat gate.
var stopwatch := Vector2.INF
## The player's vehicle, for the toots (the screen keeps it current).
var watch: Node2D
var racers: Array[Car] = []

var _theme_colour := Color(0.36, 0.73, 0.29)
var _line := PackedVector2Array()
var _ring: Line2D
var _honk_in := 2.0
var _horn: AudioStreamPlayer2D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = hash(config.track_id)
	_read_track()
	var spread := BOAT_SPREAD if kind == &"boat" else 1.0
	slot = to_global(_slot(config.player_slot - 1, spread))
	_add_racers(spread)
	_add_ring(spread)
	_add_arch()
	_add_sign()
	if kind == &"car":
		stopwatch = to_global(STOPWATCH_AT)
		var watch_sign := StopwatchSign.new()
		watch_sign.name = "Stopwatch"
		watch_sign.position = STOPWATCH_AT
		watch_sign.gate = self
		add_child(watch_sign)
	_horn = AudioStreamPlayer2D.new()
	_horn.name = "Horn"
	_horn.bus = &"SFX"
	_horn.max_distance = 2400.0
	add_child(_horn)
	queue_redraw()


## Unlocked since the gate was built (a race was finished): its place and sign light up.
func set_unlocked(value: bool) -> void:
	if value == unlocked:
		return
	unlocked = value
	for child in [_ring, get_node_or_null(^"Sign")]:
		if child:
			child.queue_free()
	_add_ring(BOAT_SPREAD if kind == &"boat" else 1.0)
	_add_sign()
	queue_redraw()


func _slot(index: int, spread: float) -> Vector2:
	return SLOTS[clampi(index, 0, SLOTS.size() - 1)] * Vector2(spread, 1.0)


## Is `pos` on the child's place?
func is_on_slot(pos: Vector2) -> bool:
	return pos.distance_to(slot) < REACH


## Is `pos` on the stopwatch's ring (a car gate)?
func is_on_stopwatch(pos: Vector2) -> bool:
	return stopwatch != Vector2.INF and pos.distance_to(stopwatch) < REACH


## Where a vehicle stands on the child's place, facing the start line.
func slot_angle() -> float:
	return global_rotation


## All three bounce and toot: the child has pulled up.
func cheer() -> void:
	for i in racers.size():
		get_tree().create_timer(0.12 * i, false).timeout.connect(_toot.bind(racers[i]))


func _physics_process(delta: float) -> void:
	if not is_instance_valid(watch) or racers.is_empty():
		return
	var distance := watch.global_position.distance_to(slot)
	if distance > HONK_REACH or distance < REACH:
		return
	_honk_in -= delta
	if _honk_in <= 0.0:
		_honk_in = _rng.randf_range(HONK_EVERY.x, HONK_EVERY.y)
		_toot(racers[_rng.randi() % racers.size()])


## One racer bounces on its wheels (or its hull), and toots its own horn.
func _toot(racer: Car) -> void:
	if not is_instance_valid(racer):
		return
	var body: Node2D = racer.get_node(^"Body")
	var tween := body.create_tween()
	tween.tween_property(body, "scale", Vector2.ONE * 1.14, 0.09)
	tween.tween_property(body, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if SoundManager.audible() and racer.setup and racer.setup.horn:
		_horn.global_position = racer.global_position
		_horn.stream = racer.setup.horn
		_horn.pitch_scale = _rng.randf_range(0.95, 1.08)
		_horn.play()


## The track's three racers on the grid, in their paints, held still and quiet.
func _add_racers(spread: float) -> void:
	var scene: PackedScene = config.vehicle_scene if config.vehicle_scene else CAR_SCENE
	var places: Array[int] = []
	for i in SLOTS.size():
		if i != config.player_slot - 1:
			places.append(i)
	for i in mini(config.opponent_setups.size(), places.size()):
		var setup: DriftSetup = config.opponent_setups[i]
		var racer: Car = scene.instantiate()
		racer.name = "Racer%d" % (i + 1)
		racer.setup = setup
		var paint: StringName = config.opponent_paints[i] if i < config.opponent_paints.size() else Paint.ORIGINAL
		racer.body_texture = Paint.body(setup, paint)
		racer.driver_id = DriverLook.OPPONENTS[i % DriverLook.OPPONENTS.size()]
		racer.position = _slot(places[i], spread)
		racer.frozen = true
		var audio := racer.get_node("Audio")  # quiet: the gate toots for them
		racer.remove_child(audio)
		audio.free()
		add_child(racer)
		racer.reset_physics_interpolation()
		racers.append(racer)


## The child's place: a glowing ring that breathes, yellow (grey while locked), with a
## padlock in it while the gate is locked.
func _add_ring(spread: float) -> void:
	_ring = Line2D.new()
	_ring.name = "Ring"
	for k in 41:
		_ring.add_point(_slot(config.player_slot - 1, spread) + Vector2.from_angle(TAU * k / 40.0) * RING_RADIUS)
	_ring.width = 14.0
	_ring.default_color = YELLOW if unlocked else GREY
	_ring.begin_cap_mode = Line2D.LINE_CAP_ROUND
	add_child(_ring)
	var breathe := _ring.create_tween().set_loops().set_trans(Tween.TRANS_SINE)
	breathe.tween_property(_ring, "modulate:a", 0.35, 0.8)
	breathe.tween_property(_ring, "modulate:a", 1.0, 0.8)
	if not unlocked:
		var lock := Padlock.new()
		lock.position = _slot(config.player_slot - 1, spread)
		lock.rotation = -rotation
		_ring.add_child(lock)


## The inflatable arch over the start line: a chequered banner between two fat pillars in the
## track's colour (buoys at sea). Drawn above the cars, as an arch is.
func _add_arch() -> void:
	var arch := Arch.new()
	arch.name = "Arch"
	arch.colour = _theme_colour if kind == &"car" else Color(1.0, 0.45, 0.15)
	arch.position = Vector2(START_LINE + 22.0, 0)
	arch.z_index = 3
	add_child(arch)


## The sign behind the grid, upright whichever way the gate faces: the track's shape in its
## colour, and its name.
func _add_sign() -> void:
	var board := Node2D.new()
	board.name = "Sign"
	board.position = SIGN_AT * (Vector2(BOAT_SPREAD, 1.0) if kind == &"boat" else Vector2.ONE)
	board.rotation = -rotation
	board.z_index = 3
	add_child(board)
	var drawing := TrackSign.new()
	drawing.line = _line
	drawing.colour = _theme_colour if unlocked else GREY
	drawing.water = kind == &"boat"
	drawing.locked = not unlocked
	board.add_child(drawing)
	var label := Label.new()
	label.text = config.display_name.to_upper()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(SIGN_SIZE.x + 120.0, 50)
	label.position = Vector2(-label.size.x / 2.0, SIGN_SIZE.y / 2.0 + 12.0)
	label.theme = THEME
	label.add_theme_font_size_override("font_size", 34)
	label.add_theme_color_override("font_color", Color.WHITE if unlocked else Color(0.85, 0.88, 0.92))
	label.add_theme_color_override("font_outline_color", DARK)
	label.add_theme_constant_override("outline_size", 10)
	board.add_child(label)


## The grid on the ground: a box for each place and the chequered start line.
func _draw() -> void:
	if kind == &"boat":
		return  # at sea the ring, the buoys and the boats are the grid
	var white := Color(1, 1, 1, 0.85)
	for i in SLOTS.size():
		var at := _slot(i, 1.0)
		# An open box behind each place: the line across in front of the car, and its sides.
		var front := at.x + 76.0
		draw_line(Vector2(front, at.y - 62.0), Vector2(front, at.y + 62.0), white, 8.0)
		draw_line(Vector2(front, at.y - 62.0), Vector2(front - 60.0, at.y - 62.0), white, 8.0)
		draw_line(Vector2(front, at.y + 62.0), Vector2(front - 60.0, at.y + 62.0), white, 8.0)
	var square := 22.0
	var across := -ARCH_HALF + 30.0
	var row := 0
	while across < ARCH_HALF - 30.0:
		for k in 2:
			var black := (row + k) % 2 == 0
			draw_rect(Rect2(START_LINE - square + k * square, across, square, square), DARK if black else Color.WHITE)
		across += square
		row += 1


## The track's racing line and theme colour, read from its scene without adding it to the tree
## (as PICK A RACE's cards do), fitted later into the sign.
func _read_track() -> void:
	var track: Track = config.track_scene.instantiate()
	if track.theme:
		_theme_colour = track.theme.card_colour
	var path := track.get_node_or_null(^"RacingLine") as Path2D
	if path and path.curve:
		_line = path.curve.get_baked_points()
	track.free()


## The arch, seen from above: two pillars and the banner between them.
class Arch extends Node2D:
	var colour := Color(0.36, 0.73, 0.29)

	func _draw() -> void:
		var half := RaceGate.ARCH_HALF
		var shade := colour.darkened(0.3)
		draw_rect(Rect2(-18, -half + 10.0, 36, half * 2.0 - 20.0), shade)
		var square := 18.0
		var y := -half + 18.0
		var row := 0
		while y < half - 18.0:
			for k in 2:
				var black := (row + k) % 2 == 0
				draw_rect(Rect2(-18.0 + k * square, y, square, square), RaceGate.DARK if black else Color.WHITE)
			y += square
			row += 1
		for side in [-1.0, 1.0]:
			var at := Vector2(0, side * half)
			draw_circle(at + Vector2(6, 8), RaceGate.PILLAR_RADIUS, Color(0, 0, 0, 0.25))
			draw_circle(at, RaceGate.PILLAR_RADIUS, shade)
			draw_circle(at - Vector2(4, 4), RaceGate.PILLAR_RADIUS - 8.0, colour)
			draw_circle(at - Vector2(14, 14), 10.0, colour.lightened(0.45))


## The sign's board (its name hangs under it): a dark panel on two posts, the track's shape in its colour (blue water
## with a white lip for a boat course), and a padlock over it while locked.
class TrackSign extends Node2D:
	var line := PackedVector2Array()
	var colour := Color(0.36, 0.73, 0.29)
	var water := false
	var locked := false

	func _draw() -> void:
		var size := RaceGate.SIGN_SIZE
		var box := Rect2(-size / 2.0, size)
		for x in [-size.x * 0.3, size.x * 0.3]:
			draw_rect(Rect2(x - 8.0, size.y / 2.0 - 10.0, 16, 40), Color(0.45, 0.32, 0.2))
		draw_rect(box.grow(10.0), Color.WHITE)
		draw_rect(box, RaceGate.DARK)
		if line.size() < 2:
			return
		var inner := Rect2(box.position + Vector2(26, 22), Vector2(size.x - 52, size.y - 44))
		var bounds := Rect2(line[0], Vector2.ZERO)
		for p in line:
			bounds = bounds.expand(p)
		var fit := minf(inner.size.x / bounds.size.x, inner.size.y / bounds.size.y)
		var offset := inner.get_center() - bounds.get_center() * fit
		var shape := PackedVector2Array()
		for i in range(0, line.size(), 3):
			shape.append(line[i] * fit + offset)
		shape.append(shape[0])
		draw_polyline(shape, Color.WHITE, 16.0, true)
		draw_polyline(shape, Color(0.3, 0.62, 0.9) if water and not locked else colour, 9.0, true)
		if locked:
			draw_set_transform(inner.get_center(), 0.0, Vector2.ONE * 0.8)
			Padlock.draw_on(self)
			draw_set_transform(Vector2.ZERO)


## A padlock: a grey hoop over a gold body with a keyhole.
## The time trial's stopwatch: a glowing ring on the grass and a big stopwatch on a post beside
## it, its hand going round. Grey with a padlock while the gate is locked.
class StopwatchSign extends Node2D:
	var gate: RaceGate
	var _time := 0.0

	func _process(delta: float) -> void:
		_time += delta
		queue_redraw()

	func _draw() -> void:
		var lit := gate.unlocked
		var ring_colour := YELLOW if lit else GREY
		var pulse := 1.0 + (0.05 * sin(_time * 4.0) if lit else 0.0)
		draw_circle(Vector2.ZERO, RING_RADIUS * pulse, Color(ring_colour, 0.22))
		draw_arc(Vector2.ZERO, RING_RADIUS * pulse, 0.0, TAU, 40, ring_colour, 10.0, true)
		# The stopwatch stands upright on screen, whichever way the gate faces.
		draw_set_transform(Vector2.ZERO, -gate.global_rotation)
		var face := Vector2(0, -RING_RADIUS - 90.0)
		draw_line(face + Vector2(0, 60), face + Vector2(0, 120), DARK, 10.0)
		draw_rect(Rect2(face + Vector2(-14, -84), Vector2(28, 22)), DARK)
		draw_circle(face, 66.0, DARK)
		draw_circle(face, 58.0, Color.WHITE if lit else Color(0.85, 0.87, 0.9))
		for k in 12:
			var a := TAU * k / 12.0
			draw_line(face + Vector2.from_angle(a) * 46.0, face + Vector2.from_angle(a) * 54.0, DARK, 4.0)
		var hand := -PI / 2.0 + (_time * 2.0 if lit else 0.6)
		draw_line(face, face + Vector2.from_angle(hand) * 44.0, Color(0.9, 0.22, 0.27), 6.0, true)
		draw_circle(face, 7.0, DARK)
		if not lit:
			draw_set_transform(face + Vector2(34, 34), -gate.global_rotation, Vector2.ONE * 0.5)
			Padlock.draw_on(self)
		draw_set_transform(Vector2.ZERO)


class Padlock extends Node2D:
	func _draw() -> void:
		Padlock.draw_on(self)

	static func draw_on(canvas: CanvasItem) -> void:
		canvas.draw_arc(Vector2(0, -22), 30.0, PI, TAU, 16, Color(0.7, 0.73, 0.78), 14.0)
		canvas.draw_line(Vector2(-30, -22), Vector2(-30, 0), Color(0.7, 0.73, 0.78), 14.0)
		canvas.draw_line(Vector2(30, -22), Vector2(30, 0), Color(0.7, 0.73, 0.78), 14.0)
		canvas.draw_rect(Rect2(-46, -6, 92, 70), RaceGate.DARK)
		canvas.draw_rect(Rect2(-40, 0, 80, 58), Color(1.0, 0.75, 0.2))
		canvas.draw_circle(Vector2(0, 22), 9.0, RaceGate.DARK)
		canvas.draw_rect(Rect2(-4, 24, 8, 18), RaceGate.DARK)

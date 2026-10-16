class_name GoldenStars
extends Node2D
## Golden stars hidden round the island (docs/DESIGN.md §32), the open-world plan's idea 29: a
## collect-a-thon that rewards looking everywhere. COUNT big shiny stars: one on most lawns,
## out on the beach, at the end of the pier, high over every jump ramp's landing (only a good
## jump reaches it), and out at sea by the lighthouse, the wreck and the ramp islets (by boat).
## Each one found stays found (the save keeps them), pays PAY coins and says how many so far;
## finding them all pays ALL_PAY. The pause map shows the count. Where they are is worked out
## from the town itself with a fixed seed, so it is the same island every time.

const COUNT := 55
## The first ISLAND_COUNT are round the town's island; the rest on the snowy hill (§33), added
## after them so the island's keep their numbers in old saves.
const ISLAND_COUNT := 50
const PAY := 3
const ALL_PAY := 50
const SEED := 2031
## Picking one up: this near the player (a boat is bigger and harder to steer, so more).
const REACH := 90.0
const BOAT_REACH := 150.0
## Stars stand at least this far apart, and this far clear of buildings and trees.
const GAP := 900.0
const CLEAR := 70.0
const SIZE := 46.0
const GOLD := Color(1.0, 0.8, 0.18)
const GOLD_EDGE := Color(0.72, 0.45, 0.05)
const CHIME := "res://art/sfx/sticker.wav"

## The town screen (TownScreen): the player, the HUD, paying.
var screen: Node
var spots: Array[Vector2] = []
## Indexes of the stars found, in any drive.
var found := {}
var _stars: Array[Node2D] = []
var _time := 0.0
var _voice: AudioStreamPlayer


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_state_changed)


func _ready() -> void:
	spots = plan(screen.town)
	for i in spots.size():
		var star := Star.new()
		star.position = spots[i]
		star.z_index = 4
		star.visible = not found.has(i)
		_stars.append(star)
		add_child(star)
	_voice = AudioStreamPlayer.new()
	_voice.bus = &"SFX"
	add_child(_voice)
	EventSystem.PRO_state_requested.emit()


func _on_state_changed(state: Dictionary) -> void:
	for i: int in state.get("golden_stars", []):
		found[i] = true
		if i < _stars.size():
			_stars[i].visible = false


func _physics_process(delta: float) -> void:
	_time += delta
	var player: Car = screen.player
	if player == null:
		return
	var reach := BOAT_REACH if player is Boat else REACH
	for i in _stars.size():
		var star := _stars[i]
		star.time = _time + i * 0.7
		if star.visible and not found.has(i) and player.global_position.distance_to(star.position) < reach:
			_find(i)


func _find(i: int) -> void:
	found[i] = true
	var star := _stars[i]
	EventSystem.PRO_golden_star_found.emit(i)
	screen.pay(PAY, star.position)
	if found.size() == spots.size():
		EventSystem.PRO_coins_found.emit(ALL_PAY)
		screen.hud.show_banner("ALL %d GOLDEN STARS!  +%d" % [spots.size(), ALL_PAY])
		TownFx.confetti(screen.get_node(^"World"), star.position)
	else:
		screen.hud.show_banner("GOLDEN STAR  %d / %d" % [found.size(), spots.size()])
	screen.job(&"star")
	var tween := star.create_tween()
	tween.tween_property(star, "scale", Vector2(2.2, 2.2), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(star, "position:y", star.position.y - 80.0, 0.35)
	tween.tween_property(star, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func() -> void:
		star.visible = false
		star.modulate.a = 1.0
		star.scale = Vector2.ONE
		star.position = spots[i])
	if SoundManager.audible() and ResourceLoader.exists(CHIME):
		_voice.stream = load(CHIME)
		_voice.volume_db = -4.0
		_voice.play()


## Where the stars are: picked from the town's own lawns, beach, ramps and sea, with a fixed
## seed, so the same COUNT spots every time.
static func plan(town: Town) -> Array[Vector2]:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var out: Array[Vector2] = []
	# Specials first: the end of the pier, over each jump ramp's landing (beyond the coins),
	# and out at sea.
	out.append(Vector2(Island.PIER.get_center().x, Island.PIER.end.y - 60.0))
	for ramp: Dictionary in town.ramps:
		out.append(ramp["at"] + ramp["throw"] * 660.0)
	for islet: Array in Island.RAMP_ISLETS:
		out.append(islet[0] + islet[1] * 900.0)
	out.append(Island.LIGHTHOUSE + Vector2(-Island.LIGHTHOUSE_RADIUS - 220.0, Island.LIGHTHOUSE_RADIUS))
	out.append(Island.WRECK + Vector2(420.0, 160.0))
	out.append(Island.DOLPHIN_HOME)
	out.append(Vector2(Island.SLALOM_X + Island.SLALOM_GAP * (Island.SLALOM_BUOYS - 1) * 0.5, Island.SLALOM_Y))
	# One on (nearly) every lawn, tucked round the side of the buildings.
	var lawns := town.lawns.duplicate()
	for lawn: Rect2 in lawns:
		for attempt in 60:
			var inner := lawn.grow(-60.0)
			var spot := Vector2(rng.randf_range(inner.position.x, inner.end.x), rng.randf_range(inner.position.y, inner.end.y))
			if _clear(town, spot, out, GAP * 0.6):
				out.append(spot)
				break
	# The rest on the beach and the grass round the town, spread out.
	var world := town.world_rect()
	var tries := 0
	while out.size() < ISLAND_COUNT and tries < 20000:
		tries += 1
		var spot := Vector2(rng.randf_range(world.position.x, world.end.x), rng.randf_range(world.position.y, world.end.y))
		if town.streets_rect().grow(-100.0).has_point(spot):
			continue
		if town.surface_at(spot) not in [&"beach", &"grass"] or not _clear(town, spot, out, GAP):
			continue
		out.append(spot)
	out.resize(mini(out.size(), ISLAND_COUNT))
	# The snowy hill: just below the flag on top, out on the frozen lake, at the foot of the
	# sledging run, on the far east shore, and halfway over the bridge. Nudged round a little
	# if a pine or a snowman stands there.
	var sled := (SnowIsland.SLED_TO - SnowIsland.SLED_FROM).normalized()
	for spot: Vector2 in [SnowIsland.HILL + Vector2(0, 240), SnowIsland.LAKE, SnowIsland.SLED_TO + sled * 160.0,
			SnowIsland.CENTRE + Vector2(SnowIsland.RADII.x - 450.0, 0),
			Vector2((Island.world().end.x + SnowIsland.shore_x()) / 2.0, SnowIsland.BRIDGE_Y)]:
		for k in 9:
			var at := spot + (Vector2.from_angle(k * TAU / 8.0) * 140.0 if k > 0 else Vector2.ZERO)
			if _clear(town, at, out, 300.0):
				out.append(at)
				break
	return out


static func _clear(town: Town, spot: Vector2, taken: Array[Vector2], gap: float) -> bool:
	for other in taken:
		if other.distance_to(spot) < gap:
			return false
	for rect in town.solid_boxes:
		if rect.grow(CLEAR).has_point(spot):
			return false
	for circle in town.solid_circles:
		if spot.distance_to(Vector2(circle.x, circle.y)) < circle.z + CLEAR:
			return false
	for tree in town.tree_spots:
		if tree.distance_to(spot) < CLEAR + 40.0:
			return false
	for pond in town.ponds:
		if spot.distance_to(Vector2(pond.x, pond.y)) < pond.z + CLEAR:
			return false
	for gate in town.gates:
		if gate["area"].grow(CLEAR).has_point(spot):
			return false
	for rect in town.playgrounds:
		if rect.grow(CLEAR).has_point(spot):
			return false
	if spot.distance_to(town.fountain_at) < 650.0:  # the fountain, and the jobs board below it
		return false
	return not town.rocket_pad.grow(CLEAR).has_point(spot) and not town.pitch.grow(CLEAR).has_point(spot)


## One star: gold with a darker rim, bobbing and turning a little, with a soft glow under it.
class Star extends Node2D:
	var time := 0.0

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var bob := sin(time * 2.4) * 6.0
		var glow := 0.25 + 0.12 * sin(time * 3.1)
		draw_circle(Vector2(0, 14), SIZE * 0.9, Color(1, 0.9, 0.4, glow))
		var spin := sin(time * 1.7) * 0.18
		_star(Vector2(0, bob), SIZE + 6.0, spin, GOLD_EDGE)
		_star(Vector2(0, bob), SIZE, spin, GOLD)
		_star(Vector2(-8, bob - 8), SIZE * 0.35, spin, Color(1, 1, 0.85, 0.85))

	func _star(at: Vector2, radius: float, turn: float, colour: Color) -> void:
		var points := PackedVector2Array()
		for k in 10:
			var reach := radius if k % 2 == 0 else radius * 0.48
			points.append(at + Vector2.from_angle(-PI / 2.0 + turn + k * PI / 5.0) * reach)
		draw_colored_polygon(points, colour)

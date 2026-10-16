class_name GoldenStars
extends Node2D
## Golden stars hidden round the island (docs/DESIGN.md §32), the open-world plan's idea 29: a
## collect-a-thon that rewards looking everywhere. COUNT big shiny stars: one on most lawns,
## out on the beach, at the end of the pier, high over every jump ramp's landing (only a good
## jump reaches it), and out at sea by the lighthouse, the wreck and the ramp islets (by boat).
## Each one found stays found (the save keeps them), pays PAY coins and says how many so far;
## finding them all pays ALL_PAY. The pause map shows the count. Where they are is worked out
## from the town itself with a fixed seed, so it is the same island every time.

const COUNT := 80
## The first ISLAND_COUNT are round the town's island; then five each on the snowy hill (§33), in
## candy land (§34), in the jungle (§35), in toy town (§36), on Sunny Beach (§37) and along the
## ring road (§38), each five added after the last so the earlier ones keep their numbers in old
## saves.
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
## Where the Candy Lane, Jungle Run, Toy Town and Sunny Beach gates' paving was before they moved
## to candy land (§34), the jungle (§35), toy town (§36) and Sunny Beach (§37): still kept clear,
## so the island's stars stay where they were and keep their numbers in old saves.
const OLD_GATE_AREAS: Array[Rect2] = [Rect2(2050.0, 7695.0, 700.0, 470.0), Rect2(7150.0, 7695.0, 700.0, 470.0),
	Rect2(9295.0, 5650.0, 470.0, 700.0), Rect2(6950.0, 165.0, 700.0, 470.0)]

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
	# Candy land: in the middle of the chocolate lake, just past a jelly pad (a bounce carries a
	# car over it), on the far east shore, by the candy canes, and halfway over the bridge.
	var jelly: float = CandyIsland.JELLY_ANGLES[1]
	for spot: Vector2 in [CandyIsland.LAKE, CandyIsland.lane_at(jelly) + CandyIsland.lane_along(jelly) * 260.0,
			CandyIsland.CENTRE + Vector2(CandyIsland.RADII.x - 420.0, 0),
			Vector2(CandyIsland.CENTRE.x - CandyIsland.LANE_RADII.x - 450.0, CandyIsland.BRIDGE_Y),
			Vector2((Island.world().end.x + CandyIsland.shore_x()) / 2.0, CandyIsland.BRIDGE_Y)]:
		for k in 9:
			var at := spot + (Vector2.from_angle(k * TAU / 8.0) * 140.0 if k > 0 else Vector2.ZERO)
			if _clear(town, at, out, 300.0):
				out.append(at)
				break
	# The jungle: on the temple's courtyard (pillars aside), at the far end of a mud pool, deep in
	# the trees on the west, on the beach in the north-east, and halfway over the bridge.
	var mud: float = JungleIsland.MUD_ANGLES[2]
	for spot: Vector2 in [JungleIsland.courtyard().get_center() + Vector2(0, -110),
			JungleIsland.trail_at(mud) + JungleIsland.trail_along(mud) * (JungleIsland.MUD_RADII.x + 120.0),
			JungleIsland.CENTRE + Vector2(-JungleIsland.RADII.x * 0.78, 0),
			JungleIsland.CENTRE + Vector2(JungleIsland.RADII.x, -JungleIsland.RADII.y) * 0.66,
			Vector2(JungleIsland.BRIDGE_X, (JungleIsland.shore_y() + Island.world().position.y) / 2.0)]:
		for k in 9:
			var at := spot + (Vector2.from_angle(k * TAU / 8.0) * 140.0 if k > 0 else Vector2.ZERO)
			if _clear(town, at, out, 300.0):
				out.append(at)
				break
	# Toy town: in the middle of the train's track, on the far south of the mat, out on its
	# east and west sides, and halfway over the bridge.
	var mid := ToyIsland.CENTRE
	for spot: Vector2 in [mid + Vector2(-500, -350), mid + Vector2(0, ToyIsland.RADII.y - 420.0),
			mid + Vector2(ToyIsland.RADII.x - 520.0, -200), mid + Vector2(-ToyIsland.RADII.x + 520.0, 300),
			Vector2(ToyIsland.BRIDGE_X, (ToyIsland.shore_y() + Island.world().end.y) / 2.0)]:
		for k in 9:
			var at := spot + (Vector2.from_angle(k * TAU / 8.0) * 140.0 if k > 0 else Vector2.ZERO)
			if _clear(town, at, out, 300.0):
				out.append(at)
				break
	# Sunny Beach: up the beach from the surf, by the lifeguard's tower, on the north and south
	# sand, inside the boardwalk, and halfway over the bridge.
	var beach := BeachIsland.CENTRE
	for spot: Vector2 in [BeachIsland.shore_point(PI - 0.3, -BeachIsland.SURF_DEPTH - 150.0),
			beach + Vector2(-600, -450), beach + Vector2(500, BeachIsland.RADII.y - 330.0),
			beach + Vector2(-300, -BeachIsland.RADII.y + 330.0),
			Vector2((Island.world().position.x + BeachIsland.shore_x()) / 2.0, BeachIsland.BRIDGE_Y)]:
		for k in 9:
			var at := spot + (Vector2.from_angle(k * TAU / 8.0) * 140.0 if k > 0 else Vector2.ZERO)
			if _clear(town, at, out, 300.0):
				out.append(at)
				break
	# The ring road: hidden in the tunnel, on the stream's bridge, where the stream meets the sea,
	# on the road past the fuel station and in front of the speed sign.
	for spot: Vector2 in [RingRoad.TUNNEL.get_center(), RingRoad.STREAM_BRIDGE.get_center(), Vector2(150.0, 7150.0),
			Vector2(RingRoad.FUEL_YARD.end.x + 400.0, TownLayout.junction(Vector2i.ZERO).y),
			Vector2(RingRoad.SPEED_SIGN.x, TownLayout.junction(Vector2i(0, TownLayout.ROWS)).y)]:
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
	for castle in town.castles:  # Sunny Beach's sandcastles (§37)
		if castle.position.distance_to(spot) < SandCastle.RADIUS + CLEAR:
			return false
	for pond in town.ponds:
		if spot.distance_to(Vector2(pond.x, pond.y)) < pond.z + CLEAR:
			return false
	for gate in town.gates:
		if gate["area"].grow(CLEAR).has_point(spot):
			return false
	for area in OLD_GATE_AREAS:
		if area.grow(CLEAR).has_point(spot):
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

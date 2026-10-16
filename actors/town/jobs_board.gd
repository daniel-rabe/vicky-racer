class_name JobsBoard
extends Node2D
## The jobs board (docs/DESIGN.md §32), the open-world plan's idea 31. A wooden board in the
## park shows today's three little jobs, in pictures only: deliver a parcel, bring the puppy
## home, put out fires, take animals on the bus, wash the car, pick up coins, pet the animals,
## jump a ramp, find a golden star. The same three show on the HUD under the coins, with a dot
## for each time still to go and a tick when done. Each job done pays JOB_PAY; all three pay
## ALL_PAY on top and the board cheers. A new day (the PC's date) brings three new jobs, and
## the save remembers how far today's have got. Nothing runs out and nothing can be failed.

## kind -> [picture (null: a golden star, drawn), how many times].
const JOBS := {
	&"delivery": ["res://art/town/treats/pizza.png", 1],
	&"puppy": ["res://art/town/animals/dog.png", 1],
	&"fire": ["res://art/town/vehicles/fire_engine.png", 2],
	&"bus": ["res://art/town/vehicles/bus.png", 3],
	&"wash": ["res://art/town/buildings/car_wash.png", 1],
	&"coins": ["res://art/ui/coin.png", 10],
	&"pet": ["res://art/town/animals/cat.png", 2],
	&"jump": ["res://art/props/water/ramp.png", 2],
	&"star": [null, 1],
}
const PER_DAY := 3
## A job needing more than this many shows a number to go, not dots.
const MAX_DOTS := 4
const JOB_PAY := 5
const ALL_PAY := 20
## Driving or walking this near the board makes it wave.
const NEAR := 360.0
const BOARD := Vector2(330, 190)
const WOOD := Color(0.62, 0.4, 0.22)
const WOOD_DARK := Color(0.42, 0.26, 0.13)
const PAPER := Color(0.98, 0.96, 0.88)
const TICK := Color(0.2, 0.75, 0.32)
const CHIME := "res://art/sfx/sparkle.wav"
const CHEER := "res://art/sfx/cheer.wav"

## The town screen (TownScreen): the player, the HUD, paying.
var screen: Node
## Today, as the PC's date ("2026-10-15"), and today's jobs: [{kind, picture, need, have}].
var day := ""
var today: Array[Dictionary] = []
var _time := 0.0
var _wave := 0.0
var _was_near := false
var _voice: AudioStreamPlayer


func _ready() -> void:
	_voice = AudioStreamPlayer.new()
	_voice.bus = &"SFX"
	add_child(_voice)
	z_index = 2


## Set up `for_day`'s jobs, carrying on from `saved` ({"day", "progress"}) when it is the same
## day. `forced` (kinds) picks them instead, for the dev flag and the tests.
func begin(for_day: String, saved: Dictionary, forced: Array = []) -> void:
	day = for_day
	var kinds: Array = forced.filter(func(k: StringName) -> bool: return JOBS.has(k)).slice(0, PER_DAY)
	if kinds.is_empty():
		kinds = pick(for_day)
	var progress: Dictionary = saved.get("progress", {}) if saved.get("day", "") == for_day else {}
	today.clear()
	for kind: StringName in kinds:
		var path: Variant = JOBS[kind][0]
		today.append({"kind": kind, "picture": load(path) if path != null else null, "need": JOBS[kind][1],
			"have": mini(int(progress.get(String(kind), 0)), JOBS[kind][1])})
	_show()


## The day's three jobs, the same all day: picked with the date as the seed.
static func pick(for_day: String) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(for_day)
	var kinds: Array = JOBS.keys()
	kinds.sort()
	var out: Array = []
	while out.size() < PER_DAY:
		var kind: StringName = kinds[rng.randi() % kinds.size()]
		if kind not in out:
			out.append(kind)
	return out


## No jobs at all (the tests that count coins exactly, whatever the date).
func clear() -> void:
	today.clear()
	_show()


func all_done() -> bool:
	return today.all(func(job: Dictionary) -> bool: return job["have"] >= job["need"])


## Something on the list happened `count` times.
func progress(kind: StringName, count := 1) -> void:
	for job in today:
		if job["kind"] != kind or job["have"] >= job["need"]:
			continue
		job["have"] = mini(job["have"] + count, job["need"])
		if job["have"] >= job["need"]:
			screen.pay(JOB_PAY, screen.player.global_position if screen.player else position)
			if all_done():
				EventSystem.PRO_coins_found.emit(ALL_PAY)
				screen.hud.show_banner("ALL JOBS DONE!  +%d" % ALL_PAY)
				TownFx.confetti(get_parent(), position)
				if screen.player:
					TownFx.confetti(get_parent(), screen.player.global_position)
				_play(CHEER if ResourceLoader.exists(CHEER) else CHIME, -4.0)
			else:
				screen.hud.show_banner("JOB DONE!  +%d" % JOB_PAY)
				_play(CHIME, -6.0)
			_wave = 1.0
		var saved := {}
		for j in today:
			saved[String(j["kind"])] = j["have"]
		EventSystem.PRO_jobs_saved.emit({"day": day, "progress": saved})
		_show()


func _show() -> void:
	queue_redraw()
	if screen and screen.hud:
		screen.hud.show_jobs(today)


func _process(delta: float) -> void:
	_time += delta
	_wave = maxf(_wave - delta * 0.8, 0.0)
	var player: Car = screen.player if screen else null
	var near := player != null and player.global_position.distance_to(position) < NEAR
	if near and not _was_near:
		_wave = 1.0
		screen.hud.show_jobs(today, true)
	_was_near = near
	queue_redraw()


func _play(path: String, volume_db: float) -> void:
	if not SoundManager.audible() or not ResourceLoader.exists(path):
		return
	_voice.stream = load(path)
	_voice.volume_db = volume_db
	_voice.play()


## The board: two posts, a wooden frame, and a paper card per job with its picture, ticked
## when done. It wobbles when someone comes by or a job is done.
func _draw() -> void:
	var tilt := sin(_time * 9.0) * 0.05 * _wave
	draw_set_transform(Vector2(0, BOARD.y * 0.5), tilt, Vector2.ONE)
	var top := Vector2(-BOARD.x / 2.0, -BOARD.y * 1.5)
	for x in [-BOARD.x * 0.32, BOARD.x * 0.32]:
		draw_rect(Rect2(x - 10.0, -BOARD.y * 0.7, 20.0, BOARD.y * 0.7), WOOD_DARK)
	draw_rect(Rect2(top - Vector2(10, 10), BOARD + Vector2(20, 20)), WOOD_DARK)
	draw_rect(Rect2(top, BOARD), WOOD)
	var card := Vector2((BOARD.x - 40.0) / PER_DAY, BOARD.y - 30.0)
	for i in today.size():
		var job: Dictionary = today[i]
		var at := top + Vector2(10.0 + i * (card.x + 10.0), 15.0)
		draw_rect(Rect2(at, card), PAPER)
		draw_circle(at + Vector2(card.x / 2.0, 8.0), 6.0, Color(0.85, 0.2, 0.2))  # the pin
		var inner := Rect2(at + Vector2(10, 22), card - Vector2(20, 44))
		JobIcon.draw_picture(self, job["picture"], inner)
		if job["have"] >= job["need"]:
			JobIcon.draw_tick(self, at + card * Vector2(0.72, 0.72), 26.0)
		else:
			JobIcon.draw_dots(self, Vector2(at.x + card.x / 2.0, at.y + card.y - 12.0), job["need"], job["have"], 6.0)
	draw_set_transform(Vector2.ZERO)


## A job's picture with its dots or tick, for the HUD as well as the board.
class JobIcon extends Control:
	var job: Dictionary

	func _draw() -> void:
		var box := Rect2(Vector2.ZERO, size - Vector2(0, 14))
		var done: bool = job["have"] >= job["need"]
		draw_picture(self, job["picture"], box, 0.55 if done else 1.0)
		if done:
			draw_tick(self, size * Vector2(0.7, 0.62), 20.0)
		else:
			draw_dots(self, Vector2(size.x / 2.0, size.y - 6.0), job["need"], job["have"], 4.5)

	static func draw_picture(on: CanvasItem, picture: Texture2D, box: Rect2, alpha := 1.0) -> void:
		if picture == null:  # a golden star
			var points := PackedVector2Array()
			var radius := minf(box.size.x, box.size.y) * 0.5
			for k in 10:
				points.append(box.get_center() + Vector2.from_angle(-PI / 2.0 + k * PI / 5.0) * (radius if k % 2 == 0 else radius * 0.48))
			on.draw_colored_polygon(points, Color(GoldenStars.GOLD, alpha))
			return
		var fit := minf(box.size.x / picture.get_width(), box.size.y / picture.get_height())
		var size := Vector2(picture.get_size()) * fit
		on.draw_texture_rect(picture, Rect2(box.get_center() - size / 2.0, size), false, Color(1, 1, 1, alpha))

	static func draw_tick(on: CanvasItem, at: Vector2, radius: float) -> void:
		on.draw_circle(at, radius, TICK)
		on.draw_polyline(PackedVector2Array([at + Vector2(-0.45, 0.0) * radius, at + Vector2(-0.1, 0.38) * radius,
			at + Vector2(0.5, -0.35) * radius]), Color.WHITE, radius * 0.28)

	## `need` dots in a row, the first `have` of them filled. More than MAX_DOTS (the coins)
	## show as a number in a bubble instead: how many still to go, counting down.
	static func draw_dots(on: CanvasItem, centre: Vector2, need: int, have: int, radius: float) -> void:
		if need <= 1:
			return
		if need > MAX_DOTS:
			var left := str(need - have)
			var font := ThemeDB.fallback_font
			var font_size := int(radius * 4.4)
			on.draw_circle(centre - Vector2(0, radius * 1.2), radius * 3.0, Color(0.3, 0.3, 0.32, 0.85))
			var width := font.get_string_size(left, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			on.draw_string(font, centre + Vector2(-width / 2.0, radius * 0.3), left, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)
			return
		var gap := radius * 2.6
		var left := centre.x - gap * (need - 1) / 2.0
		for k in need:
			var at := Vector2(left + k * gap, centre.y)
			on.draw_circle(at, radius, TICK if k < have else Color(0.3, 0.3, 0.32, 0.6))

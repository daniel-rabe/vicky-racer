class_name TownChallenges
extends Node2D
## Pop-up challenges in the open world (docs/DESIGN.md §30), the open-world plan's idea 16: no
## racers, no clock, nothing to lose, a few coins for trying.
##   - Ramp jump: every hop off a jump ramp is measured, takeoff to landing, and shown in metres
##     (40 px to the metre); a new longest jump of the drive pays JUMP_PAY.
##   - Drift zone: a painted square on the harbour's quay with stars on it. Drifting inside it
##     earns a star every STAR_EVERY seconds of drift (each one pops up over the car); driving
##     out pays a coin a star, up to MAX_STARS.

const PX_PER_METRE := 40.0
const JUMP_PAY := 3
const DRIFT_ZONE := Rect2(4960.0, 8290.0, 740.0, 330.0)
const STAR_EVERY := 0.4
const MAX_STARS := 20
const YELLOW := Color(1, 0.824, 0.247)
const CHIME := "res://art/sfx/sparkle.wav"

## The town screen (TownScreen): the player, the HUD, paying.
var screen: Node
var best_jump := 0.0
var last_jump := 0.0
var stars := 0
var _takeoff := Vector2.INF
var _drift := 0.0
var _time := 0.0
var _voice: AudioStreamPlayer


func _enter_tree() -> void:
	EventSystem.CAR_jumped.connect(func(car: Node) -> void:
		if car == screen.player:
			_takeoff = car.global_position)
	EventSystem.CAR_landed.connect(_on_landed)


func _ready() -> void:
	_voice = AudioStreamPlayer.new()
	_voice.bus = &"SFX"
	add_child(_voice)


func _on_landed(car: Node) -> void:
	if car != screen.player or _takeoff == Vector2.INF:
		return
	last_jump = roundf(car.global_position.distance_to(_takeoff) / PX_PER_METRE)
	_takeoff = Vector2.INF
	if last_jump > best_jump:
		var first := best_jump == 0.0
		best_jump = last_jump
		screen.hud.show_banner("JUMP!  %d m" % last_jump if first else "LONGEST JUMP!  %d m   +%d" % [last_jump, JUMP_PAY])
		if not first:
			EventSystem.PRO_coins_found.emit(JUMP_PAY)
		_play(CHIME, -6.0)
	else:
		screen.hud.show_banner("JUMP!  %d m" % last_jump)


func _physics_process(delta: float) -> void:
	_time += delta
	queue_redraw()
	var player: Car = screen.player
	if player == null or screen.riding != &"car" or screen.street_race.running:
		return
	var inside := DRIFT_ZONE.has_point(player.global_position)
	if inside and player.is_drifting and stars < MAX_STARS:
		_drift += delta
		if _drift >= STAR_EVERY:
			_drift -= STAR_EVERY
			stars += 1
			_pop_star(player.global_position)
	elif not inside and stars > 0:
		EventSystem.PRO_coins_found.emit(stars)
		screen.hud.show_banner("DRIFT STARS  %d   +%d" % [stars, stars])
		stars = 0
		_drift = 0.0


func _pop_star(at: Vector2) -> void:
	var star := Star.new()
	star.position = at + Vector2(0, -60)
	star.z_index = 5
	add_child(star)
	var tween := star.create_tween()
	tween.tween_property(star, "position", star.position + Vector2(0, -90), 0.7).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(star, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tween.tween_callback(star.queue_free)
	_voice.pitch_scale = 1.0 + 0.04 * mini(stars, 15)
	_play(CHIME, -14.0)


func _play(path: String, volume_db: float) -> void:
	if not SoundManager.audible() or not ResourceLoader.exists(path):
		return
	_voice.stream = load(path)
	_voice.volume_db = volume_db
	_voice.play()


## The drift zone painted on the quay: a dashed yellow frame and big pale stars, and the count
## so far over it while drifting.
func _draw() -> void:
	var r := DRIFT_ZONE
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		var n := int(a.distance_to(b) / 50.0)
		for k in n:
			if k % 2 == 0:
				draw_line(a.lerp(b, float(k) / n), a.lerp(b, float(k + 1) / n), Color(YELLOW, 0.9), 12.0)
	for spot: Vector2 in [Vector2(0.25, 0.3), Vector2(0.55, 0.65), Vector2(0.82, 0.32)]:
		var at := r.position + r.size * spot
		Star.draw_star(self, at, 60.0, Color(1, 1, 1, 0.22 + 0.06 * sin(_time * 3.0 + spot.x * 7.0)))
	if stars > 0:
		var at := r.position + Vector2(r.size.x / 2.0, -40.0)
		Star.draw_star(self, at, 34.0, YELLOW)
		draw_string(ThemeDB.fallback_font, at + Vector2(44, 16), str(stars), HORIZONTAL_ALIGNMENT_LEFT, -1, 48, YELLOW)


class Star extends Node2D:
	func _draw() -> void:
		draw_star(self, Vector2.ZERO, 26.0, YELLOW)

	static func draw_star(on: CanvasItem, at: Vector2, radius: float, colour: Color) -> void:
		var points := PackedVector2Array()
		for k in 10:
			var reach := radius if k % 2 == 0 else radius * 0.45
			points.append(at + Vector2.from_angle(-PI / 2.0 + k * PI / 5.0) * reach)
		on.draw_colored_polygon(points, colour)

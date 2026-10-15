class_name Fireworks
extends CanvasLayer
## Fireworks at night (docs/DESIGN.md §32), the open-world plan's idea 36. At night, driving
## or walking out to the harbour's quay and pier, or sailing to the lighthouse, starts a show:
## rockets whoosh up and burst into rings of sparks in the paint colours, one after another,
## for as long as he stays. Pure show, nothing to do.
##
## A CanvasLayer that follows the world's camera, so the sparks sit in the world but stay
## bright: the night's dark blue (a CanvasModulate) only tints the world's own canvas.

const ZONES := [Rect2(4100.0, 8000.0, 1800.0, 800.0), Rect2(4400.0, 8650.0, 520.0, 1000.0)]
const LIGHTHOUSE_REACH := Island.LIGHTHOUSE_RADIUS + 700.0
## Seconds between rockets.
const EVERY := Vector2(0.45, 1.0)
const RISE := 0.9
const BURST := 1.6
const SPARKS := 28
const COLOURS := [Color(1, 0.35, 0.4), Color(1, 0.85, 0.3), Color(0.4, 0.7, 1.0), Color(0.45, 1.0, 0.55),
	Color(0.8, 0.5, 1.0), Color(1, 0.6, 0.85), Color(1, 1, 1)]
const WHOOSH := "res://art/sfx/ramp_whoosh.wav"
const POP := "res://art/sfx/wall_bump.wav"
const CRACKLE := "res://art/sfx/sparkle.wav"

## The town screen (TownScreen): the player, and whether it is night.
var screen: Node
## Set by the tests and --fireworks: a show whatever the time and place.
var always := false
var showing := false
var rockets: Array[Dictionary] = []
var bursts: Array[Dictionary] = []
var _next := 0.0
var _rng := RandomNumberGenerator.new()
var _show: Node2D
var _voices: Array[AudioStreamPlayer] = []


func _ready() -> void:
	layer = 1
	follow_viewport_enabled = true
	_rng.randomize()
	_show = Show.new()
	_show.fireworks = self
	add_child(_show)
	for i in 3:
		var voice := AudioStreamPlayer.new()
		voice.bus = &"SFX"
		add_child(voice)
		_voices.append(voice)


static func in_zone(at: Vector2) -> bool:
	for zone: Rect2 in ZONES:
		if zone.has_point(at):
			return true
	return at.distance_to(Island.LIGHTHOUSE) < LIGHTHOUSE_REACH


func _process(delta: float) -> void:
	var player: Car = screen.player
	showing = player != null and (always or (screen.night != null and in_zone(player.global_position)))
	if showing:
		_next -= delta
		if _next <= 0.0:
			_next = _rng.randf_range(EVERY.x, EVERY.y)
			_launch(player.global_position)
	for rocket in rockets:
		rocket["t"] += delta / RISE
		if rocket["t"] >= 1.0:
			_burst(rocket["to"], rocket["colour"])
	rockets = rockets.filter(func(r: Dictionary) -> bool: return r["t"] < 1.0)
	for burst in bursts:
		burst["t"] += delta / BURST
	bursts = bursts.filter(func(b: Dictionary) -> bool: return b["t"] < 1.0)
	if not rockets.is_empty() or not bursts.is_empty():
		_show.queue_redraw()


## A rocket up to a spot in the sky over where he stands, somewhere he can see it.
func _launch(around: Vector2) -> void:
	var to := around + Vector2(_rng.randf_range(-650.0, 650.0), _rng.randf_range(-420.0, -60.0))
	var from := to + Vector2(_rng.randf_range(-90.0, 90.0), 560.0)
	rockets.append({"from": from, "to": to, "t": 0.0, "colour": COLOURS[_rng.randi() % COLOURS.size()]})
	_play(0, WHOOSH, -18.0, _rng.randf_range(1.4, 1.8))


func _burst(at: Vector2, colour: Color) -> void:
	var turn := _rng.randf() * TAU
	bursts.append({"at": at, "t": 0.0, "colour": colour, "turn": turn, "size": _rng.randf_range(180.0, 300.0),
		"second": COLOURS[_rng.randi() % COLOURS.size()]})
	_play(1, POP, -8.0, _rng.randf_range(0.45, 0.6))
	_play(2, CRACKLE, -16.0, _rng.randf_range(0.9, 1.2))


func _play(slot: int, path: String, volume_db: float, pitch: float) -> void:
	if not SoundManager.audible() or not ResourceLoader.exists(path):
		return
	var voice := _voices[slot]
	voice.stream = load(path)
	voice.volume_db = volume_db
	voice.pitch_scale = pitch
	voice.play()


## The rockets and the bursts, drawn in code.
class Show extends Node2D:
	var fireworks: Fireworks

	func _draw() -> void:
		for rocket in fireworks.rockets:
			var t: float = rocket["t"]
			var head: Vector2 = rocket["from"].lerp(rocket["to"], 1.0 - pow(1.0 - t, 2.0))
			var tail: Vector2 = rocket["from"].lerp(rocket["to"], maxf(1.0 - pow(1.0 - t + 0.12, 2.0), 0.0))
			draw_line(tail, head, Color(1, 0.85, 0.5, 0.6), 4.0, true)
			draw_circle(head, 6.0, Color(1, 0.95, 0.75))
		for burst in fireworks.bursts:
			var t: float = burst["t"]
			var reach: float = burst["size"] * (1.0 - pow(1.0 - minf(t * 1.6, 1.0), 3.0))
			var drop := 70.0 * t * t
			var alpha := 1.0 - t * t
			var colour: Color = burst["colour"]
			if t < 0.15:
				draw_circle(burst["at"], 60.0 * (1.0 - t / 0.15) + 10.0, Color(1, 1, 0.9, 0.8))
			draw_circle(burst["at"], reach * 0.9, Color(colour, 0.08 * alpha))
			for k in SPARKS:
				var dir := Vector2.from_angle(burst["turn"] + k * TAU / SPARKS)
				var tip: Vector2 = burst["at"] + dir * reach + Vector2(0, drop)
				var back: Vector2 = burst["at"] + dir * reach * 0.72 + Vector2(0, drop * 0.7)
				var c: Color = colour if k % 2 == 0 else burst["second"]
				draw_line(back, tip, Color(c, alpha * 0.7), 4.0, true)
				draw_circle(tip, 5.0, Color(c.lightened(0.3), alpha))

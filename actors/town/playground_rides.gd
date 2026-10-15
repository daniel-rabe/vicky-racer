class_name PlaygroundRides
extends Node2D
## The playgrounds come alive on foot (docs/DESIGN.md §32), the open-world plan's idea 25.
## Each playground picture has a swing, two slides and a see-saw. Walking up to one (from the
## side it faces) puts Vicky on it: up the ladder and WHEE down the slide, a few swings back
## and forth, up and down on the see-saw. Pure fun: no coins, no counting, as often as he
## likes. A car just drives round the playground (it is solid, as before); only on foot can
## he play.

## Each ride, in the picture's own 0..1 space: where he steps on from (just outside the
## picture), and the path he takes on it.
const RIDES := [
	{"kind": &"swing", "entry": Vector2(0.28, -0.1), "path": [Vector2(0.28, 0.2), Vector2(0.28, 0.32)]},
	{"kind": &"slide", "entry": Vector2(1.1, 0.12), "path": [Vector2(0.76, 0.1), Vector2(0.69, 0.4)]},
	{"kind": &"slide", "entry": Vector2(-0.1, 0.56), "path": [Vector2(0.21, 0.55), Vector2(0.23, 0.88)]},
	{"kind": &"seesaw", "entry": Vector2(0.52, 1.1), "path": [Vector2(0.52, 0.68), Vector2(0.52, 0.92)]},
]
## Stepping this near a ride's entry gets on; he must walk this far away before it works again.
const ON_REACH := 70.0
const REARM := 150.0
## How much bigger he looks high up (top of the slide, the swing's high point).
const UP_SCALE := 1.3
const WHEE := "res://art/sfx/cheer.wav"
const CREAK := "res://art/sfx/sparkle.wav"

## The town screen (TownScreen): the kid, riding.
var screen: Node
## Every ride in town: {kind, entry, path (world points)}.
var rides: Array[Dictionary] = []
## The ride he is on now ({} = none), and the one he got off last (until he walks away).
var on_ride := {}
var _used := {}
var _words: Array[Dictionary] = []
var _voice: AudioStreamPlayer


func _ready() -> void:
	_voice = AudioStreamPlayer.new()
	_voice.bus = &"SFX"
	add_child(_voice)
	z_index = 6
	for rect: Rect2 in screen.town.playgrounds:
		for ride: Dictionary in RIDES:
			var path: Array[Vector2] = []
			for p: Vector2 in ride["path"]:
				path.append(rect.position + rect.size * p)
			rides.append({"kind": ride["kind"], "entry": rect.position + rect.size * ride["entry"], "path": path})


func _physics_process(delta: float) -> void:
	for word in _words:
		word["time"] += delta
	_words = _words.filter(func(w: Dictionary) -> bool: return w["time"] < 1.2)
	if not _words.is_empty():
		queue_redraw()
	if screen.riding != &"foot" or not on_ride.is_empty() or screen.kid == null:
		return
	var at: Vector2 = screen.kid.global_position
	if not _used.is_empty() and at.distance_to(_used["entry"]) > REARM:
		_used = {}
	for ride in rides:
		if ride != _used and at.distance_to(ride["entry"]) < ON_REACH:
			play(ride)
			return


## Put him on `ride` and play it through; he steps off where he got on.
func play(ride: Dictionary) -> void:
	var kid: Kid = screen.kid
	on_ride = ride
	_used = ride
	kid.frozen = true
	var layer := kid.collision_layer
	var mask := kid.collision_mask
	kid.collision_layer = 0
	kid.collision_mask = 0
	var body: Node2D = kid.get_node(^"Body")
	var path: Array[Vector2] = ride["path"]
	var tween := create_tween()
	tween.tween_property(kid, "global_position", path[0], 0.35)
	match ride["kind"]:
		&"slide":
			# Up the ladder (he grows as he climbs), a moment at the top, then WHEE down.
			tween.parallel().tween_property(body, "scale", Vector2.ONE * UP_SCALE, 0.35)
			tween.parallel().tween_property(kid, "rotation", (path[1] - path[0]).angle(), 0.2)
			tween.tween_interval(0.35)
			tween.tween_callback(func() -> void: _say("WHEE!", path[0]))
			tween.tween_property(kid, "global_position", path[1], 0.55).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
			tween.parallel().tween_property(body, "scale", Vector2.ONE, 0.55)
			tween.tween_callback(func() -> void: TownFx.hearts(get_parent(), path[1], 4))
		&"swing":
			# Three swings, high at each end.
			tween.parallel().tween_property(kid, "rotation", PI / 2.0, 0.2)
			for k in 3:
				tween.tween_property(kid, "global_position", path[1], 0.45).set_trans(Tween.TRANS_SINE)
				tween.parallel().tween_property(body, "scale", Vector2.ONE * UP_SCALE, 0.45).set_trans(Tween.TRANS_SINE)
				tween.tween_property(kid, "global_position", path[0], 0.45).set_trans(Tween.TRANS_SINE)
				tween.parallel().tween_property(body, "scale", Vector2.ONE * 1.1, 0.45).set_trans(Tween.TRANS_SINE)
				if k == 1:
					tween.tween_callback(func() -> void: _say("WHEE!", path[0]))
			tween.tween_property(body, "scale", Vector2.ONE, 0.2)
		&"seesaw":
			# Up and down on the end of the see-saw.
			tween.parallel().tween_property(kid, "rotation", PI / 2.0, 0.2)
			for k in 3:
				tween.tween_property(body, "scale", Vector2.ONE * UP_SCALE, 0.4).set_trans(Tween.TRANS_SINE)
				tween.tween_property(body, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_SINE)
				tween.tween_callback(_play.bind(CREAK, -16.0))
			tween.tween_callback(func() -> void: _say("BOING!", path[0]))
	tween.tween_property(kid, "global_position", ride["entry"], 0.3)
	tween.tween_callback(func() -> void:
		body.scale = Vector2.ONE
		kid.collision_layer = layer
		kid.collision_mask = mask
		kid.velocity = Vector2.ZERO
		kid.reset_physics_interpolation()
		if screen.riding == &"foot" and screen.player == kid:
			kid.frozen = false
		on_ride = {})


func _say(text: String, at: Vector2) -> void:
	_words.append({"text": text, "at": at + Vector2(-60, -70), "time": 0.0})
	_play(WHEE, -12.0)
	queue_redraw()


func _play(path: String, volume_db: float) -> void:
	if not SoundManager.audible() or not ResourceLoader.exists(path):
		return
	_voice.stream = load(path)
	_voice.volume_db = volume_db
	_voice.play()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for word in _words:
		var t: float = word["time"]
		var at: Vector2 = word["at"] - Vector2(0, 50.0 * t)
		var alpha := 1.0 - maxf(t - 0.7, 0.0) / 0.5
		draw_string_outline(font, at, word["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 44, 10, Color(0.055, 0.078, 0.11, alpha))
		draw_string(font, at, word["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(1, 0.824, 0.247, alpha))

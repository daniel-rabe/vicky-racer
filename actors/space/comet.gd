extends Node2D
## A comet crossing a space course (docs/DESIGN.md §24.2), made to be fair to a small child:
##   1. WARNING seconds before it comes, its path glows on the course as a dashed yellow streak
##      and a soft rising chime plays;
##   2. it whooshes along the streak with its sparkly tail, in FLIGHT seconds, and is gone;
##   3. a ship it brushes gets a sideways nudge (Ship.nudge) and a shower of sparkles. Never a
##      stop, never a spin, and at most once a pass.
## It comes every `period` seconds, on a fixed rhythm from when the course is loaded (`offset`
## shifts it), so a child can learn when it comes. The track builder places it from the
## layout's `comets`; `from` and `to` are in the track's own coordinates.

const COMET := preload("res://art/props/space/comet.png")
const CHIME := preload("res://art/sfx/comet_chime.wav")
const WHOOSH := preload("res://art/sfx/comet_whoosh.wav")
const WARNING := 1.5
const FLIGHT := 0.9
## How close to the head, px, a ship is brushed; how hard, px/s, it is pushed along.
const HIT_RADIUS := 80.0
const PUSH := 300.0
const GLOW := Color(1.0, 0.89, 0.36)
const DASH := 34.0
## Above the racers, like the scenery bridges: the comet flies over everything.
const HEAD_Z := 3

@export var from := Vector2.ZERO
@export var to := Vector2.ZERO
@export var period := 8.0
@export var offset := 0.0

var _time := 0.0
var _phase := &"idle"  # &"idle", &"warning" or &"flying"
var _nudged := {}  # ship -> true, this pass
var _head: Sprite2D
var _sound: AudioStreamPlayer2D


func _ready() -> void:
	_head = Sprite2D.new()
	_head.name = "Head"
	_head.texture = COMET
	_head.rotation = (to - from).angle()
	_head.z_index = HEAD_Z
	_head.visible = false
	add_child(_head)
	_sound = AudioStreamPlayer2D.new()
	_sound.name = "Sound"
	_sound.bus = &"SFX"
	_sound.max_distance = 2400.0
	_head.add_child(_sound)


## 0..1 through the warning, the flight, or nothing (idle).
func progress() -> float:
	var c := fposmod(_time - offset, period)
	match _phase:
		&"warning": return (c - (period - WARNING - FLIGHT)) / WARNING
		&"flying": return (c - (period - FLIGHT)) / FLIGHT
	return 0.0


func is_flying() -> bool:
	return _phase == &"flying"


func head_position() -> Vector2:
	return from.lerp(to, clampf(progress(), 0.0, 1.0)) if is_flying() else from


func _physics_process(delta: float) -> void:
	_time += delta
	var c := fposmod(_time - offset, period)
	var phase := &"idle"
	if c >= period - FLIGHT:
		phase = &"flying"
	elif c >= period - FLIGHT - WARNING:
		phase = &"warning"
	if phase != _phase:
		_enter(phase)
	if is_flying():
		_head.position = head_position()
		var along := (to - from).normalized()
		for car in get_tree().get_nodes_in_group(&"cars"):
			if car is Ship and not _nudged.has(car) \
					and to_local(car.global_position).distance_to(_head.position) < HIT_RADIUS:
				_nudged[car] = true
				car.nudge(along * PUSH)
	queue_redraw()


func _enter(phase: StringName) -> void:
	_phase = phase
	_head.visible = phase == &"flying"
	if phase == &"warning":
		_nudged.clear()
		_head.position = from.lerp(to, 0.5)  # the chime comes from the middle of the path
		_play(CHIME, -8.0)
		EventSystem.SPC_comet_warned.emit(self)
	elif phase == &"flying":
		_head.position = from
		_play(WHOOSH, -3.0)
		EventSystem.SPC_comet_passing.emit(self)


func _play(stream: AudioStream, volume_db: float) -> void:
	if not SoundManager.audible():
		return
	_sound.stream = stream
	_sound.volume_db = volume_db
	_sound.play()


## The streak: a soft glow along the path and bright dashes, fading in through the warning and
## out as the comet passes.
func _draw() -> void:
	var alpha := 0.0
	match _phase:
		&"warning": alpha = clampf(progress() * 2.0, 0.0, 1.0)
		&"flying": alpha = 1.0 - progress()
	if alpha <= 0.0:
		return
	draw_line(from, to, Color(GLOW, 0.22 * alpha), 46.0)
	var length := from.distance_to(to)
	var along := (to - from) / maxf(length, 1.0)
	var d := 0.0
	while d < length:
		draw_line(from + along * d, from + along * minf(d + DASH, length), Color(GLOW, 0.9 * alpha), 8.0)
		d += DASH * 2.0

extends CanvasLayer
## The race HUD (docs/mockups/hud_layout): position, lap, lap timers, a speed bar, the
## minimap, the 3-2-1-GO countdown and the FINISH! banner. Race state arrives over the
## RAC_ signals; the speed bar and minimap read the cars handed over in setup(), because
## they need every frame what no signal should carry 60 times a second.

const SUFFIX := {1: "ST", 2: "ND", 3: "RD", 4: "TH"}
const GO_COLOUR := Color(0.18, 0.769, 0.42)
const COUNT_COLOUR := Color(1, 0.824, 0.247)

var _player_car: Car
var _racer_count := 4
var _laps := 3
var _player_laps := 0
var _lap_clock := 0.0
var _best := 0.0
var _running := false

@onready var _position: Label = %Position
@onready var _suffix: Label = %Suffix
@onready var _of: Label = %Of
@onready var _lap: Label = %Lap
@onready var _time: Label = %Time
@onready var _best_label: Label = %Best
@onready var _speed: ProgressBar = %Speed
@onready var _minimap: Minimap = %Minimap
@onready var _countdown: Control = %Countdown
@onready var _countdown_label: Label = %CountdownLabel
@onready var _banner: Label = %Banner


func _enter_tree() -> void:
	EventSystem.RAC_countdown_tick.connect(_on_countdown_tick)
	EventSystem.RAC_race_started.connect(func() -> void: _running = true)
	EventSystem.RAC_lap_completed.connect(_on_lap_completed)
	EventSystem.RAC_positions_updated.connect(_on_positions_updated)


func _ready() -> void:
	_countdown.visible = false
	_banner.visible = false


func setup(track: Track, racers: Array[Dictionary], laps: int) -> void:
	_laps = laps
	_racer_count = racers.size()
	_of.text = "/%d" % _racer_count
	for r in racers:
		if r["is_player"]:
			_player_car = r["car"]
	_minimap.setup(track, racers)
	_update_lap_label()


func _process(delta: float) -> void:
	if _running:
		_lap_clock += delta
	_time.text = _format(_lap_clock)
	if _player_car:
		_speed.value = _player_car.velocity.length() / _player_car.config.max_speed


func _on_countdown_tick(seconds_left: int) -> void:
	_countdown.visible = true
	_countdown.modulate.a = 1.0
	_countdown_label.text = str(seconds_left) if seconds_left > 0 else "GO!"
	_countdown_label.label_settings.font_color = COUNT_COLOUR if seconds_left > 0 else GO_COLOUR
	_countdown.pivot_offset = _countdown.size / 2.0
	_countdown.scale = Vector2(1.4, 1.4)
	var tween := create_tween()
	tween.tween_property(_countdown, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if seconds_left == 0:
		tween.tween_interval(0.3)
		tween.tween_property(_countdown, "modulate:a", 0.0, 0.6)
		tween.tween_callback(func() -> void: _countdown.visible = false)


func _on_lap_completed(car: Node, lap: int, lap_time: float) -> void:
	if car != _player_car:
		return
	_player_laps = lap
	_best = lap_time if _best == 0.0 else minf(_best, lap_time)
	_best_label.text = "BEST %s" % _format(_best)
	_lap_clock = 0.0
	_update_lap_label()
	if lap >= _laps:
		_running = false
		_banner.visible = true
		_banner.pivot_offset = _banner.size / 2.0
		_banner.scale = Vector2(0.6, 0.6)
		create_tween().tween_property(_banner, "scale", Vector2.ONE, 0.35) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_positions_updated(order: Array) -> void:
	for entry: Dictionary in order:
		if entry["is_player"]:
			_position.text = str(entry["position"])
			_suffix.text = SUFFIX.get(entry["position"], "TH")


func _update_lap_label() -> void:
	_lap.text = "%d / %d" % [mini(_player_laps + 1, _laps), _laps]


static func _format(seconds: float) -> String:
	return "%d:%05.2f" % [int(seconds) / 60, fmod(seconds, 60.0)]

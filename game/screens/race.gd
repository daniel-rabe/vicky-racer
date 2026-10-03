extends Node2D
## The race screen. Phase 6: the player alone on Track 01, to drive it and check surfaces
## and lap detection; RaceManager, the AI opponents and the HUD arrive in Phase 7.
##
## Escape returns to the garage. Dev, until Phase 7: F fakes a race finish (pays real coins).
## Dev: `-- --overview` frames the whole track in one view, for checking the layout.

@onready var track: Track = $Track
@onready var car: Car = $Car
@onready var camera_rig: Node2D = $Car/ChaseCamera
@onready var readout: Label = %Readout

var _laps := 0
var _checkpoint_passed := false
var _lap_start_ms := 0
var _last_lap := 0.0
var _best_lap := 0.0


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_state_changed)


func _ready() -> void:
	car.global_transform = track.grid_transforms()[0]
	car.reset_physics_interpolation()
	camera_rig.snap_to_car()
	camera_rig.set_world_bounds(track.world_rect())
	track.checkpoint_crossed.connect(func(c: Car) -> void:
		if c == car:
			_checkpoint_passed = true)
	track.finish_crossed.connect(_on_finish_crossed)
	_lap_start_ms = Time.get_ticks_msec()
	EventSystem.PRO_state_requested.emit()
	if "--overview" in OS.get_cmdline_user_args():
		_show_overview()


func _show_overview() -> void:
	var rect := track.world_rect()
	var view := Camera2D.new()
	var fit := minf(1920.0 / rect.size.x, 1080.0 / rect.size.y)
	view.zoom = Vector2(fit, fit)
	view.position = rect.get_center()
	add_child(view)
	view.make_current()
	$Debug.visible = false


func _on_state_changed(state: Dictionary) -> void:
	for setup: DriftSetup in state["setups"]:
		if setup.id == state["equipped"]:
			car.setup = setup


## A lap only counts if the mid-lap checkpoint was crossed first (docs/DESIGN.md §7.4).
func _on_finish_crossed(c: Car) -> void:
	if c != car or not _checkpoint_passed:
		return
	_checkpoint_passed = false
	_laps += 1
	var now := Time.get_ticks_msec()
	_last_lap = (now - _lap_start_ms) / 1000.0
	_best_lap = _last_lap if _best_lap == 0.0 else minf(_best_lap, _last_lap)
	_lap_start_ms = now


func _process(_delta: float) -> void:
	var progress := track.progress_at(car.global_position) / track.lap_length()
	readout.text = "\n".join([
		"SURFACE  %s" % String(track.surface_at(car.global_position)).to_upper(),
		"LAP      %d   (%d%% round)   checkpoint %s" % [_laps, progress * 100.0, "OK" if _checkpoint_passed else "-"],
		"LAST     %.2fs   BEST %.2fs" % [_last_lap, _best_lap],
		"SPEED    %4d / %d" % [car.velocity.length(), car.config.max_speed * car.surface_speed_mult],
		"ESC garage   F fake finish (dev, pays real coins)",
	])


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		EventSystem.UI_screen_requested.emit(&"garage")
	elif key.physical_keycode == KEY_F:
		var main := get_tree().root.get_node_or_null("Main")
		if main and main.has_method("_fake_race_finish"):
			main._fake_race_finish(randi_range(1, 4))
			EventSystem.UI_screen_requested.emit(&"results")

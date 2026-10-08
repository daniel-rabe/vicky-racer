class_name GhostCar
extends Sprite2D
## A recorded lap driven again as a see-through car (docs/DESIGN.md §16). It sets off each
## time the player crosses the line (`start`) and drives the lap exactly as recorded — one
## sample per physics tick, so at the recording's tick rate it is where the car was to the
## pixel — then fades away at the line. It touches nothing: no body, no collisions.
##
## Placed in _physics_process, so physics interpolation smooths it like a real car. Drawn at
## the car's own layer (above a bridge deck while on it) but before the cars in the tree, so a
## real car always covers it. Its wheels roll like a real car's (RollingTread), at the speed
## between samples.

const FADE_SECONDS := 0.4
## Where a lap's setup may live: a car, a boat (docs/DESIGN.md §20) or a ship (§24).
const SETUP_DIRS: Array[String] = ["res://game/configs/setups/", "res://game/configs/boats/",
	"res://game/configs/ships/"]

var ghost: GhostLap:
	set(value):
		ghost = value
		if ghost:
			for dir in SETUP_DIRS:
				var path := dir + "%s.tres" % ghost.setup_id
				if ResourceLoader.exists(path):
					var setup: DriftSetup = load(path)
					texture = Paint.body(setup, ghost.paint)
					_kind = setup.kind
					break
			_seat_driver()
## The ghost's colour: see-through white for the player's own best, gold for the developer's.
var tint := Color(1, 1, 1, 0.45)
## Physics ticks since this lap started.
var tick := 0
var running := false

var _tread: RollingTread
## What the lap was driven in: a boat's driver wears a cap and life vest, not a helmet.
var _kind := &"car"


func _ready() -> void:
	modulate = tint
	visible = false
	_tread = RollingTread.new()
	_tread.sprite = self
	add_child(_tread)


## Vicky at the wheel, see-through with the rest of the ghost (docs/DESIGN.md §22).
func _seat_driver() -> void:
	var old := get_node_or_null(^"Driver")
	if old:
		remove_child(old)
		old.queue_free()
	DriverRider.build(self, DriverLook.texture(DriverLook.VICKY, _kind))


func start() -> void:
	if ghost == null:
		return
	tick = 0
	running = true
	visible = true
	modulate = tint
	_place()
	reset_physics_interpolation()


func _physics_process(delta: float) -> void:
	if not running:
		return
	tick += 1
	if tick > ghost.frame_count():
		running = false
		create_tween().tween_property(self, "modulate:a", 0.0, FADE_SECONDS)
		return
	var before := global_position
	_place()
	var moved := (global_position - before).dot(Vector2.RIGHT.rotated(global_rotation))
	_tread.advance(moved, moved / delta)


func _place() -> void:
	if ghost.ticks_per_second == Engine.physics_ticks_per_second:
		# Same tick rate as the recording: exactly the recorded sample.
		var i := maxi(tick - 1, 0)
		global_position = ghost.position_at_frame(i)
		global_rotation = ghost.rotation_at_frame(i)
		z_index = ghost.layer_at_frame(i)
	else:
		var seconds := float(tick) / Engine.physics_ticks_per_second
		var at := ghost.transform_at(seconds)
		global_position = at.origin
		global_rotation = at.get_rotation()
		z_index = ghost.layer_at_frame(roundi(seconds * ghost.ticks_per_second) - 1)

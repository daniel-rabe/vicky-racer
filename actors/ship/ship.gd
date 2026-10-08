class_name Ship
extends Boat
## One racing spaceship (docs/DESIGN.md §23.1). A Boat underneath, so a Car in every way the
## race, the AI, the HUD and the ghosts care about: it bounces softly off asteroids, the edge
## and other ships as a boat bounces off the shore, and leaves no skid marks. The rest is
## numbers (base_ship.tres: the longest, softest drift in the game) and the look of floating:
##   - it hovers, swaying a little, with its shadow well below it, so it reads as off the ground;
##   - a comet (Comet) can give it a sideways nudge, never a stop or a spin.
## Space has no currents and no ramps, so a ship's `current` stays zero and it never jumps.

## The hover: degrees of sway either way, and the drift up and down, px, of its shadow.
const SWAY_DEGREES := 2.5
const HOVER_PX := 3.0
const HOVER_SHADOW := Vector2(14, 24)

var _hover := 0.0


## A comet brushed past (Comet): pushed sideways, `push` px/s, the way it was flying.
func nudge(push: Vector2) -> void:
	if frozen:
		return
	velocity += push
	EventSystem.CAR_comet_nudged.emit(self)


## Floating, not bobbing: a slow sway, a gentle rise and fall, and a shadow far below.
func _draw_motion(delta: float) -> void:
	var fraction := clampf(velocity.length() / config.max_speed, 0.0, 1.0)
	_hover += delta * (1.6 + 1.4 * fraction)
	var lift := sin(_hover * 1.3)
	_body.rotation = deg_to_rad(SWAY_DEGREES) * sin(_hover) * (0.5 + 0.5 * fraction)
	_body.scale = Vector2.ONE * (1.0 + 0.012 * lift)
	_shadow.visible = true
	_shadow.texture = _body.texture  # follows a repaint
	# Down and right on screen whichever way the ship points: the light does not turn with it.
	_shadow.position = (HOVER_SHADOW + Vector2(0, HOVER_PX * lift)).rotated(-rotation)
	_shadow.rotation = _body.rotation
	_shadow.scale = Vector2.ONE * (0.92 - 0.02 * lift)

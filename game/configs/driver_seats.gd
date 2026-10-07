class_name DriverSeats
extends RefCounted
## Where the driver sits in each vehicle that shows one (docs/DESIGN.md §22.2), for DriverRider.
## Only vehicles with an open seat or glass to see through have a driver. A closed roof keeps
## its driver hidden: one drawn on the roof looked as if it sat on top of the car, not inside.
##
## Keyed by the body picture's name without its paint: a paint is a Kontext recolour of the
## same picture, so "paint/kart_blue.png" seats its driver where "setups/kart.png" does.
## `pos` is the driver's head in texture pixels from the picture's centre (+X is the nose).
## `mode`:
##   open  - drawn straight on top (boats, the kart, the formula)
##   glass - seen through glass (`window`, a Rect2 from the centre): the bubble car's dome,
##           the town trucks' windscreens
## `scale` multiplies the driver picture (40 px for a child, 44 px for a grown-up).

const OPEN := &"open"
const GLASS := &"glass"

const SEATS := {
	# Race cars (128 x 72).
	"kart": {"pos": Vector2(-19, 0), "mode": OPEN},
	"bubble": {"pos": Vector2(0, 0), "mode": GLASS, "window": Rect2(-17, -17, 34, 34)},
	"formula": {"pos": Vector2(-10, 0), "mode": OPEN, "scale": 0.85},
	# Boats (128 x 72).
	"speedboat": {"pos": Vector2(3, -6), "mode": OPEN},
	"jetski": {"pos": Vector2(6, 0), "mode": OPEN},
	"duck": {"pos": Vector2(-12, 0), "mode": OPEN},
	"swan": {"pos": Vector2(-1, 0), "mode": OPEN},
	"tugboat": {"pos": Vector2(-20, 0), "mode": OPEN},
	"pirate": {"pos": Vector2(-24, -2), "mode": OPEN},
	"banana_boat": {"pos": Vector2(-4, 0), "mode": OPEN},
	# Town traffic (their own sizes), grown-ups behind the windscreen.
	"bus": {"pos": Vector2(12, -12), "mode": GLASS, "window": Rect2(8, -26, 14, 52)},
	"fire_engine": {"pos": Vector2(55, -10), "mode": GLASS, "window": Rect2(50, -20, 10, 38)},
	"garbage_truck": {"pos": Vector2(60, -12), "mode": GLASS, "window": Rect2(59, -24, 7, 40)},
}


## The seat for a body picture, or {} if it shows no driver.
static func seat_for(body: Texture2D) -> Dictionary:
	if body == null:
		return {}
	return SEATS.get(base_name(body.resource_path), {})


## "res://art/cars/paint/kart_blue.png" -> "kart"; "res://art/boats/duck.png" -> "duck".
static func base_name(path: String) -> String:
	var name := path.get_file().get_basename()
	if path.get_base_dir().ends_with("/paint"):
		for colour in Paint.COLOURS:
			if name.ends_with("_" + String(colour)):
				return name.trim_suffix("_" + String(colour))
	return name

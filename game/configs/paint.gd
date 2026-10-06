class_name Paint
extends RefCounted
## The paint shop's palette (docs/DESIGN.md §9.3): every owned car can be painted in any of
## these colours, free. &"original" is the car as designed; the others are Kontext
## recolours built by tools/comfy/generate_assets.py (the manifest's `paints` section) into
## art/ui/cards/paint/<car>_<colour>.png and art/cars/paint/<car>_<colour>.png.

const ORIGINAL := &"original"
## In the order the paint button cycles through them.
const COLOURS: Array[StringName] = [&"original", &"blue", &"yellow", &"green", &"purple", &"pink"]
## Swatch colours for the garage; the original shows the car's own card.
const SWATCHES := {
	&"blue": Color(0.227, 0.525, 1.0),
	&"yellow": Color(1.0, 0.824, 0.247),
	&"green": Color(0.18, 0.769, 0.42),
	&"purple": Color(0.62, 0.36, 0.95),
	&"pink": Color(1.0, 0.45, 0.72),
}


## The car's race body in this paint (128 x 72, facing +X). Boats keep theirs in art/boats/paint/.
static func body(setup: DriftSetup, colour: StringName) -> Texture2D:
	var pattern := "res://art/boats/paint/%s_%s.png" if setup.kind == &"boat" else "res://art/cars/paint/%s_%s.png"
	return _painted(pattern, setup, colour, setup.body)


## The car's garage card art in this paint.
static func card(setup: DriftSetup, colour: StringName) -> Texture2D:
	var pattern := "res://art/ui/cards/boats/paint/%s_%s.png" if setup.kind == &"boat" else "res://art/ui/cards/paint/%s_%s.png"
	return _painted(pattern, setup, colour, setup.card_art)


## The colour after `colour` in the cycle, wrapping round to the original.
static func next(colour: StringName) -> StringName:
	return COLOURS[(COLOURS.find(colour) + 1) % COLOURS.size()]


static func _painted(pattern: String, setup: DriftSetup, colour: StringName, fallback: Texture2D) -> Texture2D:
	if colour == ORIGINAL or colour not in COLOURS:
		return fallback
	var path := pattern % [setup.id, colour]
	return load(path) if ResourceLoader.exists(path) else fallback

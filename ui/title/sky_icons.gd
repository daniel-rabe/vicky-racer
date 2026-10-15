class_name SkyIcons
## The pictures on the title's day / night button (docs/DESIGN.md §27), drawn in code: a
## round yellow sun with rays, and a pale crescent moon with two little stars.

const SIZE := 128
const SUN := Color(1.0, 0.82, 0.2)
const SUN_EDGE := Color(0.95, 0.55, 0.12)
const MOON := Color(1.0, 0.95, 0.7)
const MOON_EDGE := Color(0.85, 0.72, 0.35)

static var _sun: Texture2D
static var _moon: Texture2D


static func sun() -> Texture2D:
	if _sun == null:
		var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var centre := Vector2(SIZE, SIZE) * 0.5
		for y in SIZE:
			for x in SIZE:
				var p := Vector2(x + 0.5, y + 0.5) - centre
				var r := p.length()
				var colour := Color(0, 0, 0, 0)
				# Eight rays, round-ended wedges, behind the disc.
				var ray := absf(wrapf(p.angle(), -PI / 8.0, PI / 8.0))
				if r > 38.0 and r < 60.0 and ray < 0.16 * (60.0 - r) / 22.0 + 0.05:
					colour = SUN_EDGE
				if r < 36.0:
					colour = SUN if r < 31.0 else SUN_EDGE
				image.set_pixel(x, y, colour)
		_sun = ImageTexture.create_from_image(image)
	return _sun


static func moon() -> Texture2D:
	if _moon == null:
		var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
		var centre := Vector2(SIZE, SIZE) * 0.5 + Vector2(-6, 0)
		var bite := centre + Vector2(22, -14)
		for y in SIZE:
			for x in SIZE:
				var p := Vector2(x + 0.5, y + 0.5)
				var colour := Color(0, 0, 0, 0)
				var r := p.distance_to(centre)
				var b := p.distance_to(bite)
				if r < 46.0 and b > 38.0:
					colour = MOON if r < 41.0 and b > 43.0 else MOON_EDGE
				for star in [Vector3(100, 30, 9), Vector3(104, 84, 6)]:
					var d := p - Vector2(star.x, star.y)
					if absf(d.x) + absf(d.y) < star.z or d.length() < star.z * 0.45:
						colour = MOON
				image.set_pixel(x, y, colour)
		_moon = ImageTexture.create_from_image(image)
	return _moon

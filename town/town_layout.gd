class_name TownLayout
extends RefCounted
## Free Drive's town, as data (docs/DESIGN.md §19). Streets are a grid: COLS x ROWS blocks
## between straight two-lane roads, every crossing a junction. A road listed in
## REMOVED_ROADS is left out, so the blocks either side of it join into one (the park).
##
## Every building faces down the screen (the roof seen from above, the front wall below
## it), like a picture-book town map. So shops stand along the BOTTOM edge of their block,
## their doors on the pavement of the road below; houses can also stand along the TOP
## edge, their front gardens facing into the block.

const COLS := 5
const ROWS := 4
## Road centre to road centre, px.
const PITCH := 1600.0
const ROAD_HALF := 160.0
const SIDEWALK := 72.0
## Grass between the outer ring road and the edge of the world, px.
const MARGIN := 960.0

## ["h", x, y]: the road from junction (x, y) to (x + 1, y). ["v", x, y]: (x, y) to (x, y + 1).
const REMOVED_ROADS := [["v", 3, 1]]

## What stands in each block, keyed by its top-left cell. bottom / top: building ids from
## art/town/buildings/, spread evenly along that edge. park: the big park's furniture.
## pond / playground: one each in the middle of a block. trees / flowers: trees and flower
## beds, scattered where there is room.
const BLOCKS := {
	Vector2i(0, 0): {"bottom": ["house_red", "house_blue"], "top": ["house_green"], "trees": 3, "flowers": 2},
	Vector2i(1, 0): {"bottom": ["candy_shop", "ice_cream_shop"], "top": ["house_blue", "house_red"], "trees": 2, "flowers": 2},
	Vector2i(2, 0): {"bottom": ["school"], "playground": true, "trees": 3, "flowers": 1},
	Vector2i(3, 0): {"bottom": ["toy_shop", "bakery"], "top": ["house_green", "house_blue"], "trees": 2, "flowers": 2},
	Vector2i(4, 0): {"bottom": ["house_green", "house_red"], "top": ["house_blue"], "trees": 3, "flowers": 2},
	Vector2i(0, 1): {"bottom": ["pet_shop", "flower_shop"], "top": ["house_red", "house_green"], "trees": 2, "flowers": 2},
	Vector2i(1, 1): {"bottom": ["fire_station"], "top": ["house_blue", "house_green"], "trees": 2, "flowers": 1},
	Vector2i(2, 1): {"park": true, "flowers": 1},
	Vector2i(4, 1): {"bottom": ["police_station"], "top": ["house_red"], "trees": 3, "flowers": 2},
	Vector2i(0, 2): {"bottom": ["house_blue", "house_green"], "top": ["house_red"], "trees": 3, "flowers": 2},
	Vector2i(1, 2): {"bottom": ["pizza_place", "candy_shop"], "top": ["house_green", "house_blue"], "trees": 2, "flowers": 2},
	Vector2i(2, 2): {"bottom": ["car_wash"], "top": ["house_green", "house_red"], "trees": 2, "flowers": 1},
	Vector2i(3, 2): {"bottom": ["bakery", "flower_shop"], "top": ["house_red", "house_green"], "trees": 2, "flowers": 2},
	Vector2i(4, 2): {"bottom": ["ice_cream_shop", "pet_shop"], "top": ["house_blue"], "trees": 2, "flowers": 2},
	Vector2i(0, 3): {"pond": true, "trees": 6, "flowers": 1},
	Vector2i(1, 3): {"bottom": ["house_red", "house_blue"], "top": ["house_green", "house_red"], "trees": 2, "flowers": 2},
	Vector2i(2, 3): {"bottom": ["toy_shop", "pizza_place"], "top": ["house_blue"], "trees": 3, "flowers": 2},
	Vector2i(3, 3): {"bottom": ["house_green", "house_red"], "top": ["house_blue", "house_green"], "trees": 2, "flowers": 2},
	Vector2i(4, 3): {"playground": true, "trees": 5, "flowers": 1},
}

## Shown when the player pulls up at the door. Houses have no sign.
const PLACE_NAMES := {
	"candy_shop": "CANDY SHOP",
	"ice_cream_shop": "ICE CREAM",
	"toy_shop": "TOY SHOP",
	"bakery": "BAKERY",
	"pet_shop": "PET SHOP",
	"pizza_place": "PIZZA",
	"flower_shop": "FLOWERS",
	"fire_station": "FIRE STATION",
	"police_station": "POLICE",
	"school": "SCHOOL",
	"car_wash": "CAR WASH",
}


static func junction(cell: Vector2i) -> Vector2:
	return Vector2(MARGIN + cell.x * PITCH, MARGIN + cell.y * PITCH)


static func world_size() -> Vector2:
	return Vector2(2.0 * MARGIN + COLS * PITCH, 2.0 * MARGIN + ROWS * PITCH)


static func is_removed(kind: String, x: int, y: int) -> bool:
	for road: Array in REMOVED_ROADS:
		if road[0] == kind and road[1] == x and road[2] == y:
			return true
	return false

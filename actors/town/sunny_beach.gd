class_name SunnyBeach
extends Node
## What happens on Sunny Beach (docs/DESIGN.md §37; BeachIsland has where things are, Town builds
## the beach, the huts, the sandcastles and the crabs, BeachSurf draws the waves):
##   - a wave coming in pushes every car it catches back up the beach (Vicky on foot too);
##   - the first time across the bridge each drive, SUNNY BEACH comes up; the first wave that
##     catches the player says SPLASH!, and the first sandcastle knocked down says OOPS!

## Of the wave's speed up the beach, how hard it pushes (px/s²).
const PUSH := 900.0

## The town screen (TownScreen): the player, the HUD, the town.
var screen: Node
var arrived := false
var splashed := false
var smashed := false


func _ready() -> void:
	for castle: SandCastle in screen.town.castles:
		castle.knocked.connect(_on_knocked)


func _physics_process(delta: float) -> void:
	var surf: BeachSurf = screen.town.surf
	if surf and surf.rising:
		for car: Car in get_tree().get_nodes_in_group(&"cars"):
			if car is Boat or car.frozen or CarHop.airborne(car) or not BeachIsland.in_wave(car.global_position, surf.front):
				continue
			car.velocity += BeachIsland.inland(car.global_position) * PUSH * delta
			if car == screen.player and not splashed:
				splashed = true
				screen.hud.show_banner("SPLASH!")
	var player: Car = screen.player
	if player and not arrived and BeachIsland.contains(player.global_position):
		arrived = true
		screen.hud.show_banner("SUNNY BEACH")


func _on_knocked(_castle: SandCastle, by: Car) -> void:
	if by == screen.player and not smashed:
		smashed = true
		screen.hud.show_banner("OOPS!")

class_name BeachSurf
extends Node2D
## Sunny Beach's surf (docs/DESIGN.md §37), on the island's west side: every few seconds a wave
## rolls up the sand and runs back. Drawn here, on the ground; SunnyBeach pushes the cars it
## catches back up the beach.

const EVERY := 5.5
## A wave comes in for RISE seconds and goes back out for FALL.
const RISE := 1.8
const FALL := 1.7
const POINTS := 60
const WATER := Color(0.55, 0.84, 0.96, 0.6)
const FOAM := Color(1, 1, 1, 0.92)

var time := 0.0
## How far up the beach the water comes now (px), and whether it is still coming in.
var front := 0.0
var rising := false


func _physics_process(delta: float) -> void:
	time += delta
	var t := fmod(time, EVERY)
	rising = t < RISE
	if t < RISE:
		front = BeachIsland.SURF_DEPTH * sin(t / RISE * PI / 2.0)
	elif t < RISE + FALL:
		front = BeachIsland.SURF_DEPTH * (0.5 + 0.5 * cos((t - RISE) / FALL * PI))
	else:
		front = 0.0
	queue_redraw()


func _draw() -> void:
	if front < 4.0:
		return
	var edge := PackedVector2Array()
	var behind := PackedVector2Array()
	var sea := PackedVector2Array()
	for k in POINTS + 1:
		var a := PI - BeachIsland.SURF_ARC + 2.0 * BeachIsland.SURF_ARC * k / POINTS
		var reach := front * BeachIsland.surf_taper(a)
		edge.append(BeachIsland.shore_point(a, -reach))
		behind.append(BeachIsland.shore_point(a, -reach * 0.55))
		sea.append(BeachIsland.shore_point(a, 60.0))
	var water := edge.duplicate()
	for k in range(sea.size() - 1, -1, -1):
		water.append(sea[k])
	draw_colored_polygon(water, WATER)
	draw_polyline(behind, Color(1, 1, 1, 0.4), 8.0)
	draw_polyline(edge, FOAM, 18.0)

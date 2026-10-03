extends Node
## The persistent shell: loaded once and never unloaded. It will hold the managers that
## must survive screen changes (GarageManager, Phase 5) and swaps screens in and out of
## ScreenSlot. Until the garage exists it opens the test drive.

const FIRST_SCREEN := preload("res://game/screens/test_drive.tscn")

@onready var screen_slot: Node = $ScreenSlot


func _ready() -> void:
	show_screen(FIRST_SCREEN)


func show_screen(scene: PackedScene) -> void:
	for child in screen_slot.get_children():
		child.queue_free()
	screen_slot.add_child(scene.instantiate())

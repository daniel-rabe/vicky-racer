class_name NightKey
extends CanvasLayer
## N (or a gamepad's Back / Select) switches day and night on any screen, paused too
## (docs/DESIGN.md §27). The screen showing a world switches it at once; a sun or a moon pops
## up in the middle for a moment, so the change is seen on the menus as well. Lives in the
## main.tscn shell (main.gd adds it).

var garage: GarageManager

var _picture: TextureRect


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_picture = TextureRect.new()
	_picture.name = "Picture"
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.size = Vector2(SkyIcons.SIZE, SkyIcons.SIZE) * 1.5
	_picture.position = Vector2(960, 900) - _picture.size * 0.5  # under the countdown and the HUD panels
	_picture.pivot_offset = _picture.size * 0.5
	_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_picture.modulate.a = 0.0
	add_child(_picture)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"night") and not event.is_echo():
		get_viewport().set_input_as_handled()
		var night := not garage.night
		EventSystem.PRO_night_requested.emit(night)
		_flash(night)


func _flash(night: bool) -> void:
	_picture.texture = SkyIcons.moon() if night else SkyIcons.sun()
	_picture.modulate.a = 1.0
	_picture.scale = Vector2.ONE * 0.6
	var tween := _picture.create_tween()
	tween.tween_property(_picture, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.7)
	tween.tween_property(_picture, "modulate:a", 0.0, 0.4)

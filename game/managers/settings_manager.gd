class_name SettingsManager
extends Node
## Owns the Settings, applies them (bus volume, window mode) and saves every change at
## once — there is no "apply" button. It also remembers where the window was (remember_window,
## on quit and before going fullscreen) and opens it there again, if that spot is still on a
## screen. In a browser there is no window to remember: the page is the window, and going
## fullscreen needs a click, so the page always opens windowed.
## Lives in the main.tscn shell next to GarageManager.
## Screens talk to it only through EventSystem: UI_settings_requested and
## UI_setting_change_requested in, UI_settings_changed (the whole set) out.

@export var settings_path := Settings.DEFAULT_PATH

var settings: Settings


func _enter_tree() -> void:
	EventSystem.UI_settings_requested.connect(_publish)
	EventSystem.UI_setting_change_requested.connect(change)


func _ready() -> void:
	settings = Settings.load_from(settings_path)
	if OS.has_feature("web"):
		settings.fullscreen = false  # the page always opens windowed, so the toggle shows that
	_apply()
	_restore_window()


func change(key: StringName, value: Variant) -> void:
	if key == &"fullscreen" and value == true:
		remember_window()  # so leaving fullscreen goes back to the same window
	if not settings.set_value(key, value):
		push_warning("ignored setting %s = %s" % [key, value])
		return
	_apply()
	settings.save_to(settings_path)
	_publish()


## Keep the window's place and size, if it is a window (not fullscreen, headless or a web page).
func remember_window() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("web"):
		return
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		return
	var rect := Rect2i(DisplayServer.window_get_position(), DisplayServer.window_get_size())
	if rect != settings.window_rect and settings.set_value(&"window_rect", rect):
		settings.save_to(settings_path)


func _restore_window() -> void:
	var rect := settings.window_rect
	if DisplayServer.get_name() == "headless" or OS.has_feature("web") or settings.fullscreen or not rect.has_area():
		return
	for screen in DisplayServer.get_screen_count():
		# Only where it would still be seen: a monitor may have been unplugged since.
		if DisplayServer.screen_get_usable_rect(screen).has_point(rect.get_center()):
			DisplayServer.window_set_size(rect.size)
			DisplayServer.window_set_position(rect.position)
			return


func _publish() -> void:
	EventSystem.UI_settings_changed.emit(settings.to_dict())


func _apply() -> void:
	_apply_volume(&"SFX", settings.sound_volume)
	_apply_volume(&"Music", settings.music_volume)
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)


func _apply_volume(bus_name: StringName, volume: float) -> void:
	var bus := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(bus, volume <= 0.0)
	AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(volume, 0.001)))

class_name SettingsManager
extends Node
## Owns the Settings, applies them (bus volume, window mode) and saves every change at
## once — there is no "apply" button. Lives in the main.tscn shell next to GarageManager.
## Screens talk to it only through EventSystem: UI_settings_requested and
## UI_setting_change_requested in, UI_settings_changed (the whole set) out.

@export var settings_path := Settings.DEFAULT_PATH

var settings: Settings


func _enter_tree() -> void:
	EventSystem.UI_settings_requested.connect(_publish)
	EventSystem.UI_setting_change_requested.connect(change)


func _ready() -> void:
	settings = Settings.load_from(settings_path)
	_apply()


func change(key: StringName, value: Variant) -> void:
	if not settings.set_value(key, value):
		push_warning("ignored setting %s = %s" % [key, value])
		return
	_apply()
	settings.save_to(settings_path)
	_publish()


func _publish() -> void:
	EventSystem.UI_settings_changed.emit(settings.to_dict())


func _apply() -> void:
	var sfx := AudioServer.get_bus_index(&"SFX")
	AudioServer.set_bus_mute(sfx, settings.sound_volume <= 0.0)
	AudioServer.set_bus_volume_db(sfx, linear_to_db(maxf(settings.sound_volume, 0.001)))
	if DisplayServer.get_name() != "headless":
		var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if settings.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
		if DisplayServer.window_get_mode() != mode:
			DisplayServer.window_set_mode(mode)

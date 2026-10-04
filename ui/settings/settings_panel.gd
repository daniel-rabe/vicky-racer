class_name SettingsPanel
extends Control
## The settings screen (docs/mockups/pause_settings_layout), shown over the title screen
## and over the pause menu. Every change is sent as UI_setting_change_requested and
## applied and saved by SettingsManager straight away — there is no "apply" button.
## B / Escape or BACK closes it.

signal closed

const ROWS := [
	{"key": &"sound_volume", "kind": &"volume", "title": "SOUND", "hint": ""},
	{"key": &"music_volume", "kind": &"volume", "title": "MUSIC", "hint": ""},
	{"key": &"fullscreen", "kind": &"toggle", "title": "FULLSCREEN", "hint": ""},
	{"key": &"auto_accelerate", "kind": &"toggle", "title": "AUTO GO", "hint": "the car drives forward by itself"},
	{"key": &"steering_help", "kind": &"toggle", "title": "STEER HELP", "hint": "gently keeps the car on the road"},
	{"key": &"difficulty", "kind": &"choice", "title": "OPPONENTS", "hint": "EASY / NORMAL / FAST"},
]

var _settings := {}
var _rows := {}  # key -> SettingsRow

@onready var _list: VBoxContainer = %Rows
@onready var _back: Button = %Back


func _enter_tree() -> void:
	EventSystem.UI_settings_changed.connect(_on_settings_changed)


func _ready() -> void:
	for spec: Dictionary in ROWS:
		var row := SettingsRow.new()
		row.setup(spec["key"], spec["kind"], spec["title"], spec["hint"])
		row.stepped.connect(_on_stepped)
		_list.add_child(row)
		_rows[spec["key"]] = row
	_back.pressed.connect(close)
	visible = false


func open() -> void:
	visible = true
	EventSystem.UI_settings_requested.emit()
	_rows[ROWS[0]["key"]].grab_focus()


func close() -> void:
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()


func _on_settings_changed(settings: Dictionary) -> void:
	_settings = settings
	for key in _rows:
		_rows[key].show_value(settings[String(key)])


func _on_stepped(key: StringName, direction: int) -> void:
	if _settings.is_empty():
		return
	var value: Variant = _settings[String(key)]
	match _rows[key].kind:
		&"volume":
			# Left / right stop at the ends; a press steps up and wraps round to silent, so
			# A or a click alone can reach every level.
			if direction == 0:
				value = 0.0 if float(value) >= 1.0 - 0.01 else float(value) + Settings.VOLUME_STEP
			else:
				value = clampf(float(value) + direction * Settings.VOLUME_STEP, 0.0, 1.0)
		&"toggle":
			value = not value
		&"choice":
			var i := Settings.DIFFICULTIES.find(StringName(value))
			var step := direction if direction != 0 else 1
			value = Settings.DIFFICULTIES[posmod(i + step, Settings.DIFFICULTIES.size())]
	EventSystem.UI_setting_change_requested.emit(key, value)

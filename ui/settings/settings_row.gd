class_name SettingsRow
extends Button
## One line of the settings panel (docs/mockups/pause_settings_layout): a title, an
## optional hint and the current value. The whole row takes focus, so a gamepad moves
## up and down rows and changes the focused one with left / right (or A for toggles and
## choices). It only reports the step; the panel turns it into a setting change.

## direction: -1 / 1 for left / right, 0 for a press (A, Enter or a click).
signal stepped(key: StringName, direction: int)

const YELLOW := Color(1, 0.824, 0.247)
const DIM := Color(0.624, 0.69, 0.769)
const ON_COLOUR := Color(0.18, 0.769, 0.42)
const OFF_COLOUR := Color(0.227, 0.29, 0.369)
const DARK := Color(0.055, 0.078, 0.11)

var key: StringName
var kind: StringName  ## &"volume", &"toggle" or &"choice"

var _bar: ProgressBar
var _pill: PanelContainer
var _pill_label: Label
var _choice: Label


func setup(row_key: StringName, row_kind: StringName, title: String, hint: String) -> void:
	key = row_key
	kind = row_kind
	name = String(row_key).to_pascal_case()
	theme_type_variation = &"SettingsRow"
	custom_minimum_size = Vector2(880, 96)
	var line := HBoxContainer.new()
	line.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	line.offset_left = 28
	line.offset_right = -28
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(line)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 8)
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.add_child(words)
	words.add_child(_label(title, 30, Color.WHITE))
	if not hint.is_empty():
		words.add_child(_label(hint, 16, DIM))
	match kind:
		&"volume":
			_bar = ProgressBar.new()
			_bar.custom_minimum_size = Vector2(420, 36)
			_bar.max_value = 1.0
			_bar.show_percentage = false
			_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
			line.add_child(_bar)
		&"toggle":
			_pill = PanelContainer.new()
			_pill.custom_minimum_size = Vector2(160, 56)
			_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_pill_label = _label("OFF", 26, Color.WHITE)
			_pill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			_pill.add_child(_pill_label)
			line.add_child(_pill)
		&"choice":
			_choice = _label("", 30, YELLOW)
			line.add_child(_choice)


func show_value(value: Variant) -> void:
	match kind:
		&"volume":
			_bar.value = float(value)
		&"toggle":
			_pill_label.text = "ON" if value else "OFF"
			var style := StyleBoxFlat.new()
			style.bg_color = ON_COLOUR if value else OFF_COLOUR
			style.set_corner_radius_all(28)
			style.set_border_width_all(4)
			style.border_color = DARK
			_pill.add_theme_stylebox_override("panel", style)
		&"choice":
			_choice.text = "<  %s  >" % String(value).to_upper()


func _ready() -> void:
	pressed.connect(func() -> void: stepped.emit(key, 0))


func _gui_input(event: InputEvent) -> void:
	# Left / right change the value instead of moving focus sideways.
	if event.is_action_pressed("ui_left", true):
		stepped.emit(key, -1)
		accept_event()
	elif event.is_action_pressed("ui_right", true):
		stepped.emit(key, 1)
		accept_event()


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", DARK)
	label.add_theme_constant_override("outline_size", 6 if font_size >= 26 else 0)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

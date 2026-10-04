extends Control
## Cup standings between races (docs/DESIGN.md §12, docs/mockups/cup_layout): the four
## racers by points, each row showing the points just won counting up into the total.
## NEXT RACE goes on (PODIUM! after the last race); B / GARAGE leaves, and the cup waits.

const YELLOW := Color(1, 0.824, 0.247)
const DIM := Color(0.624, 0.69, 0.769)
const DARK := Color(0.055, 0.078, 0.11)
const COUNT_SECONDS := 1.0

var _cup := {}

@onready var _icon: TextureRect = %Icon
@onready var _title: Label = %Title
@onready var _subtitle: Label = %Subtitle
@onready var _rows: VBoxContainer = %Rows
@onready var _next: Button = %Next
@onready var _garage: Button = %Garage


func _enter_tree() -> void:
	EventSystem.CUP_state_changed.connect(func(state: Dictionary) -> void: _cup = state)


func _ready() -> void:
	EventSystem.CUP_state_requested.emit()
	_garage.pressed.connect(func() -> void: EventSystem.UI_screen_requested.emit(&"garage"))
	_next.pressed.connect(func() -> void: EventSystem.CUP_continue_requested.emit())
	if _cup.is_empty() or _cup["cup"] == null:
		_title.text = "NO CUP"
		_next.disabled = true
		_garage.grab_focus()
		return
	var cup: CupConfig = _cup["cup"]
	var done: bool = _cup["phase"] == &"done"
	_icon.texture = cup.icon
	_title.text = cup.display_name.to_upper()
	_subtitle.text = "AFTER RACE %d OF %d" % [_cup["race_index"], cup.tracks.size()]
	_next.text = "PODIUM!" if done else "NEXT RACE"
	var tween := create_tween()
	for row_data: Dictionary in _cup["standings"]:
		var row := _make_row(row_data)
		row.modulate.a = 0.0
		_rows.add_child(row)
		tween.tween_property(row, "modulate:a", 1.0, 0.15)
	tween.tween_interval(0.2)
	tween.set_parallel()
	for i in _rows.get_child_count():
		var data: Dictionary = _cup["standings"][i]
		var total: Label = _rows.get_child(i).get_meta(&"total")
		tween.tween_method(func(v: float) -> void: total.text = str(roundi(v)),
			float(data["points"] - data["gained"]), float(data["points"]), COUNT_SECONDS)
	_next.grab_focus()


func _make_row(data: Dictionary) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(1100, 112)
	if data["is_player"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.118, 0.165, 0.227)
		style.border_color = YELLOW
		style.set_border_width_all(6)
		style.set_corner_radius_all(28)
		style.set_content_margin_all(22)
		row.add_theme_stylebox_override("panel", style)
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 36)
	row.add_child(line)
	line.add_child(_label(str(data["position"]), 52, Color.WHITE))
	var car := TextureRect.new()
	if ResourceLoader.exists(data["body"]):
		car.texture = load(data["body"])
	car.custom_minimum_size = Vector2(128, 72)
	car.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	car.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	line.add_child(car)
	var name_label := _label(data["name"], 34, YELLOW if data["is_player"] else Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	line.add_child(_label("+%d" % data["gained"], 30, YELLOW))
	var total := _label("0", 44, Color.WHITE)
	total.custom_minimum_size = Vector2(110, 0)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(total)
	line.add_child(_label("PTS", 20, DIM))
	row.set_meta(&"total", total)
	return row


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", DARK)
	label.add_theme_constant_override("outline_size", 6)
	return label


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		EventSystem.UI_screen_requested.emit(&"garage")
		get_viewport().set_input_as_handled()

extends Control
## End of race (docs/mockups/results_layout): the finishing order slides in row by row,
## then the coin payout lines appear and the total counts up. Only then do GARAGE and
## RACE AGAIN become usable, with RACE AGAIN focused. The headline is always cheerful.

const ROW_INTERVAL := 0.15
const COUNT_UP_SECONDS := 1.2
const ORDINALS := {1: "1ST", 2: "2ND", 3: "3RD", 4: "4TH"}
const BREAKDOWN_LABELS := {"place": "%s PLACE", "first_finish": "FIRST FINISH"}
const YELLOW := Color(1, 0.824, 0.247)
const DIM := Color(0.624, 0.69, 0.769)
const COIN := preload("res://art/sfx/coin.wav")

@onready var _headline: Label = %Headline
@onready var _rows: VBoxContainer = %Rows
@onready var _lines: VBoxContainer = %Lines
@onready var _total: Label = %Total
@onready var _balance: Label = %Balance
@onready var _garage: Button = %Garage
@onready var _again: Button = %Again

var _state := {}


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(func(state: Dictionary) -> void: _state = state)


func _ready() -> void:
	for button in [_garage, _again]:
		button.disabled = true
		button.focus_mode = Control.FOCUS_NONE
	_garage.pressed.connect(func() -> void: EventSystem.UI_screen_requested.emit(&"garage"))
	_again.pressed.connect(func() -> void: EventSystem.UI_screen_requested.emit(&"race"))
	EventSystem.PRO_state_requested.emit()
	var race: Dictionary = _state.get("last_race", {})
	if race.is_empty():
		_headline.text = "NO RACE YET"
		_enable_buttons()
		return
	_play(race)


func _play(race: Dictionary) -> void:
	var player_position := 0
	for entry: Dictionary in race["results"]:
		if entry["is_player"]:
			player_position = entry["position"]
	_headline.text = "YOU WON!" if player_position == 1 else "YOU CAME %s!" % ORDINALS.get(player_position, "")
	_total.text = "+0"
	_balance.text = "TOTAL %d" % (int(_state["coins"]) - int(race["amount"]))

	var tween := create_tween()
	for entry: Dictionary in race["results"]:
		var row := _make_row(entry, entry["is_player"] and race["new_best_lap"])
		row.modulate.a = 0.0
		_rows.add_child(row)
		tween.tween_property(row, "modulate:a", 1.0, ROW_INTERVAL)
	tween.tween_interval(0.3)
	for key: String in race["breakdown"]:
		var line := _make_line(key, int(race["breakdown"][key]), player_position)
		line.modulate.a = 0.0
		_lines.add_child(line)
		tween.tween_property(line, "modulate:a", 1.0, 0.2)
	tween.tween_callback(_chime)
	tween.tween_method(func(v: float) -> void: _total.text = "+%d" % roundi(v), 0.0, float(race["amount"]), COUNT_UP_SECONDS)
	tween.tween_callback(func() -> void: _balance.text = "TOTAL %d" % int(_state["coins"]))
	tween.tween_callback(_enable_buttons)


func _make_row(entry: Dictionary, best_lap: bool) -> PanelContainer:
	var row := PanelContainer.new()
	row.custom_minimum_size = Vector2(1000, 112)
	if entry["is_player"]:
		row.add_theme_stylebox_override("panel", _player_row_style())
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 36)
	row.add_child(line)
	line.add_child(_label(str(entry["position"]), 52))
	var car := TextureRect.new()
	car.texture = load(entry["body"])
	car.custom_minimum_size = Vector2(128, 72)
	car.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	car.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	line.add_child(car)
	var name_label := _label(entry["name"], 34, YELLOW if entry["is_player"] else Color.WHITE)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	if best_lap:
		line.add_child(_label("BEST LAP!", 18, Color(0.18, 0.769, 0.42)))
	var times := VBoxContainer.new()
	times.custom_minimum_size = Vector2(220, 0)
	times.add_child(_label("TIME", 20, DIM))
	times.add_child(_label(_format_time(entry["time"]), 28))
	line.add_child(times)
	return row


## The theme's panel with a thick yellow border. Built explicitly: a row that is not in
## the tree yet would hand back Godot's default stylebox, not the theme's.
func _player_row_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.118, 0.165, 0.227)
	style.border_color = YELLOW
	style.set_border_width_all(6)
	style.set_corner_radius_all(28)
	style.set_content_margin_all(22)
	style.content_margin_left = 24
	style.content_margin_right = 24
	return style


func _make_line(key: String, amount: int, player_position: int) -> HBoxContainer:
	var line := HBoxContainer.new()
	var text: String = BREAKDOWN_LABELS.get(key, key.to_upper())
	if "%s" in text:
		text = text % ORDINALS.get(player_position, "")
	var name_label := _label(text, 26)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	line.add_child(_label("+%d" % amount, 30, YELLOW))
	return line


func _label(text: String, size: int, colour := Color.WHITE) -> Label:
	var label := Label.new()
	label.text = text
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", colour)
	return label


func _enable_buttons() -> void:
	for button in [_garage, _again]:
		button.disabled = false
		button.focus_mode = Control.FOCUS_ALL
	_again.grab_focus()


static func _format_time(seconds: float) -> String:
	return "%d:%05.2f" % [int(seconds) / 60, fmod(seconds, 60.0)]


## The payout count-up gets the coin chime, so earning is something you hear.
func _chime() -> void:
	if not SoundManager.audible():
		return
	var player := AudioStreamPlayer.new()
	player.stream = COIN
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)

extends Control
## Pick a race, between the garage and a race (docs/DESIGN.md §10): a row of track cards (the
## last track raced focused) and, below, the cups (§12). A cup opens when the one before it
## has been won; the cup in progress offers CONTINUE. A locked card shakes and says which track to finish first. Choosing
## a track goes through EventSystem (PRO_track_select_requested), then straight to the race.
## Above the cards, RACE / TIME TRIAL switches what choosing a track means (docs/DESIGN.md
## §16): in a time trial the cards show each track's record, and the cups make way.
## B / Escape goes back to the garage. In a two-player game (§15) there are no cups — they
## belong to the one player's progress — and B goes back to the join screen.

const HINTS_KEYBOARD := "ENTER RACE    ESC BACK"
const HINTS_GAMEPAD := "A RACE    B BACK"
const MODES: Array[StringName] = [&"race", &"time_trial"]
const MODE_NAMES := {&"race": "RACE", &"time_trial": "TIME TRIAL"}

var _cards := {}  # track id -> TrackCard
var _cup_cards := {}  # cup id -> CupCard
var _cup := {}
var _two_player := false
var _mode: StringName = &"race"
var _trials := {}
var _tabs := {}  # mode -> Button
var _gamepad := false

@onready var _row: HBoxContainer = %Cards
@onready var _cups_row: HBoxContainer = %Cups
@onready var _message: Label = %Message
@onready var _hints: Label = %Hints


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_state_changed)
	EventSystem.PRO_track_locked.connect(_on_locked)
	EventSystem.CUP_state_changed.connect(func(state: Dictionary) -> void: _cup = state)
	EventSystem.PLY_state_changed.connect(func(state: Dictionary) -> void: _two_player = state["two_player"])


func _ready() -> void:
	_message.modulate.a = 0.0
	_hints.text = HINTS_KEYBOARD
	EventSystem.PRO_state_requested.emit()
	EventSystem.CUP_state_requested.emit()
	EventSystem.PLY_state_requested.emit()
	if _two_player:
		_cups_row.visible = false
		$CupsTitle.visible = false
	else:
		_build_cups()
		_build_tabs()
	_show_mode()


func _on_state_changed(state: Dictionary) -> void:
	_trials = state.get("trials", {})
	if not _two_player:
		_mode = state.get("race_mode", &"race")
	if not _cards.is_empty():
		return
	var entries: Array = state["tracks"]
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var card := TrackCard.new()
		var opened_by: String = entries[i - 1]["config"].display_name if i > 0 else ""
		card.setup(entry["config"], entry["unlocked"], entry["best_lap"], entry["completed"], opened_by)
		card.chosen.connect(_on_chosen)
		_row.add_child(card)
		_cards[entry["config"].track_id] = card
	var selected: TrackCard = _cards.get(state.get("selected_track"))
	if selected:
		selected.grab_focus()
		_scroll_into_view(selected)


## The row scrolls with the focus, but not before it has been laid out once: the card focused
## on opening (the last track raced) may be off to the right.
func _scroll_into_view(card: Control) -> void:
	await get_tree().process_frame
	if is_instance_valid(card):
		($CardsScroll as ScrollContainer).ensure_control_visible(card)


func _on_chosen(config: TrackConfig) -> void:
	if not _cards[config.track_id].unlocked:
		EventSystem.PRO_track_select_requested.emit(config.track_id)  # refused: PRO_track_locked
		return
	EventSystem.PRO_track_select_requested.emit(config.track_id)
	EventSystem.PRO_race_mode_requested.emit(&"race" if _two_player else _mode)
	EventSystem.UI_screen_requested.emit(&"race")


func _build_cups() -> void:
	var entries: Array = _cup["cups"]
	for i in entries.size():
		var entry: Dictionary = entries[i]
		var cup: CupConfig = entry["config"]
		var running := 0
		if _cup["cup"] == cup and _cup["phase"] in [&"ready", &"results", &"racing"]:
			running = _cup["race_index"] + 1
		var card := CupCard.new()
		var previous: String = entries[i - 1]["config"].display_name if i > 0 else ""
		card.setup(cup, entry["unlocked"], entry["trophy"], running, previous)
		card.chosen.connect(_on_cup_chosen)
		_cups_row.add_child(card)
		_cup_cards[cup.id] = card


func _on_cup_chosen(cup: CupConfig) -> void:
	var card: CupCard = _cup_cards[cup.id]
	EventSystem.PRO_race_mode_requested.emit(&"race")  # a cup is always a race
	if not card.unlocked:
		_shake(card, "WIN THE %s FIRST!" % card.opened_by.to_upper())
	elif _cup["cup"] == cup and _cup["phase"] in [&"ready", &"results"]:
		EventSystem.CUP_continue_requested.emit()
	else:
		EventSystem.CUP_start_requested.emit(cup.id)


## RACE | TIME TRIAL, top right. Up from the cards reaches them; choosing one switches mode.
func _build_tabs() -> void:
	var row := HBoxContainer.new()
	row.name = "Modes"
	row.add_theme_constant_override("separation", 24)
	row.position = Vector2(1040, 52)
	row.size = Vector2(832, 84)
	row.alignment = BoxContainer.ALIGNMENT_END
	add_child(row)
	for mode in MODES:
		var tab := Button.new()
		tab.name = String(mode).to_pascal_case()
		tab.text = MODE_NAMES[mode]
		tab.custom_minimum_size = Vector2(440 if mode == &"time_trial" else 220, 84)
		tab.pressed.connect(func() -> void:
			_mode = mode
			EventSystem.PRO_race_mode_requested.emit(mode)
			_show_mode())
		row.add_child(tab)
		_tabs[mode] = tab


## Cards, cups and tabs as the mode says: the chosen tab green, records on the cards in a
## time trial, and no cups (a cup is always a race).
func _show_mode() -> void:
	for mode: StringName in _tabs:
		_tabs[mode].theme_type_variation = &"RaceButton" if mode == _mode else &"NavButton"
	var trial := _mode == &"time_trial" and not _two_player
	for id: StringName in _cards:
		_cards[id].show_mode(trial, float(_trials.get(id, {}).get("best", 0.0)))
	if not _two_player:
		_cups_row.visible = not trial
		$CupsTitle.visible = not trial
	_update_hints()


func _on_locked(track_id: StringName) -> void:
	var card: TrackCard = _cards[track_id]
	_shake(card, "FINISH %s FIRST!" % card.opened_by.to_upper())


func _shake(card: Control, message: String) -> void:
	var tween := create_tween()
	var home := card.position.x
	for offset in [12.0, -10.0, 7.0, -4.0, 0.0]:
		tween.tween_property(card, "position:x", home + offset, 0.05)
	_message.text = message
	var flash := create_tween()
	flash.tween_property(_message, "modulate:a", 1.0, 0.15)
	flash.tween_interval(2.0)
	flash.tween_property(_message, "modulate:a", 0.0, 0.4)


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_gamepad = true
		_update_hints()
	elif event is InputEventKey:
		_gamepad = false
		_update_hints()


func _update_hints() -> void:
	var hints := HINTS_GAMEPAD if _gamepad else HINTS_KEYBOARD
	_hints.text = hints.replace("RACE", "DRIVE") if _mode == &"time_trial" and not _two_player else hints


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		EventSystem.UI_screen_requested.emit(&"join" if _two_player else &"garage")
		get_viewport().set_input_as_handled()

extends Control
## Pick a race, between the garage and a race (docs/DESIGN.md §10): four track cards (the
## last track raced focused) and, below, the cups (§12). A cup opens when the one before it
## has been won; the cup in progress offers CONTINUE. A locked card shakes and says which track to finish first. Choosing
## a track goes through EventSystem (PRO_track_select_requested), then straight to the race.
## B / Escape goes back to the garage.

const HINTS_KEYBOARD := "ENTER RACE    ESC BACK"
const HINTS_GAMEPAD := "A RACE    B BACK"

var _cards := {}  # track id -> TrackCard
var _cup_cards := {}  # cup id -> CupCard
var _cup := {}

@onready var _row: HBoxContainer = %Cards
@onready var _cups_row: HBoxContainer = %Cups
@onready var _message: Label = %Message
@onready var _hints: Label = %Hints


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_state_changed)
	EventSystem.PRO_track_locked.connect(_on_locked)
	EventSystem.CUP_state_changed.connect(func(state: Dictionary) -> void: _cup = state)


func _ready() -> void:
	_message.modulate.a = 0.0
	_hints.text = HINTS_KEYBOARD
	EventSystem.PRO_state_requested.emit()
	EventSystem.CUP_state_requested.emit()
	_build_cups()


func _on_state_changed(state: Dictionary) -> void:
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


func _on_chosen(config: TrackConfig) -> void:
	if not _cards[config.track_id].unlocked:
		EventSystem.PRO_track_select_requested.emit(config.track_id)  # refused: PRO_track_locked
		return
	EventSystem.PRO_track_select_requested.emit(config.track_id)
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
	if not card.unlocked:
		_shake(card, "WIN THE %s FIRST!" % card.opened_by.to_upper())
	elif _cup["cup"] == cup and _cup["phase"] in [&"ready", &"results"]:
		EventSystem.CUP_continue_requested.emit()
	else:
		EventSystem.CUP_start_requested.emit(cup.id)


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
		_hints.text = HINTS_GAMEPAD
	elif event is InputEventKey:
		_hints.text = HINTS_KEYBOARD


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		EventSystem.UI_screen_requested.emit(&"garage")
		get_viewport().set_input_as_handled()

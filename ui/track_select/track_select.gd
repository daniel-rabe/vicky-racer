extends Control
## Track select, between the garage and a race (docs/DESIGN.md §10): four cards, the last
## track raced focused. A locked card shakes and says which track to finish first. Choosing
## a track goes through EventSystem (PRO_track_select_requested), then straight to the race.
## B / Escape goes back to the garage.

const HINTS_KEYBOARD := "ENTER RACE    ESC BACK"
const HINTS_GAMEPAD := "A RACE    B BACK"

var _cards := {}  # track id -> TrackCard

@onready var _row: HBoxContainer = %Cards
@onready var _message: Label = %Message
@onready var _hints: Label = %Hints


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_state_changed)
	EventSystem.PRO_track_locked.connect(_on_locked)


func _ready() -> void:
	_message.modulate.a = 0.0
	_hints.text = HINTS_KEYBOARD
	EventSystem.PRO_state_requested.emit()


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


func _on_locked(track_id: StringName) -> void:
	var card: TrackCard = _cards[track_id]
	var tween := create_tween()
	var home := card.position.x
	for offset in [12.0, -10.0, 7.0, -4.0, 0.0]:
		tween.tween_property(card, "position:x", home + offset, 0.05)
	_message.text = "FINISH %s FIRST!" % card.opened_by.to_upper()
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

extends Control
## The garage (docs/mockups/garage_layout): coin balance, a 3 x 2 grid of setup cards, a
## preview with Grip / Slide / Speed bars that follows the focused card, and RACE!.
## Everything goes through EventSystem: it asks GarageManager for the state and sends
## buy / equip requests; it never touches the manager itself.

const CARD_SCENE := preload("res://ui/garage/setup_card.tscn")
const MESSAGE_SECONDS := 2.2
const HINTS_KEYBOARD := "ENTER  BUY / EQUIP      R  RACE      ESC  BACK"
const HINTS_GAMEPAD := "A  BUY / EQUIP      Y  RACE      B  BACK"

var _state := {}
var _cards := {}  # setup id -> SetupCard
var _shown_coins := 0.0

@onready var _coins: Label = %Coins
@onready var _grid: GridContainer = %Cards
@onready var _preview_art: TextureRect = %PreviewArt
@onready var _preview_caption: Label = %PreviewCaption
@onready var _preview_name: Label = %PreviewName
@onready var _bar_grip: ProgressBar = %BarGrip
@onready var _bar_slide: ProgressBar = %BarSlide
@onready var _bar_speed: ProgressBar = %BarSpeed
@onready var _message: Label = %Message
@onready var _hints: Label = %Hints
@onready var _race: Button = %Race


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(_on_state_changed)
	EventSystem.PRO_purchase_refused.connect(_on_purchase_refused)
	EventSystem.PRO_setup_purchased.connect(_on_setup_purchased)


func _ready() -> void:
	_race.pressed.connect(_start_race)
	_message.modulate.a = 0.0
	EventSystem.PRO_state_requested.emit()
	var equipped: SetupCard = _cards.get(_state.get("equipped"))
	if equipped:
		equipped.grab_focus()


func _on_state_changed(state: Dictionary) -> void:
	_state = state
	_count_coins_to(state["coins"])
	for setup: DriftSetup in state["setups"]:
		var card: SetupCard = _cards.get(setup.id)
		if card == null:
			card = CARD_SCENE.instantiate()
			_grid.add_child(card)
			_cards[setup.id] = card
			card.chosen.connect(_on_card_chosen)
			card.focus_entered.connect(_show_preview.bind(setup))
		var owned: bool = setup.id in state["owned"]
		card.show_setup(setup, owned, setup.id == state["equipped"], state["coins"] >= setup.price)
	var focused := get_viewport().gui_get_focus_owner() as SetupCard
	_show_preview(focused.setup if focused else state["setups"].filter(
		func(s: DriftSetup) -> bool: return s.id == state["equipped"])[0])


func _on_card_chosen(setup: DriftSetup) -> void:
	if setup.id in _state["owned"]:
		EventSystem.PRO_equip_requested.emit(setup.id)
	else:
		EventSystem.PRO_buy_requested.emit(setup.id)


func _on_purchase_refused(setup_id: StringName, _reason: StringName) -> void:
	var card: SetupCard = _cards[setup_id]
	card.shake()
	_flash("NEED %d MORE COINS!" % (card.setup.price - int(_state["coins"])))


func _on_setup_purchased(setup_id: StringName) -> void:
	_cards[setup_id].pop()
	_flash("YOU GOT %s!" % _cards[setup_id].setup.display_name.to_upper())


func _show_preview(setup: DriftSetup) -> void:
	_preview_art.texture = setup.card_art
	_preview_name.text = setup.display_name.to_upper()
	var equipped: bool = setup.id == _state.get("equipped")
	var owned: bool = setup.id in _state.get("owned", [])
	_preview_caption.text = "EQUIPPED" if equipped else ("OWNED" if owned else "%d COINS" % setup.price)
	var tween := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_bar_grip, "value", setup.bar_grip, 0.3)
	tween.tween_property(_bar_slide, "value", setup.bar_slide, 0.3)
	tween.tween_property(_bar_speed, "value", setup.bar_speed, 0.3)


func _count_coins_to(target: int) -> void:
	var tween := create_tween()
	tween.tween_method(func(v: float) -> void:
		_shown_coins = v
		_coins.text = str(roundi(v)), _shown_coins, float(target), 0.5)


func _flash(text: String) -> void:
	_message.text = text
	var tween := create_tween()
	tween.tween_property(_message, "modulate:a", 1.0, 0.15)
	tween.tween_interval(MESSAGE_SECONDS)
	tween.tween_property(_message, "modulate:a", 0.0, 0.4)


func _start_race() -> void:
	EventSystem.UI_screen_requested.emit(&"race")


func _input(event: InputEvent) -> void:
	# Show the controls for whichever device was used last.
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_hints.text = HINTS_GAMEPAD
	elif event is InputEventKey:
		_hints.text = HINTS_KEYBOARD


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("race_start"):
		_start_race()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		EventSystem.UI_screen_requested.emit(&"title")
		get_viewport().set_input_as_handled()

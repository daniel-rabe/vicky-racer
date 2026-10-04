extends Control
## The garage (docs/mockups/garage_layout): coin balance, the cars as cards in pages of
## 3 x 2, a preview with Grip / Slide / Speed bars and paint swatches that follows the
## focused card, and RACE!. Q / E or the shoulder buttons turn the page, and so does
## moving left or right off the edge of one. X / C paints the focused car the next colour.
## Everything goes through EventSystem: it asks GarageManager for the state and sends
## buy / equip / paint requests; it never touches the manager itself.

const CARD_SCENE := preload("res://ui/garage/setup_card.tscn")
const MESSAGE_SECONDS := 2.2
const HINTS_KEYBOARD := "ENTER BUY  C PAINT  Q/E PAGE  R RACE  ESC BACK"
const HINTS_GAMEPAD := "A BUY  X PAINT  LB/RB PAGE  Y RACE  B BACK"
const PAGE_SIZE := 6
const COLUMNS := 3
const SWATCH := 44
const YELLOW := Color(1, 0.824, 0.247)

var _state := {}
var _cards := {}  # setup id -> SetupCard
var _shown_coins := 0.0
var _order: Array[StringName] = []  # setup ids in display order
var _page := 0
var _page_label: Label
var _swatches: HBoxContainer

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
	EventSystem.PRO_setup_painted.connect(func(id: StringName, _colour: StringName) -> void:
		if _cards.has(id):
			_cards[id].pop())
	EventSystem.PRO_purchase_refused.connect(_on_purchase_refused)
	EventSystem.PRO_setup_purchased.connect(_on_setup_purchased)


func _ready() -> void:
	_race.pressed.connect(_start_race)
	_message.modulate.a = 0.0
	_hints.text = HINTS_KEYBOARD
	_build_page_label()
	_build_swatches()
	EventSystem.PRO_state_requested.emit()
	var equipped: SetupCard = _cards.get(_state.get("equipped"))
	if equipped:
		_show_page(_order.find(equipped.setup.id) / PAGE_SIZE)
		equipped.grab_focus()


func _on_state_changed(state: Dictionary) -> void:
	_state = state
	_count_coins_to(state["coins"])
	var paint: Dictionary = state.get("paint", {})
	for setup: DriftSetup in state["setups"]:
		var card: SetupCard = _cards.get(setup.id)
		if card == null:
			card = CARD_SCENE.instantiate()
			_grid.add_child(card)
			_cards[setup.id] = card
			_order.append(setup.id)
			card.chosen.connect(_on_card_chosen)
			card.focus_entered.connect(_show_preview.bind(setup))
		var owned: bool = setup.id in state["owned"]
		var art := Paint.card(setup, paint.get(setup.id, Paint.ORIGINAL))
		card.show_setup(setup, art, owned, setup.id == state["equipped"], state["coins"] >= setup.price)
	_show_page(_page)
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
	var colour: StringName = _state.get("paint", {}).get(setup.id, Paint.ORIGINAL)
	_preview_art.texture = Paint.card(setup, colour)
	_show_swatches(setup, colour)
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
	EventSystem.UI_screen_requested.emit(&"tracks")


## Show the controls for whichever device was used last.
func _update_hints(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_hints.text = HINTS_GAMEPAD
	elif event is InputEventKey:
		_hints.text = HINTS_KEYBOARD


## Paging comes before focus navigation, so left / right off the edge of a page turn it.
func _input(event: InputEvent) -> void:
	_update_hints(event)
	var card := get_viewport().gui_get_focus_owner() as SetupCard
	if card == null:
		return
	var index := _order.find(card.setup.id)
	var column := index % PAGE_SIZE % COLUMNS
	if event.is_action_pressed("page_next"):
		_turn_page(1, index, false)
	elif event.is_action_pressed("page_prev"):
		_turn_page(-1, index, false)
	elif event.is_action_pressed("ui_right") and column == COLUMNS - 1 and _page < (_order.size() - 1) / PAGE_SIZE:
		_turn_page(1, index, true)
	elif event.is_action_pressed("ui_left") and column == 0 and _page > 0:
		_turn_page(-1, index, true)
	elif event.is_action_pressed("paint"):
		if card.setup.id in _state.get("owned", []):
			EventSystem.PRO_paint_requested.emit(card.setup.id)
		else:
			card.shake()
			_flash("BUY IT FIRST!")
	else:
		return
	get_viewport().set_input_as_handled()


## Go to the next / previous page. Moving off the edge of a page lands on the near edge of
## the next one, in the same row; Q / E keep the same place on the page.
func _turn_page(step: int, from_index: int, off_edge: bool) -> void:
	var pages := ceili(_order.size() / float(PAGE_SIZE))
	var page := _page + step
	if page < 0 or page >= pages:
		return
	_show_page(page)
	var slot := from_index % PAGE_SIZE
	var column := slot % COLUMNS
	if off_edge:
		column = 0 if step > 0 else COLUMNS - 1
	var target := mini(page * PAGE_SIZE + slot / COLUMNS * COLUMNS + column, _order.size() - 1)
	_cards[_order[target]].grab_focus()


func _show_page(page: int) -> void:
	_page = page
	for i in _order.size():
		_cards[_order[i]].visible = i / PAGE_SIZE == page
	var pages := ceili(_order.size() / float(PAGE_SIZE))
	_page_label.visible = pages > 1
	_page_label.text = "%s  %d / %d  %s" % ["<" if page > 0 else " ", page + 1, pages, ">" if page < pages - 1 else " "]


func _build_page_label() -> void:
	_page_label = Label.new()
	_page_label.position = Vector2(736, 112)
	_page_label.size = Vector2(1136, 48)
	_page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_page_label.add_theme_font_size_override("font_size", 30)
	_page_label.add_theme_color_override("font_color", YELLOW)
	add_child(_page_label)


## A row of paint swatches under the bars: the car's own paint first, then the palette.
func _build_swatches() -> void:
	_swatches = HBoxContainer.new()
	_swatches.alignment = BoxContainer.ALIGNMENT_CENTER
	_swatches.add_theme_constant_override("separation", 14)
	_bar_speed.get_parent().get_parent().add_child(_swatches)
	for colour in Paint.COLOURS:
		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(SWATCH, SWATCH)
		swatch.set_meta(&"colour", colour)
		_swatches.add_child(swatch)


func _show_swatches(setup: DriftSetup, current: StringName) -> void:
	_swatches.visible = setup.id in _state.get("owned", [])
	for swatch: Panel in _swatches.get_children():
		var colour: StringName = swatch.get_meta(&"colour")
		var style := StyleBoxFlat.new()
		style.bg_color = Paint.SWATCHES.get(colour, Color(0.9, 0.9, 0.9))
		style.set_corner_radius_all(SWATCH / 2)
		style.set_border_width_all(6 if colour == current else 3)
		style.border_color = YELLOW if colour == current else Color(0.055, 0.078, 0.11)
		if colour == Paint.ORIGINAL:
			# The car's own paint: a two-tone disc, since it is not one colour.
			style.bg_color = Color(0.93, 0.93, 0.91)
			style.border_color = YELLOW if colour == current else Color(0.902, 0.224, 0.275)
		swatch.add_theme_stylebox_override("panel", style)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("race_start"):
		_start_race()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		EventSystem.UI_screen_requested.emit(&"title")
		get_viewport().set_input_as_handled()

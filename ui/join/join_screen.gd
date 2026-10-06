extends Control
## Two players join (docs/DESIGN.md §15), from 2 PLAYERS on the title. Each player claims a
## device by pressing its button: A on a gamepad, SPACE for the left half of the keyboard
## (W A S D), ENTER for the right half (the arrow keys). The first to press is player 1.
## A joined player picks a car from the ones the garage owns with their own left and right;
## O or Y switches the AI opponents on and off, V or X switches between racing cars and boats
## (docs/DESIGN.md §20.5); once both are in, either one's join button again goes on to PICK A
## RACE. B / Escape goes back to the title, which ends the game.
##
## The screen reads raw events rather than the ui_ actions: which device pressed matters here.

const BACKGROUND := Color(0.078, 0.125, 0.18)
const YELLOW := Color(1, 0.824, 0.247)
const DIM := Color(0.624, 0.69, 0.769)
const OUTLINE := Color(0.055, 0.078, 0.11)
const CARD_SIZE := Vector2(780, 640)
## A stick pushed past this picks the next car once, until it comes back to the middle.
const STICK_PICK := 0.6

var _garage := {}
var _party := {}
var _owned: Array[DriftSetup] = []
var _cards: Array[Panel] = []
var _opponents: Label
var _hints: Label
var _stick_latched := {}  # pad id -> true while the stick is held over


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(func(state: Dictionary) -> void:
		_garage = state
		_owned.clear()
		for setup: DriftSetup in state.get("setups", []):
			if setup.id in state.get("owned", []):
				_owned.append(setup))
	EventSystem.PLY_state_changed.connect(_on_party_changed)


func _ready() -> void:
	EventSystem.PRO_state_requested.emit()
	var background := ColorRect.new()
	background.color = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var title := _label("2 PLAYERS", 72, Color.WHITE)
	title.position = Vector2(48, 30)
	title.size = Vector2(900, 100)
	add_child(title)
	for i in 2:
		var card := Panel.new()
		card.name = "Player%d" % (i + 1)
		card.position = Vector2(120 + i * (CARD_SIZE.x + 120), 170)
		card.size = CARD_SIZE
		add_child(card)
		_cards.append(card)
	_opponents = _label("", 36, Color.WHITE)
	_opponents.name = "Opponents"
	_opponents.position = Vector2(0, 850)
	_opponents.size = Vector2(1920, 60)
	_opponents.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_opponents)
	_hints = _label("", 26, DIM)
	_hints.position = Vector2(0, 960)
	_hints.size = Vector2(1920, 50)
	_hints.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hints)
	EventSystem.PLY_state_requested.emit()
	_refresh()


func _on_party_changed(state: Dictionary) -> void:
	_party = state
	if is_node_ready():
		_refresh()


func _players() -> Array:
	return _party.get("players", [])


func _refresh() -> void:
	var players := _players()
	for i in 2:
		_fill_card(_cards[i], i, players[i] if i < players.size() else {})
	_opponents.text = "%s     ( V / X )          OPPONENTS:  %s     ( O / Y )" % [
		"BOATS" if _garage.get("vehicle_kind", &"car") == &"boat" else "CARS",
		"ON" if _party.get("opponents", true) else "OFF"]
	_hints.text = "BOTH IN?  PRESS YOUR BUTTON AGAIN TO RACE!     ESC / B  BACK" if players.size() == 2 \
		else "GAMEPAD: A     KEYBOARD: SPACE (W A S D)  OR  ENTER (ARROWS)     ESC / B  BACK"


func _fill_card(card: Panel, index: int, player: Dictionary) -> void:
	for child in card.get_children():
		child.free()
	var colour: Color = PlayersManager.COLOURS[index]
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.118, 0.165, 0.227)
	style.set_corner_radius_all(36)
	style.set_border_width_all(8)
	style.border_color = colour if not player.is_empty() else Color(0.2, 0.25, 0.32)
	card.add_theme_stylebox_override("panel", style)
	var heading := _label("PLAYER %d" % (index + 1), 56, colour)
	heading.position = Vector2(0, 36)
	heading.size = Vector2(CARD_SIZE.x, 80)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(heading)
	if player.is_empty():
		var press := _label("PRESS A\nTO JOIN!", 64, YELLOW)
		press.name = "Press"
		press.position = Vector2(0, 220)
		press.size = Vector2(CARD_SIZE.x, 200)
		press.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(press)
		# Gently pulse, so an empty seat calls for someone to take it.
		var pulse := press.create_tween().set_loops()
		pulse.tween_property(press, "modulate:a", 0.45, 0.7)
		pulse.tween_property(press, "modulate:a", 1.0, 0.7)
		return
	var device := _label(PlayersManager.device_name(player["device"]), 28, DIM)
	device.position = Vector2(0, 120)
	device.size = Vector2(CARD_SIZE.x, 40)
	device.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(device)
	var setup := _setup(player["setup"])
	var art := TextureRect.new()
	art.name = "Car"
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = Paint.card(setup, _garage.get("paint", {}).get(setup.id, Paint.ORIGINAL)) if setup else null
	art.position = Vector2(110, 190)
	art.size = Vector2(CARD_SIZE.x - 220, 320)
	card.add_child(art)
	var arrows := "<   %s   >" if _owned.size() > 1 else "%s"
	var car_name := _label(arrows % (setup.display_name.to_upper() if setup else ""), 40, Color.WHITE)
	car_name.name = "CarName"
	car_name.position = Vector2(0, 540)
	car_name.size = Vector2(CARD_SIZE.x, 60)
	car_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(car_name)


func _setup(id: StringName) -> DriftSetup:
	for setup in _owned:
		if setup.id == id:
			return setup
	return _owned[0] if not _owned.is_empty() else null


func _input(event: InputEvent) -> void:
	var device := _join_device(event)
	if not device.is_empty():
		get_viewport().set_input_as_handled()
		_on_join_button(device)
		return
	if _is_back(event):
		get_viewport().set_input_as_handled()
		EventSystem.UI_screen_requested.emit(&"title")
		return
	if (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_O) \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_Y):
		get_viewport().set_input_as_handled()
		EventSystem.PLY_opponents_requested.emit(not _party.get("opponents", true))
		return
	if (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_V) \
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X):
		get_viewport().set_input_as_handled()
		_switch_kind()
		return
	_pick_car(event)


## Cars or boats: every player who has joined moves into the matching vehicle of the other kind
## (the equipped one for player 1, the next one owned for player 2), so nobody drives a car
## on the water.
func _switch_kind() -> void:
	var kind := &"car" if _garage.get("vehicle_kind", &"car") == &"boat" else &"boat"
	EventSystem.PRO_vehicle_kind_requested.emit(kind)  # answered at once: _garage and _owned follow
	var players := _players()
	for index in players.size():
		EventSystem.PLY_car_requested.emit(index, _default_car(players.slice(0, index)))
	_refresh()


## The device whose join button this event is, or {}.
static func _join_device(event: InputEvent) -> Dictionary:
	if event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_A:
		return {"kind": &"pad", "pad": event.device}
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_SPACE:
			return {"kind": &"keys_left"}
		if event.physical_keycode in [KEY_ENTER, KEY_KP_ENTER]:
			return {"kind": &"keys_right"}
	return {}


static func _is_back(event: InputEvent) -> bool:
	return (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_ESCAPE) \
		or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_B)


func _on_join_button(device: Dictionary) -> void:
	var players := _players()
	var mine := players.any(func(p: Dictionary) -> bool: return PlayersManager.same_device(p["device"], device))
	if mine:
		if players.size() == 2:
			EventSystem.UI_screen_requested.emit(&"tracks")
		return
	if players.size() >= 2:
		return
	EventSystem.PLY_join_requested.emit(device, _default_car(players))


## Player 1 starts in the equipped car; player 2 in the next car owned, so the two look different.
func _default_car(players: Array) -> StringName:
	var equipped: StringName = _garage.get("equipped", &"starter")
	if players.is_empty() or _owned.size() < 2:
		return equipped
	var i := _owned.find(_setup(players[0]["setup"]))
	return _owned[(i + 1) % _owned.size()].id


## Left / right on a joined player's own device picks their car.
func _pick_car(event: InputEvent) -> void:
	var players := _players()
	for index in players.size():
		var step := _steer_step(event, players[index]["device"])
		if step != 0 and _owned.size() > 1:
			get_viewport().set_input_as_handled()
			var i := _owned.find(_setup(players[index]["setup"]))
			EventSystem.PLY_car_requested.emit(index, _owned[posmod(i + step, _owned.size())].id)
			return


func _steer_step(event: InputEvent, device: Dictionary) -> int:
	var kind: StringName = device["kind"]
	if kind == &"pad":
		if event.device != device.get("pad", -1):
			return 0
		if event is InputEventJoypadButton and event.pressed:
			return {JOY_BUTTON_DPAD_LEFT: -1, JOY_BUTTON_DPAD_RIGHT: 1}.get(event.button_index, 0)
		if event is InputEventJoypadMotion and event.axis == JOY_AXIS_LEFT_X:
			var pad: int = event.device
			if absf(event.axis_value) < STICK_PICK * 0.5:
				_stick_latched.erase(pad)
			elif absf(event.axis_value) > STICK_PICK and not _stick_latched.has(pad):
				_stick_latched[pad] = true
				return 1 if event.axis_value > 0.0 else -1
		return 0
	if event is InputEventKey and event.pressed and not event.echo:
		var keys := {&"keys_left": {KEY_A: -1, KEY_D: 1}, &"keys_right": {KEY_LEFT: -1, KEY_RIGHT: 1}}
		return keys.get(kind, {}).get(event.physical_keycode, 0)
	return 0


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 8)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

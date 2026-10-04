class_name PlayersManager
extends Node
## One player or two (docs/DESIGN.md §15). Lives in the main.tscn shell next to
## GarageManager. Holds who is playing on what: in a one-player game the shared actions
## (steer_left, accelerate, ...) answer every keyboard key and every gamepad, as they always
## have; for two players each player gets actions of their own — p1_steer_left, p2_steer_left
## and so on — bound to only their device, so two children can drive on one computer.
##
## A device is a Dictionary: {"kind": &"keys_left"} (WASD), {"kind": &"keys_right"} (the
## arrow keys) or {"kind": &"pad", "pad": <joypad id>}. Screens ask with PLY_state_requested
## and get the whole state back on PLY_state_changed; the join screen sets it with
## PLY_join_requested / PLY_car_requested / PLY_opponents_requested, and going back to the
## title ends a two-player game.

## The per-player actions, without their "pN_" prefix.
const ACTIONS: Array[StringName] = [&"steer_left", &"steer_right", &"accelerate", &"brake", &"handbrake", &"horn"]
## Keyboard halves: physical keys per action. Left is WASD with Space; right is the arrows
## with Right Ctrl (and Numpad 0, for keyboards without a right Ctrl).
const KEYS := {
	&"keys_left": {&"steer_left": [KEY_A], &"steer_right": [KEY_D], &"accelerate": [KEY_W], &"brake": [KEY_S],
		&"handbrake": [KEY_SPACE], &"horn": [KEY_E]},
	&"keys_right": {&"steer_left": [KEY_LEFT], &"steer_right": [KEY_RIGHT], &"accelerate": [KEY_UP],
		&"brake": [KEY_DOWN], &"handbrake": [KEY_CTRL, KEY_KP_0], &"horn": [KEY_SHIFT]},
}
## Display names, short enough for a join card.
const DEVICE_NAMES := {&"keys_left": "KEYS  W A S D", &"keys_right": "KEYS  ARROWS", &"pad": "GAMEPAD %d"}
## Each player's colour: their minimap dot, their arrow over the car, their name on the results.
const COLOURS: Array[Color] = [Color(0.902, 0.224, 0.275), Color(0.62, 0.35, 0.95)]
const NAMES: Array[String] = ["P1", "P2"]

var two_player := false
## One entry per player who has joined: {"device": Dictionary, "setup": StringName}.
var players: Array[Dictionary] = []
## Whether two players race against AI opponents too (two) or only each other.
var opponents := true


func _enter_tree() -> void:
	EventSystem.PLY_state_requested.connect(_publish)
	EventSystem.PLY_join_requested.connect(join)
	EventSystem.PLY_car_requested.connect(func(index: int, setup_id: StringName) -> void:
		if index < players.size():
			players[index]["setup"] = setup_id
			_publish())
	EventSystem.PLY_opponents_requested.connect(func(on: bool) -> void:
		opponents = on
		_publish())
	EventSystem.PLY_two_player_requested.connect(start_two_player)
	EventSystem.UI_screen_requested.connect(func(screen: StringName) -> void:
		if screen == &"title":
			end_two_player())


## A fresh two-player game: nobody has joined yet.
func start_two_player() -> void:
	two_player = true
	players.clear()
	opponents = true
	_clear_actions()
	_publish()


func end_two_player() -> void:
	if not two_player and players.is_empty():
		return
	two_player = false
	players.clear()
	_clear_actions()
	_publish()


## The next free player takes `device`; a device already taken, or a third player, is ignored.
func join(device: Dictionary, setup_id: StringName) -> void:
	if not two_player or players.size() >= 2 or is_taken(device):
		return
	players.append({"device": device, "setup": setup_id})
	install_actions(players.size(), device)
	_publish()


func is_taken(device: Dictionary) -> bool:
	return players.any(func(p: Dictionary) -> bool: return same_device(p["device"], device))


static func same_device(a: Dictionary, b: Dictionary) -> bool:
	return a.get("kind") == b.get("kind") and a.get("pad", -1) == b.get("pad", -1)


static func prefix(player_number: int) -> String:
	return "p%d_" % player_number


static func device_name(device: Dictionary) -> String:
	var text: String = DEVICE_NAMES.get(device.get("kind"), "")
	return text % (int(device.get("pad", 0)) + 1) if "%d" in text else text


## Bind player `number`'s own actions (p1_..., p2_...) to `device` alone.
static func install_actions(number: int, device: Dictionary) -> void:
	for action in ACTIONS:
		var name := StringName(prefix(number) + action)
		if InputMap.has_action(name):
			InputMap.erase_action(name)
		InputMap.add_action(name, 0.2)
		for event in _events(action, device):
			InputMap.action_add_event(name, event)


static func _events(action: StringName, device: Dictionary) -> Array[InputEvent]:
	var out: Array[InputEvent] = []
	var kind: StringName = device.get("kind")
	if KEYS.has(kind):
		for key: Key in KEYS[kind][action]:
			var event := InputEventKey.new()
			event.physical_keycode = key
			if key in [KEY_CTRL, KEY_SHIFT]:  # the right-hand ones: the left belong to WASD's side
				event.location = KEY_LOCATION_RIGHT
			out.append(event)
		return out
	var pad := int(device.get("pad", 0))
	var axes := {&"steer_left": [JOY_AXIS_LEFT_X, -1.0], &"steer_right": [JOY_AXIS_LEFT_X, 1.0],
		&"accelerate": [JOY_AXIS_TRIGGER_RIGHT, 1.0], &"brake": [JOY_AXIS_TRIGGER_LEFT, 1.0]}
	var buttons := {&"steer_left": JOY_BUTTON_DPAD_LEFT, &"steer_right": JOY_BUTTON_DPAD_RIGHT,
		&"accelerate": JOY_BUTTON_A, &"brake": JOY_BUTTON_B, &"handbrake": JOY_BUTTON_X, &"horn": JOY_BUTTON_Y}
	if axes.has(action):
		var motion := InputEventJoypadMotion.new()
		motion.device = pad
		motion.axis = axes[action][0]
		motion.axis_value = axes[action][1]
		out.append(motion)
	var button := InputEventJoypadButton.new()
	button.device = pad
	button.button_index = buttons[action]
	out.append(button)
	return out


func _clear_actions() -> void:
	for number in [1, 2]:
		for action in ACTIONS:
			var name := StringName(prefix(number) + action)
			if InputMap.has_action(name):
				InputMap.erase_action(name)


func _publish() -> void:
	EventSystem.PLY_state_changed.emit({
		"two_player": two_player,
		"players": players.duplicate(true),
		"opponents": opponents,
	})

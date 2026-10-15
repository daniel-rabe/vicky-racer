extends CanvasLayer
## The race's pause menu (docs/mockups/pause_settings_layout). Escape / Start — or the
## window losing focus — freezes the race: cars, timers, countdown and car sounds all stop,
## because the whole tree pauses and only this layer keeps running.
##
## Built so a child cannot throw a race away by accident: RESUME is focused on opening, so
## pressing pause twice just resumes; B / Escape resumes too; RESTART and GARAGE ask
## "SURE?" with NO focused.

## Free Drive has nothing to restart: its menu has no RESTART.
@export var can_restart := true
## The open world (docs/DESIGN.md §28) has a MAP, under RESUME: the whole island, to find a race
## and have the way shown. The screen opens it (map_requested) and calls back_from_map().
@export var can_map := false

signal map_requested

@onready var _menu: Control = %Menu
@onready var _resume: Button = %Resume
@onready var _restart: Button = %Restart
@onready var _settings_button: Button = %Settings
@onready var _garage: Button = %Garage
@onready var _confirm: Control = %Confirm
@onready var _no: Button = %No
@onready var _yes: Button = %Yes
@onready var _settings: SettingsPanel = %SettingsPanel

var _confirmed_action: Callable
var _asked_from: Button  # focus returns here when SURE? is answered NO
var _map_button: Button
## Where leaving a race goes (§28): the garage, or straight back to the town once the child plays
## in the open world.
var _home: StringName = &"title"


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(func(state: Dictionary) -> void: _home = state.get("home", &"title"))


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_restart.visible = can_restart
	_resume.pressed.connect(resume)
	_restart.pressed.connect(_ask.bind(_leave_to.bind(&"race"), _restart))
	EventSystem.PRO_state_requested.emit()
	var leave_to := &"garage"
	if can_restart and _home == &"town":
		_garage.text = "TOWN"
		leave_to = &"town"
	_garage.pressed.connect(_ask.bind(_leave_to.bind(leave_to), _garage))
	if can_map:
		enable_map()
	_settings_button.pressed.connect(func() -> void:
		_menu.visible = false
		_settings.open())
	_settings.closed.connect(func() -> void:
		_menu.visible = true
		_settings_button.grab_focus())
	_no.pressed.connect(_close_confirm)
	_yes.pressed.connect(func() -> void: _confirmed_action.call())


## MAP under RESUME (once).
func enable_map() -> void:
	can_map = true
	if _map_button:
		return
	_map_button = Button.new()
	_map_button.name = "Map"
	_map_button.text = "MAP"
	_map_button.custom_minimum_size = Vector2(400, 90)
	_map_button.theme_type_variation = &"NavButton"
	_resume.get_parent().add_child(_map_button)
	_resume.get_parent().move_child(_map_button, _resume.get_index() + 1)
	_map_button.pressed.connect(func() -> void:
		_menu.visible = false
		map_requested.emit())


## The map was closed without choosing a way: the menu again, MAP focused.
func back_from_map() -> void:
	_menu.visible = true
	_map_button.grab_focus()


func _notification(what: int) -> void:
	# Alt-tabbing away (or a notification popping up) should not cost a race.
	var headless := DisplayServer.get_name() == "headless"
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not headless and not _capturing():
		pause()


## Dev screenshot runs (main.gd --screenshot) often start without focus; they must not pause.
static func _capturing() -> bool:
	return Array(OS.get_cmdline_user_args()).any(func(a: String) -> bool: return a.begins_with("--screenshot"))


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		if event.is_action_pressed("pause"):
			pause()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		if _confirm.visible:
			_close_confirm()
		else:
			resume()
		get_viewport().set_input_as_handled()


func pause() -> void:
	if visible:
		return
	visible = true
	_menu.visible = true
	_confirm.visible = false
	get_tree().paused = true
	_resume.grab_focus()


func resume() -> void:
	if not visible:
		return
	_settings.visible = false
	visible = false
	get_tree().paused = false


func _ask(action: Callable, from: Button) -> void:
	_confirmed_action = action
	_asked_from = from
	_menu.visible = false
	_confirm.visible = true
	_no.grab_focus()


func _close_confirm() -> void:
	_confirm.visible = false
	_menu.visible = true
	(_asked_from if _asked_from else _resume).grab_focus()


func _leave_to(screen: StringName) -> void:
	get_tree().paused = false
	EventSystem.UI_screen_requested.emit(screen)

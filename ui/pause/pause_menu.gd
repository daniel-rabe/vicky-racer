extends CanvasLayer
## The race's pause menu (docs/mockups/pause_settings_layout). Escape / Start — or the
## window losing focus — freezes the race: cars, timers, countdown and car sounds all stop,
## because the whole tree pauses and only this layer keeps running.
##
## Built so a child cannot throw a race away by accident: RESUME is focused on opening, so
## pressing pause twice just resumes; B / Escape resumes too; RESTART and GARAGE ask
## "SURE?" with NO focused.

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


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_resume.pressed.connect(resume)
	_restart.pressed.connect(_ask.bind(_leave_to.bind(&"race"), _restart))
	_garage.pressed.connect(_ask.bind(_leave_to.bind(&"garage"), _garage))
	_settings_button.pressed.connect(func() -> void:
		_menu.visible = false
		_settings.open())
	_settings.closed.connect(func() -> void:
		_menu.visible = true
		_settings_button.grab_focus())
	_no.pressed.connect(_close_confirm)
	_yes.pressed.connect(func() -> void: _confirmed_action.call())


func _notification(what: int) -> void:
	# Alt-tabbing away (or a notification popping up) should not cost a race.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and DisplayServer.get_name() != "headless":
		pause()


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
	EventSystem.UI_pause_changed.emit(true)


func resume() -> void:
	if not visible:
		return
	_settings.visible = false
	visible = false
	get_tree().paused = false
	EventSystem.UI_pause_changed.emit(false)


func _ask(action: Callable, from: Button) -> void:
	_confirmed_action = action
	_confirm.set_meta(&"from", from)
	_menu.visible = false
	_confirm.visible = true
	_no.grab_focus()


func _close_confirm() -> void:
	_confirm.visible = false
	_menu.visible = true
	var from: Button = _confirm.get_meta(&"from", _resume)
	from.grab_focus()


func _leave_to(screen: StringName) -> void:
	get_tree().paused = false
	EventSystem.UI_pause_changed.emit(false)
	EventSystem.UI_screen_requested.emit(screen)

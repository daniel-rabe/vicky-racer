class_name TownHUD
extends CanvasLayer
## Free Drive's HUD (docs/DESIGN.md §19): the coin purse top left, the town map top right
## with the player's car on it, and a sign that pops up when the player pulls up at a shop
## — the shop's picture and name, and how many kinds of place have been visited.
## Built in code: there is little of it, and it follows the race HUD's look (HudPanel).
##
## For the things to do (§23): an arrow at the screen's edge pointing to where a job is
## going (with its picture), the bus's passengers in a row under the coins, the controls of
## whatever the player is driving, and the map's marks.
##
## The open world (§28): pulling up on a race gate's glowing place shows its track's card (the
## one PICK A RACE shows) at the bottom, with the button that starts the race.

const THEME := preload("res://ui/theme/vicky_theme.tres")
const COIN := preload("res://art/ui/coin.png")
const YELLOW := Color(1, 0.824, 0.247)
const OUTLINE := Color(0.055, 0.078, 0.11)
const MAP_SIZE := Vector2(380, 300)
## The controls along the bottom, by what is being driven and the device used last.
const HINTS := {
	&"car": ["H  HORN     E  GET OUT     ESC  PAUSE", "Y  HORN / GET OUT     START  PAUSE"],
	&"foot": ["ARROWS  WALK     SPACE  RUN     E  GET IN     H  WHISTLE     ESC  PAUSE",
		"STICK  WALK     X  RUN     Y  GET IN / WHISTLE     START  PAUSE"],
	&"boat": ["H  HORN     ESC  PAUSE", "Y  HORN     START  PAUSE"],
	&"fire_engine": ["SPACE  WATER     H  SIREN     ESC  PAUSE", "X  WATER     Y  SIREN     START  PAUSE"],
	&"bus": ["H  HORN     ESC  PAUSE", "Y  HORN     START  PAUSE"],
}
## The pointer keeps this far inside the screen's edge, and hides when its target is on screen
## this far in.
const POINTER_MARGIN := 110.0
const GATE_SCALE := 0.75

var _coins: Label
var _sign: PanelContainer
var _sign_picture: TextureRect
var _sign_name: Label
var _sign_count: Label
var _sign_tween: Tween
var _banner: Label
var _map: TownMinimap
var _places_total := 0
var _shown_coins := -1
var _hints: Label
## The boat, beside the coins while sailing (§21.3).
var _vehicle_icon: TextureRect
## The harbour's swap: the screen goes white and comes back with the other vehicle.
var _fade: ColorRect
var _kind := &"car"
var _gamepad := false
## The last controls used were a gamepad's (the bubbles show its buttons).
var gamepad: bool:
	get:
		return _gamepad
## The arrow to a job's target, off screen (§23).
var _pointer: Control
var _pointer_picture: TextureRect
var _pointer_target := Vector2.INF
## The purse and the map: the pointer slides along the edge to keep clear of them.
var _corners: Array[Control] = []
## The bus's passengers.
var _passengers: HBoxContainer
## Today's jobs (§32), under the coins.
var _jobs: PanelContainer
var _job_row: HBoxContainer
## A race gate's card (§28), and the gate it is for (null: none shown).
var _gate_panel: PanelContainer
var _gate_slot: Control
var _gate_go: Label
var _gate_unlocked := true
var gate_shown: Node
## &"race", or &"time_trial" on a gate's stopwatch (§31).
var gate_mode := &"race"


func _ready() -> void:
	var root := Control.new()
	root.theme = THEME
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Coins, top left.
	var purse := _panel(root, Vector2(0, 0), Vector2(32, 28), Vector2(260, 96))
	_corners.append(purse)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	purse.add_child(row)
	var icon := TextureRect.new()
	icon.texture = COIN
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(64, 64)
	row.add_child(icon)
	_coins = _label(44, YELLOW)
	row.add_child(_coins)
	_vehicle_icon = TextureRect.new()
	_vehicle_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vehicle_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_vehicle_icon.custom_minimum_size = Vector2(150, 0)
	_vehicle_icon.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_END
	_vehicle_icon.visible = false
	row.add_child(_vehicle_icon)
	# The map, top right.
	var map_panel := _panel(root, Vector2(1, 0), Vector2(-MAP_SIZE.x - 32, 28), MAP_SIZE)
	_map = TownMinimap.new()
	map_panel.add_child(_map)
	_corners.append(map_panel)
	# The shop sign, top middle; hidden until a shop is reached.
	_sign = _panel(root, Vector2(0.5, 0), Vector2(-300, 40), Vector2(600, 170))
	var sign_row := HBoxContainer.new()
	sign_row.add_theme_constant_override("separation", 24)
	_sign.add_child(sign_row)
	_sign_picture = TextureRect.new()
	_sign_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sign_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sign_picture.custom_minimum_size = Vector2(150, 140)
	sign_row.add_child(_sign_picture)
	var words := VBoxContainer.new()
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	sign_row.add_child(words)
	_sign_name = _label(48, Color.WHITE)
	words.add_child(_sign_name)
	_sign_count = _label(24, YELLOW)
	words.add_child(_sign_count)
	_sign.pivot_offset = Vector2(300, 85)
	_sign.modulate.a = 0.0
	# A big line across the middle, for the all-places bonus.
	_banner = _label(56, YELLOW)
	_banner.anchor_right = 1.0  # the full width, however wide the window
	_banner.offset_top = 300.0
	_banner.offset_bottom = 400.0
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	root.add_child(_banner)
	_jobs = _panel(root, Vector2(0, 0), Vector2(32, 132), Vector2(260, 92))
	_jobs.pivot_offset = Vector2(130, 46)
	_jobs.visible = false
	_corners.append(_jobs)
	_job_row = HBoxContainer.new()
	_job_row.add_theme_constant_override("separation", 14)
	_job_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_jobs.add_child(_job_row)
	_passengers = HBoxContainer.new()
	_passengers.add_theme_constant_override("separation", 6)
	_passengers.position = Vector2(40, 238)
	root.add_child(_passengers)
	_pointer = _make_pointer()
	root.add_child(_pointer)
	_build_gate_card(root)
	_hints = _label(22, Color.WHITE)
	_hints.text = HINTS[_kind][0]
	_hints.anchor_top = 1.0
	_hints.anchor_bottom = 1.0
	_hints.offset_left = 32.0
	_hints.offset_top = -50.0
	_hints.offset_bottom = -14.0
	_hints.modulate.a = 0.75
	root.add_child(_hints)
	_fade = ColorRect.new()
	_fade.color = Color.WHITE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.modulate.a = 0.0
	root.add_child(_fade)


## Show the controls for whichever device was used last.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_gamepad = true
	elif event is InputEventKey:
		_gamepad = false
	_hints.text = HINTS[_kind][1 if _gamepad else 0]
	_show_gate_button()


func setup(town: Town, player: Car, traffic: Array[Car], places_total: int) -> void:
	_places_total = places_total
	_map.setup(town, player, traffic)


## After a swap (the harbour, the fire station, the school): the map follows the new vehicle
## (and shows the whole sea while sailing), a little picture of it sits beside the coins, and
## the controls along the bottom are its own.
func set_vehicle(player: Car, kind: StringName) -> void:
	_kind = kind
	_map.set_player(player, kind == &"boat")
	_vehicle_icon.texture = player.body_texture
	_vehicle_icon.visible = kind not in [&"car", &"foot"]
	_hints.text = HINTS[_kind][1 if _gamepad else 0]


## Point the way to `target` (Vector2.INF: nowhere) with `picture` beside the arrow.
func point_at(target: Vector2, picture: Texture2D) -> void:
	_pointer_target = target
	if picture:
		_pointer_picture.texture = picture


func set_marks(marks: Array) -> void:
	_map.marks = marks


## The bus's passengers, as a row of little pictures under the coins.
func show_passengers(pictures: Array[Texture2D]) -> void:
	for child in _passengers.get_children():
		child.queue_free()
	for picture in pictures:
		var icon := TextureRect.new()
		icon.texture = picture
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(44, 44)
		_passengers.add_child(icon)


## Today's jobs board (§32): a picture each, dots to go or a tick. `pulse`: a little bounce,
## when he comes by the board.
func show_jobs(jobs: Array[Dictionary], pulse := false) -> void:
	if _job_row == null:
		return
	_jobs.visible = not jobs.is_empty()
	while _job_row.get_child_count() < jobs.size():
		var icon := JobsBoard.JobIcon.new()
		icon.custom_minimum_size = Vector2(68, 70)
		_job_row.add_child(icon)
	for i in _job_row.get_child_count():
		var icon: JobsBoard.JobIcon = _job_row.get_child(i)
		icon.visible = i < jobs.size()
		if icon.visible:
			var done_before: bool = not icon.job.is_empty() and icon.job["have"] >= icon.job["need"]
			icon.job = jobs[i].duplicate()
			icon.queue_redraw()
			if not done_before and icon.job["have"] >= icon.job["need"]:
				pulse = true
	if pulse:
		var tween := _jobs.create_tween()
		tween.tween_property(_jobs, "scale", Vector2(1.15, 1.15), 0.1)
		tween.tween_property(_jobs, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(_delta: float) -> void:
	_place_pointer()


## The pointer sits on the screen's edge in the target's direction, the arrow turned to it;
## when the target is on screen the bubble over it shows the way instead.
func _place_pointer() -> void:
	if _pointer_target == Vector2.INF:
		_pointer.visible = false
		return
	var screen := get_viewport().get_visible_rect().size
	var at := get_viewport().get_canvas_transform() * _pointer_target
	var inner := Rect2(Vector2.ZERO, screen).grow(-POINTER_MARGIN)
	if inner.grow(-60.0).has_point(at):
		_pointer.visible = false
		return
	_pointer.visible = true
	var centre := screen / 2.0
	var direction := (at - centre).normalized()
	# Out from the middle along that direction, to where it meets the inner frame.
	var reach := INF
	if direction.x != 0.0:
		reach = minf(reach, (inner.size.x / 2.0) / absf(direction.x))
	if direction.y != 0.0:
		reach = minf(reach, (inner.size.y / 2.0) / absf(direction.y))
	var spot := centre + direction * reach
	for corner in _corners:
		var clear := corner.get_global_rect().grow(POINTER_MARGIN * 0.55)
		if clear.has_point(spot):
			# On the side edge: drop below the panel. On the top edge: step in beside it.
			if absf(spot.x - inner.position.x) < 1.0 or absf(spot.x - inner.end.x) < 1.0:
				spot.y = clear.end.y
			else:
				spot.x = clear.position.x if spot.x > centre.x else clear.end.x
	_pointer.position = spot
	_pointer.get_node(^"Arrow").rotation = direction.angle()
	_pointer.scale = Vector2.ONE * (1.0 + 0.06 * sin(Time.get_ticks_msec() / 160.0))


func _make_pointer() -> Control:
	var pointer := Control.new()
	pointer.name = "Pointer"
	pointer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointer.visible = false
	var bubble := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color.WHITE
	style.border_color = OUTLINE
	style.set_border_width_all(6)
	style.set_corner_radius_all(60)
	bubble.add_theme_stylebox_override("panel", style)
	bubble.size = Vector2(110, 110)
	bubble.position = -bubble.size / 2.0
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointer.add_child(bubble)
	_pointer_picture = TextureRect.new()
	_pointer_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_pointer_picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pointer_picture.size = Vector2(76, 76)
	_pointer_picture.position = Vector2(-38, -38)
	_pointer_picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pointer.add_child(_pointer_picture)
	var arrow := Polygon2D.new()
	arrow.name = "Arrow"
	arrow.polygon = PackedVector2Array([Vector2(62, -26), Vector2(98, 0), Vector2(62, 26)])
	arrow.color = YELLOW
	pointer.add_child(arrow)
	var rim := Line2D.new()
	rim.points = PackedVector2Array([Vector2(62, -26), Vector2(98, 0), Vector2(62, 26), Vector2(62, -26)])
	rim.width = 5.0
	rim.default_color = OUTLINE
	arrow.add_child(rim)
	return pointer


## The race gate's card, on the left, clear of the car in the middle: the track's card beside
## RACE! and its button. Drawn at GATE_SCALE.
func _build_gate_card(root: Control) -> void:
	_gate_panel = _panel(root, Vector2(0, 0.5), Vector2(32, -170), Vector2(780, 440))
	_gate_panel.name = "GateCard"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 28)
	_gate_panel.add_child(row)
	_gate_slot = Control.new()
	_gate_slot.custom_minimum_size = TrackCard.SIZE
	_gate_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_gate_slot)
	_gate_go = _label(44, YELLOW)
	_gate_go.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gate_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_gate_go)
	_gate_panel.pivot_offset = Vector2(0, 0)
	_gate_panel.visible = false


## Pulled up on `gate`'s place: its track's card, and RACE! (or, while it is locked, the button
## that shows the way to the race that opens it).
func show_gate(gate: Node, config: TrackConfig, unlocked: bool, best_lap: float, completed: bool, opened_by: String,
		mode := &"race") -> void:
	if gate_shown == gate and gate_mode == mode:
		return
	gate_shown = gate
	gate_mode = mode
	_gate_unlocked = unlocked
	for child in _gate_slot.get_children():
		child.queue_free()
	var card := TrackCard.new()
	card.setup(config, unlocked, best_lap, completed, opened_by)
	card.focus_mode = Control.FOCUS_NONE
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gate_slot.add_child(card)
	_show_gate_button()
	_gate_panel.visible = true
	_gate_panel.scale = Vector2.ONE * GATE_SCALE * 0.6
	_gate_panel.modulate.a = 0.0
	var tween := _gate_panel.create_tween()
	tween.tween_property(_gate_panel, "modulate:a", 1.0, 0.12)
	tween.parallel().tween_property(_gate_panel, "scale", Vector2.ONE * GATE_SCALE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func hide_gate() -> void:
	if gate_shown == null:
		return
	gate_shown = null
	_gate_panel.visible = false


func _show_gate_button() -> void:
	if _gate_go == null:
		return
	var button := "Y" if _gamepad else "R"
	if not _gate_unlocked:
		_gate_go.text = "%s\nSHOW ME\nTHE WAY" % button
	else:
		_gate_go.text = "%s\nTIME\nTRIAL!" % button if gate_mode == &"time_trial" else "%s\nRACE!" % button


## Fade the screen to white (`to_white`) or back. Await it: 0.18 s in, 0.25 s out.
func fade(to_white: bool) -> void:
	var tween := create_tween()
	tween.tween_property(_fade, "modulate:a", 1.0 if to_white else 0.0, 0.18 if to_white else 0.25)
	await tween.finished


func show_coins(total: int) -> void:
	if _shown_coins >= 0 and total > _shown_coins:
		var tween := _coins.create_tween()
		_coins.pivot_offset = _coins.size / 2.0
		tween.tween_property(_coins, "scale", Vector2(1.3, 1.3), 0.08)
		tween.tween_property(_coins, "scale", Vector2.ONE, 0.15)
	_shown_coins = total
	_coins.text = str(total)


## Coins earned at `world_pos`: a little +2 (or however many) floats up from it.
func coin_popped(world_pos: Vector2, amount := 2) -> void:
	var at := get_viewport().get_canvas_transform() * world_pos
	var label := _label(34 if amount < 5 else 46, YELLOW)
	label.text = "+%d" % amount
	label.position = at - Vector2(30, 60)
	get_child(0).add_child(label)
	var tween := label.create_tween()
	tween.tween_property(label, "position:y", label.position.y - 70.0, 0.7)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tween.tween_callback(label.queue_free)


func show_place(display_name: String, picture: Texture2D, visited: int, first: bool) -> void:
	_sign_name.text = display_name
	_sign_picture.texture = picture
	_sign_count.text = ("NEW PLACE!  " if first else "") + "%d / %d" % [visited, _places_total]
	if _sign_tween:
		_sign_tween.kill()
	_sign_tween = create_tween()
	_sign.scale = Vector2(0.6, 0.6)
	_sign_tween.tween_property(_sign, "modulate:a", 1.0, 0.12)
	_sign_tween.parallel().tween_property(_sign, "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_sign_tween.tween_interval(2.4)
	_sign_tween.tween_property(_sign, "modulate:a", 0.0, 0.4)


func show_banner(text: String) -> void:
	_banner.text = text
	var tween := create_tween()
	tween.tween_property(_banner, "modulate:a", 1.0, 0.2)
	tween.tween_interval(3.0)
	tween.tween_property(_banner, "modulate:a", 0.0, 0.5)


## The car wash: a screenful of soap bubbles floating up.
func bubbles() -> void:
	var root: Control = get_child(0)
	for i in 26:
		var bubble := Panel.new()
		var size := randf_range(30.0, 90.0)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.85, 0.95, 1.0, 0.35)
		style.border_color = Color(1, 1, 1, 0.85)
		style.set_border_width_all(3)
		style.set_corner_radius_all(int(size))
		bubble.add_theme_stylebox_override("panel", style)
		bubble.size = Vector2(size, size)
		bubble.position = Vector2(randf_range(0.1, 0.9) * root.size.x, root.size.y * randf_range(0.85, 1.05))
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bubble)
		var tween := bubble.create_tween()
		var time := randf_range(1.6, 3.0)
		tween.tween_property(bubble, "position", bubble.position + Vector2(randf_range(-160.0, 160.0), -900.0), time) \
			.set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(bubble, "modulate:a", 0.0, 0.6).set_delay(time - 0.6)
		tween.tween_callback(bubble.queue_free)


## A HUD panel pinned to a point of the screen (`anchor`: 0..1 across and down, so (1, 0) is
## the top right corner), `offset` px from it. Anchored rather than placed, so on a window
## wider than 16:9 the map stays in the corner instead of floating in from it.
func _panel(parent: Control, anchor: Vector2, offset: Vector2, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	panel.anchor_left = anchor.x
	panel.anchor_right = anchor.x
	panel.anchor_top = anchor.y
	panel.anchor_bottom = anchor.y
	panel.offset_left = offset.x
	panel.offset_top = offset.y
	panel.offset_right = offset.x + size.x
	panel.offset_bottom = offset.y + size.y
	panel.custom_minimum_size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	return panel


func _label(font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", 10)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

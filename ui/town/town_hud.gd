class_name TownHUD
extends CanvasLayer
## Free Drive's HUD (docs/DESIGN.md §19): the coin purse top left, the town map top right
## with the player's car on it, and a sign that pops up when the player pulls up at a shop
## — the shop's picture and name, and how many kinds of place have been visited.
## Built in code: there is little of it, and it follows the race HUD's look (HudPanel).

const THEME := preload("res://ui/theme/vicky_theme.tres")
const COIN := preload("res://art/ui/coin.png")
const YELLOW := Color(1, 0.824, 0.247)
const OUTLINE := Color(0.055, 0.078, 0.11)
const MAP_SIZE := Vector2(380, 300)
const HINTS_KEYBOARD := "H  HORN     ESC  PAUSE"
const HINTS_GAMEPAD := "Y  HORN     START  PAUSE"

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


func _ready() -> void:
	var root := Control.new()
	root.theme = THEME
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	# Coins, top left.
	var purse := _panel(root, Vector2(32, 28), Vector2(260, 96))
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
	# The map, top right.
	var map_panel := _panel(root, Vector2(1920 - MAP_SIZE.x - 32, 28), MAP_SIZE)
	_map = TownMinimap.new()
	map_panel.add_child(_map)
	# The shop sign, top middle; hidden until a shop is reached.
	_sign = _panel(root, Vector2(660, 40), Vector2(600, 170))
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
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_banner.position = Vector2(0, 300)
	_banner.size = Vector2(1920, 100)
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.modulate.a = 0.0
	root.add_child(_banner)
	_hints = _label(22, Color.WHITE)
	_hints.text = HINTS_KEYBOARD
	_hints.position = Vector2(32, 1030)
	_hints.modulate.a = 0.75
	root.add_child(_hints)


## Show the controls for whichever device was used last.
func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_hints.text = HINTS_GAMEPAD
	elif event is InputEventKey:
		_hints.text = HINTS_KEYBOARD


func setup(town: Town, player: Car, traffic: Array[Car], places_total: int) -> void:
	_places_total = places_total
	_map.setup(town, player, traffic)


func show_coins(total: int) -> void:
	if _shown_coins >= 0 and total > _shown_coins:
		var tween := _coins.create_tween()
		_coins.pivot_offset = _coins.size / 2.0
		tween.tween_property(_coins, "scale", Vector2(1.3, 1.3), 0.08)
		tween.tween_property(_coins, "scale", Vector2.ONE, 0.15)
	_shown_coins = total
	_coins.text = str(total)


## A coin picked up at `world_pos`: a little +2 floats up from it.
func coin_popped(world_pos: Vector2) -> void:
	var at := get_viewport().get_canvas_transform() * world_pos
	var label := _label(34, YELLOW)
	label.text = "+2"
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
		bubble.position = Vector2(randf_range(200.0, 1720.0), randf_range(900.0, 1150.0))
		bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bubble)
		var tween := bubble.create_tween()
		var time := randf_range(1.6, 3.0)
		tween.tween_property(bubble, "position", bubble.position + Vector2(randf_range(-160.0, 160.0), -900.0), time) \
			.set_trans(Tween.TRANS_SINE)
		tween.parallel().tween_property(bubble, "modulate:a", 0.0, 0.6).set_delay(time - 0.6)
		tween.tween_callback(bubble.queue_free)


func _panel(parent: Control, at: Vector2, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"HudPanel"
	panel.position = at
	panel.size = size
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

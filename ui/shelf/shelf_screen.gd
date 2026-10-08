extends Control
## The trophy shelf and the sticker book (docs/DESIGN.md §14), from the title screen. Every
## cup's best trophy stands on the shelf; the book above it holds every sticker. What is not won yet
## shows as a pale outline of itself, so a child who cannot read can see what is left to
## find. Moving the focus over a prize names it, or says how to win it, for a grown-up to
## read out. B / Esc or BACK returns to the title.

const BACKGROUND := preload("res://art/ui/shelf/background.png")
const SILHOUETTE := preload("res://ui/shelf/silhouette.gdshader")
const TROPHY_ART := {
	&"gold": preload("res://art/ui/cups/trophy_gold.png"),
	&"silver": preload("res://art/ui/cups/trophy_silver.png"),
	&"bronze": preload("res://art/ui/cups/trophy_bronze.png"),
	&"ribbon": preload("res://art/ui/cups/ribbon.png"),
}
const TROPHY_WORDS := {&"gold": "YOU WON THE %s!", &"silver": "2ND IN THE %s!", &"bronze": "3RD IN THE %s!",
	&"ribbon": "YOU FINISHED THE %s!"}
const HINTS_KEYBOARD := "ARROWS LOOK   ESC BACK"
const HINTS_GAMEPAD := "STICK LOOK   B BACK"
## The top of the shelf plank in the background picture, where the trophies stand.
const SHELF_TOP := 628.0
const TROPHY_SIZE := 220.0
const TROPHY_GAP := 420.0
## From the first trophy's centre to the last's at most, px.
const SHELF_SPAN := 1600.0
## The sticker book: a page pinned to the wall above the shelf, one row of stickers.
const BOOK_RECT := Rect2(150, 36, 1620, 350)
## Under the shelf, on the floor: what the focused prize is.
const CAPTION_Y := 860.0
const STICKER_SIZE := 196.0
## Each sticker sits a little crooked, as if stuck on by hand — always the same way.
const TILTS: Array[float] = [-0.07, 0.05, -0.03, 0.08, -0.05, 0.04, -0.06]
const BROWN := Color(0.29, 0.2, 0.13)
const PAPER := Color(0.99, 0.95, 0.85)
const YELLOW := Color(1, 0.824, 0.247)
const OUTLINE := Color(0.055, 0.078, 0.11)

var _state := {}
var _cups := {}
var _caption: Label
var _hints: Label
var _back: Button


func _enter_tree() -> void:
	EventSystem.PRO_state_changed.connect(func(state: Dictionary) -> void: _state = state)
	EventSystem.CUP_state_changed.connect(func(state: Dictionary) -> void: _cups = state)


func _ready() -> void:
	EventSystem.PRO_state_requested.emit()
	EventSystem.CUP_state_requested.emit()
	var background := TextureRect.new()
	background.texture = BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	_build_footer()
	var trophies := _build_trophies()
	var stickers := _build_book()
	_link_focus(trophies, stickers)
	(trophies[0] if not trophies.is_empty() else stickers[0]).grab_focus()


## One place per cup on the shelf, its trophy (or a pale outline) over the cup's picture.
func _build_trophies() -> Array[Button]:
	var row: Array[Button] = []
	var cups: Array = _cups.get("cups", [])
	for i in cups.size():
		var cup: CupConfig = cups[i]["config"]
		var trophy: StringName = cups[i]["trophy"]
		# Closer together when there are more cups, so the row always fits the shelf.
		var gap := minf(TROPHY_GAP, SHELF_SPAN / maxf(cups.size() - 1, 1))
		var centre_x := 960.0 + (i - (cups.size() - 1) / 2.0) * gap
		var rect := Rect2(centre_x - TROPHY_SIZE / 2.0, SHELF_TOP - TROPHY_SIZE + 12.0, TROPHY_SIZE, TROPHY_SIZE)
		var slot := _slot(rect, TROPHY_ART.get(trophy, TROPHY_ART[&"gold"]), trophy != &"", 0.0)
		slot.name = "Trophy_" + String(cup.id)
		var name_words := cup.display_name.to_upper()
		slot.set_meta(&"caption", TROPHY_WORDS[trophy] % name_words if trophy != &"" else "WIN THE %s!" % name_words)
		# The cup's own picture under the shelf, like a little name plate.
		var icon := TextureRect.new()
		icon.texture = cup.icon
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # before the size
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.position = Vector2(centre_x - 40.0, SHELF_TOP + 60.0)
		icon.size = Vector2(80, 80)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(icon)
		row.append(slot)
	return row


func _build_book() -> Array[Button]:
	var book := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PAPER
	style.set_corner_radius_all(36)
	style.set_border_width_all(10)
	style.border_color = Color(0.78, 0.36, 0.3)
	style.shadow_color = Color(0, 0, 0, 0.25)
	style.shadow_size = 18
	style.shadow_offset = Vector2(0, 8)
	book.add_theme_stylebox_override("panel", style)
	book.position = BOOK_RECT.position
	book.size = BOOK_RECT.size
	book.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(book)
	var earned: Array = _state.get("stickers", [])
	var title := _label("STICKERS  %d / %d" % [earned.size(), StickerManager.ORDER.size()], 34, BROWN, 0)
	title.position = BOOK_RECT.position + Vector2(48, 30)
	title.size = Vector2(BOOK_RECT.size.x - 96, 50)
	add_child(title)
	var row: Array[Button] = []
	var count := StickerManager.ORDER.size()
	var step := (BOOK_RECT.size.x - 80.0) / count
	# Smaller when there are more stickers, so they never overlap.
	var size := minf(STICKER_SIZE, step - 8.0)
	for i in count:
		var id := StickerManager.ORDER[i]
		var sticker: StickerConfig = load(StickerManager.STICKER_DIR + String(id) + ".tres")
		var won := id in earned
		var spot := Vector2(BOOK_RECT.position.x + 40.0 + step * (i + 0.5) - size / 2.0,
			BOOK_RECT.position.y + 112.0 + (STICKER_SIZE - size) / 2.0)
		var slot := _slot(Rect2(spot, Vector2.ONE * size), sticker.texture, won, TILTS[i % TILTS.size()])
		slot.name = "Sticker_" + String(id)
		slot.set_meta(&"caption", sticker.display_name.to_upper() + "!" if won else sticker.hint)
		row.append(slot)
	return row


## A focusable prize: the picture itself when won, its pale outline when not.
func _slot(rect: Rect2, texture: Texture2D, won: bool, tilt: float) -> Button:
	var slot := Button.new()
	slot.flat = true
	slot.position = rect.position
	slot.size = rect.size
	slot.pivot_offset = rect.size / 2.0
	slot.set_meta(&"won", won)
	var art := TextureRect.new()
	art.texture = texture
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # first: otherwise the size clamps to the texture's
	art.position = Vector2(10, 10)
	art.size = rect.size - Vector2(20, 20)
	art.pivot_offset = art.size / 2.0
	art.rotation = tilt
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not won:
		var material := ShaderMaterial.new()
		material.shader = SILHOUETTE
		art.material = material
	slot.add_child(art)
	slot.focus_entered.connect(_on_focus.bind(slot))
	slot.focus_exited.connect(func() -> void: create_tween().tween_property(slot, "scale", Vector2.ONE, 0.12))
	slot.mouse_entered.connect(slot.grab_focus)
	add_child(slot)
	return slot


func _on_focus(slot: Button) -> void:
	_caption.text = slot.get_meta(&"caption", "")
	create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT) \
		.tween_property(slot, "scale", Vector2.ONE * 1.12, 0.18)


func _build_footer() -> void:
	_caption = _label("", 34, YELLOW)
	_caption.position = Vector2(BOOK_RECT.position.x, CAPTION_Y)
	_caption.size = Vector2(BOOK_RECT.size.x, 60)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_caption)
	_hints = _label(HINTS_KEYBOARD, 24, Color.WHITE)
	_hints.position = Vector2(60, 1000)
	_hints.size = Vector2(900, 40)
	add_child(_hints)
	_back = Button.new()
	_back.name = "Back"
	_back.text = "BACK"
	_back.theme_type_variation = &"NavButton"
	_back.position = Vector2(1560, 966)
	_back.size = Vector2(300, 84)
	_back.pressed.connect(_go_back)
	_back.focus_entered.connect(func() -> void: _caption.text = "")
	add_child(_back)


## Left and right along each row; up and down between the book, the shelf and BACK.
func _link_focus(trophies: Array[Button], stickers: Array[Button]) -> void:
	for row: Array[Button] in [trophies, stickers]:
		for i in row.size():
			row[i].focus_neighbor_left = row[i].get_path_to(row[i - 1] if i > 0 else row[i])
			row[i].focus_neighbor_right = row[i].get_path_to(row[i + 1] if i < row.size() - 1 else row[i])
	var below_book: Array[Button] = trophies if not trophies.is_empty() else [_back]
	for sticker in stickers:
		sticker.focus_neighbor_top = sticker.get_path_to(sticker)
		sticker.focus_neighbor_bottom = sticker.get_path_to(_nearest(below_book, sticker))
	for trophy in trophies:
		trophy.focus_neighbor_top = trophy.get_path_to(_nearest(stickers, trophy))
		trophy.focus_neighbor_bottom = trophy.get_path_to(_back)
	var above_back: Button = trophies[-1] if not trophies.is_empty() else stickers[-1]
	_back.focus_neighbor_top = _back.get_path_to(above_back)
	_back.focus_neighbor_left = _back.get_path_to(above_back)
	_back.focus_neighbor_right = _back.get_path_to(_back)
	_back.focus_neighbor_bottom = _back.get_path_to(_back)


func _nearest(row: Array[Button], to: Control) -> Button:
	var x := to.get_rect().get_center().x
	var best := row[0]
	for b in row:
		if absf(b.get_rect().get_center().x - x) < absf(best.get_rect().get_center().x - x):
			best = b
	return best


func _label(text: String, font_size: int, colour: Color, outline := 10) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", OUTLINE)
	label.add_theme_constant_override("outline_size", outline)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _go_back() -> void:
	EventSystem.UI_screen_requested.emit(&"title")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_hints.text = HINTS_GAMEPAD
	elif event is InputEventKey:
		_hints.text = HINTS_KEYBOARD

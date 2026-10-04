class_name StickerPopup
extends CanvasLayer
## A new sticker pops onto the screen (docs/DESIGN.md §14): it bounces in, big, above the
## middle of the screen — where the race countdown goes, clear of the player's own car — with
## NEW STICKER! over it, then shrinks away. Lives in the main.tscn shell, so it shows on any
## screen and carries on across a screen change; several at once (a win can bring three)
## take turns.

const THEME := preload("res://ui/theme/vicky_theme.tres")
const SOUND := preload("res://art/sfx/sticker.wav")
const CENTRE := Vector2(960, 400)
const SIZE := 290.0
const HOLD_SECONDS := 2.0
const YELLOW := Color(1, 0.824, 0.247)
const DARK := Color(0.055, 0.078, 0.11)

var _queue: Array[StickerConfig] = []
var _showing := false
## The sticker on screen now, or null (for tests).
var current: StickerConfig

var _art: TextureRect
var _banner: Label
var _sound: AudioStreamPlayer


func _enter_tree() -> void:
	EventSystem.PRO_sticker_earned.connect(_on_earned)


func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	_art = TextureRect.new()
	_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE  # before the size, or it clamps to the texture's
	_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_art.size = Vector2(SIZE, SIZE)
	_art.pivot_offset = _art.size / 2.0
	_art.position = CENTRE - _art.size / 2.0
	_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art.visible = false
	add_child(_art)
	_banner = Label.new()
	_banner.theme = THEME
	_banner.text = "NEW STICKER!"
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 56)
	_banner.add_theme_color_override("font_color", YELLOW)
	_banner.add_theme_color_override("font_outline_color", DARK)
	_banner.add_theme_constant_override("outline_size", 18)
	_banner.size = Vector2(900, 80)
	_banner.pivot_offset = _banner.size / 2.0
	_banner.position = Vector2(CENTRE.x - 450.0, CENTRE.y - SIZE / 2.0 - 90.0)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_banner.visible = false
	add_child(_banner)
	_sound = AudioStreamPlayer.new()
	_sound.stream = SOUND
	_sound.bus = &"SFX"
	add_child(_sound)
	if not _queue.is_empty():
		_show_next()


func _on_earned(id: StringName) -> void:
	var path := StickerManager.STICKER_DIR + String(id) + ".tres"
	if not ResourceLoader.exists(path):
		return
	_queue.append(load(path))
	# A save that already qualifies earns at start-up, before this node is ready: _ready shows it.
	if not _showing and is_node_ready():
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		current = null
		_art.visible = false
		_banner.visible = false
		return
	_showing = true
	current = _queue.pop_front()
	_art.texture = current.texture
	_art.visible = true
	_banner.visible = true
	_art.scale = Vector2.ZERO
	_art.rotation = -0.7
	_art.modulate.a = 1.0
	_banner.scale = Vector2.ZERO
	_banner.modulate.a = 1.0
	if SoundManager.audible():  # each sticker pops with its own sound, as it comes up
		_sound.play()
	var tween := create_tween()
	# Slapped on: overshoots, settles a little askew like a sticker stuck on by hand.
	tween.tween_property(_art, "scale", Vector2.ONE * 1.15, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_art, "rotation", -0.08, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(_banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_art, "scale", Vector2.ONE, 0.12)
	tween.tween_interval(HOLD_SECONDS)
	tween.tween_property(_art, "scale", Vector2.ONE * 0.2, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_art, "modulate:a", 0.0, 0.35)
	tween.parallel().tween_property(_banner, "modulate:a", 0.0, 0.25)
	tween.tween_callback(_show_next)

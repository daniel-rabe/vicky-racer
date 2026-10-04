extends Control
## The end of a cup (docs/DESIGN.md §12): the top three cars rise onto a podium, confetti
## falls, the podium music opens with its fanfare (MusicManager), then the trophy (or, for 4th, the ribbon) flies in and the cup
## bonus counts up. Always a celebration: finishing a cup is something to be proud of.
## GARAGE (focused when the show is over) leaves.

const TROPHY_ART := {
	&"gold": preload("res://art/ui/cups/trophy_gold.png"),
	&"silver": preload("res://art/ui/cups/trophy_silver.png"),
	&"bronze": preload("res://art/ui/cups/trophy_bronze.png"),
	&"ribbon": preload("res://art/ui/cups/ribbon.png"),
}
const HEADLINES := {
	&"gold": "YOU WON THE %s!",
	&"silver": "2ND IN THE %s!",
	&"bronze": "3RD IN THE %s!",
	&"ribbon": "YOU FINISHED THE %s!",
}
const COIN := preload("res://art/sfx/coin.wav")
## Podium blocks left to right: 2nd, 1st, 3rd — height and colour.
const BLOCKS := [[2, 230.0, Color(0.75, 0.77, 0.8)], [1, 330.0, Color(1, 0.8, 0.25)], [3, 160.0, Color(0.8, 0.5, 0.25)]]
const BLOCK_WIDTH := 300.0
const FLOOR_Y := 900.0
const DARK := Color(0.055, 0.078, 0.11)
const YELLOW := Color(1, 0.824, 0.247)

var _cup := {}
var _garage_state := {}

@onready var _headline: Label = %Headline
@onready var _stage: Control = %Stage
@onready var _trophy: TextureRect = %Trophy
@onready var _bonus: Label = %Bonus
@onready var _garage: Button = %Garage


func _enter_tree() -> void:
	EventSystem.CUP_state_changed.connect(func(state: Dictionary) -> void: _cup = state)
	EventSystem.PRO_state_changed.connect(func(state: Dictionary) -> void: _garage_state = state)


func _ready() -> void:
	EventSystem.CUP_state_requested.emit()
	EventSystem.PRO_state_requested.emit()
	_garage.pressed.connect(func() -> void: EventSystem.UI_screen_requested.emit(&"garage"))
	_garage.disabled = true
	_garage.focus_mode = Control.FOCUS_NONE
	_trophy.modulate.a = 0.0
	_bonus.text = ""
	if _cup.is_empty() or _cup["cup"] == null or _cup["trophy"] == &"":
		_headline.text = "NO CUP"
		_enable_garage()
		return
	var cup: CupConfig = _cup["cup"]
	var trophy: StringName = _cup["trophy"]
	_headline.text = HEADLINES[trophy] % cup.display_name.to_upper()
	_trophy.texture = TROPHY_ART[trophy]
	_add_confetti()
	var tween := create_tween()
	for block: Array in BLOCKS:
		_build_block(block, tween)
	# The trophy flies up from below and settles, then the bonus counts up.
	var home := _trophy.position
	_trophy.position.y += 500.0
	tween.tween_property(_trophy, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(_trophy, "position", home, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var bonus := int(_garage_state.get("last_cup", {}).get("bonus", 0))
	tween.tween_callback(_play.bind(COIN))
	tween.tween_method(func(v: float) -> void: _bonus.text = "+%d COINS" % roundi(v), 0.0, float(bonus), 1.0)
	tween.tween_callback(_enable_garage)


## One podium block with the car that finished there standing on it.
func _build_block(block: Array, tween: Tween) -> void:
	var place: int = block[0]
	var height: float = block[1]
	var slot := BLOCKS.find(block)
	var x := 960.0 - BLOCK_WIDTH * 1.5 + slot * BLOCK_WIDTH - 360.0
	var rect := Panel.new()
	var style := StyleBoxFlat.new()
	style.bg_color = block[2]
	style.set_border_width_all(6)
	style.border_color = DARK
	style.set_corner_radius_all(16)
	rect.add_theme_stylebox_override("panel", style)
	rect.position = Vector2(x, FLOOR_Y)
	rect.size = Vector2(BLOCK_WIDTH - 12.0, 0.0)
	_stage.add_child(rect)
	var number := _label(str(place), 96, DARK)
	number.position = Vector2(0, 20)
	number.size = Vector2(BLOCK_WIDTH - 12.0, 110)
	rect.add_child(number)
	tween.tween_property(rect, "position:y", FLOOR_Y - height, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(rect, "size:y", height, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var row: Dictionary = {}
	for entry: Dictionary in _cup["standings"]:
		if entry["position"] == place:
			row = entry
	if row.is_empty():
		return
	var car := TextureRect.new()
	if ResourceLoader.exists(row["body"]):
		car.texture = load(row["body"])
	car.size = Vector2(256, 144)
	car.pivot_offset = car.size / 2.0
	car.rotation = -PI / 2.0  # nose up, as if standing on the podium to be seen
	car.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	car.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	car.position = Vector2(x + (BLOCK_WIDTH - 12.0 - 256.0) / 2.0, FLOOR_Y - height - 200.0)
	car.modulate.a = 0.0
	_stage.add_child(car)
	var name_label := _label(row["name"], 30, YELLOW if row["is_player"] else Color.WHITE)
	name_label.position = Vector2(x, FLOOR_Y - height - 320.0)
	name_label.size = Vector2(BLOCK_WIDTH - 12.0, 50)
	name_label.modulate.a = 0.0
	_stage.add_child(name_label)
	tween.tween_property(car, "modulate:a", 1.0, 0.2)
	tween.parallel().tween_property(name_label, "modulate:a", 1.0, 0.2)


func _add_confetti() -> void:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	material.emission_box_extents = Vector3(980.0, 10.0, 0.0)
	material.direction = Vector3(0, 1, 0)
	material.spread = 25.0
	material.initial_velocity_min = 120.0
	material.initial_velocity_max = 260.0
	material.gravity = Vector3(0, 160, 0)
	material.angular_velocity_min = -360.0
	material.angular_velocity_max = 360.0
	material.scale_min = 1.0
	material.scale_max = 1.6
	var colours := Gradient.new()
	colours.set_color(0, Color(0.9, 0.22, 0.27))
	colours.set_color(1, Color(0.23, 0.53, 1.0))
	colours.add_point(0.33, YELLOW)
	colours.add_point(0.66, Color(0.18, 0.77, 0.42))
	var ramp := GradientTexture1D.new()
	ramp.gradient = colours
	material.color_initial_ramp = ramp
	var confetti := GPUParticles2D.new()
	confetti.process_material = material
	confetti.amount = 160
	confetti.lifetime = 5.0
	confetti.preprocess = 1.0
	confetti.position = Vector2(960, -20)
	var piece := Image.create(10, 16, false, Image.FORMAT_RGBA8)
	piece.fill(Color.WHITE)  # tinted per piece by color_initial_ramp
	confetti.texture = ImageTexture.create_from_image(piece)
	add_child(confetti)
	move_child(confetti, 1)


func _enable_garage() -> void:
	_garage.disabled = false
	_garage.focus_mode = Control.FOCUS_ALL
	_garage.grab_focus()


func _play(stream: AudioStream) -> void:
	if not SoundManager.audible():
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = &"SFX"
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _label(text: String, font_size: int, colour: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", DARK)
	label.add_theme_constant_override("outline_size", 8 if colour != DARK else 0)
	return label

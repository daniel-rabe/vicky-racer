class_name SetupCard
extends Button
## One drift setup in the garage grid: its card art, name, and either its price or an
## OWNED / EQUIPPED badge. Unaffordable cards are dimmed with the price in red, but stay
## focusable so their stats can be browsed before saving up (docs/mockups/garage_layout).

signal chosen(setup: DriftSetup)

const GREEN := Color(0.18, 0.769, 0.42)
const RED := Color(0.902, 0.224, 0.275)
const DIM := 0.55

var setup: DriftSetup

@onready var _content: Control = $Content
@onready var _art: TextureRect = %Art
@onready var _name: Label = %Name
@onready var _price_row: Control = %PriceRow
@onready var _price: Label = %Price
@onready var _owned: Label = %Owned
@onready var _equipped: PanelContainer = %Equipped


func _ready() -> void:
	pressed.connect(func() -> void: chosen.emit(setup))


func show_setup(value: DriftSetup, owned: bool, equipped: bool, affordable: bool) -> void:
	setup = value
	_art.texture = setup.card_art
	_name.text = setup.display_name.to_upper()
	_equipped.visible = equipped
	_owned.visible = owned and not equipped
	_price_row.visible = not owned
	_price.text = str(setup.price)
	_price.add_theme_color_override("font_color", Color.WHITE if affordable else RED)
	_content.modulate.a = 1.0 if owned or affordable else DIM


## A short wobble when the player tries to buy something they cannot afford yet.
func shake() -> void:
	var tween := create_tween()
	for offset in [12.0, -10.0, 7.0, -4.0, 0.0]:
		tween.tween_property(_content, "position:x", offset, 0.05)


## A little pop when the setup has just been bought.
func pop() -> void:
	pivot_offset = size / 2.0
	var tween := create_tween()
	tween.tween_property(self, "scale", Vector2(1.08, 1.08), 0.1)
	tween.tween_property(self, "scale", Vector2.ONE, 0.15)

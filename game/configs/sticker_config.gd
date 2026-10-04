class_name StickerConfig
extends Resource
## One sticker for the sticker book (docs/DESIGN.md §14): a small achievement shown as a
## picture, so a child who cannot read yet can still see what they have collected. What
## earns it is decided by StickerManager, keyed on `id`.

@export var id: StringName
@export var display_name := ""
## How to earn it, for a grown-up to read out: shown under the focused sticker in the book.
@export var hint := ""
@export var texture: Texture2D

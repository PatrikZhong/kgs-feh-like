@tool
class_name UnitSpawner
extends Node2D

const TILE_SIZE := 40
# TileMapLayers in Battle scenes use scale=2.5 on 16 px tiles, making each
# tile appear as 40 px in world space.  In the Godot editor there is no camera
# zoom, so we scale the editor indicator by the same factor so it looks as
# large as the tiles it sits on.
const EDITOR_DRAW_SCALE := 2.5

@export var unit_data: UnitData:
	set(v):
		unit_data = v
		queue_redraw()

@export var is_player_unit: bool = true:
	set(v):
		is_player_unit = v
		queue_redraw()

@export var cell: Vector2i = Vector2i.ZERO:
	set(v):
		cell = v
		position = Vector2(v) * TILE_SIZE + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
		queue_redraw()

func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_local_transform(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_LOCAL_TRANSFORM_CHANGED and Engine.is_editor_hint():
		var new_cell := Vector2i(int(floor(position.x / TILE_SIZE)), int(floor(position.y / TILE_SIZE)))
		if new_cell != cell:
			cell = new_cell  # snaps position to cell centre and redraws

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color := Color(0.2, 0.6, 1.0, 0.6) if is_player_unit else Color(1.0, 0.3, 0.2, 0.6)
	var half: float = TILE_SIZE * EDITOR_DRAW_SCALE * 0.5
	var size: float = TILE_SIZE * EDITOR_DRAW_SCALE
	draw_rect(Rect2(-half, -half, size, size), Color(color.r, color.g, color.b, 0.25))
	draw_rect(Rect2(-half, -half, size, size), color, false, 2.0)
	draw_circle(Vector2.ZERO, half * 0.45, color)
	if unit_data:
		var letter := unit_data.class_label().left(1)
		var font_size := int(half * 0.9)
		var text_size := ThemeDB.fallback_font.get_string_size(letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(ThemeDB.fallback_font, -text_size / 2.0 + Vector2(0, text_size.y * 0.25),
				letter, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

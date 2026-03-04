@tool
class_name UnitSpawner
extends Node2D

const TILE_SIZE := 40

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

func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	var color := Color(0.2, 0.6, 1.0, 0.5) if is_player_unit else Color(1.0, 0.3, 0.2, 0.5)
	var half := TILE_SIZE * 0.5
	draw_rect(Rect2(-half, -half, TILE_SIZE, TILE_SIZE), color)
	draw_circle(Vector2.ZERO, half * 0.5, color.lightened(0.3))
	if unit_data:
		var letter := unit_data.class_label().left(1)
		draw_string(ThemeDB.fallback_font, Vector2(-5, 5), letter,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)

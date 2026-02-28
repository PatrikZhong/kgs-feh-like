class_name HighlightLayer
extends Node2D

const CELL_SIZE := Vector2(64, 64)
const HIGHLIGHT_COLOR := Color(0.20, 0.60, 1.00, 0.40)
const DANGER_COLOR    := Color(1.00, 0.30, 0.20, 0.40)

var _cells: Array[Vector2i] = []

func show_reachable(cells: Array[Vector2i]) -> void:
	_cells = cells
	queue_redraw()

func clear() -> void:
	_cells = []
	queue_redraw()

func _draw() -> void:
	for cell in _cells:
		var rect := Rect2(Vector2(cell) * CELL_SIZE, CELL_SIZE)
		draw_rect(rect, HIGHLIGHT_COLOR, true)
		draw_rect(rect, Color(0.20, 0.60, 1.00, 0.80), false, 2.0)

class_name HighlightLayer
extends Node2D

const CELL_SIZE    := Vector2(40, 40)
const MOVE_FILL    := Color(0.20, 0.60, 1.00, 0.35)
const MOVE_BORDER  := Color(0.20, 0.60, 1.00, 0.85)
const ATTACK_FILL  := Color(1.00, 0.38, 0.08, 0.38)
const ATTACK_BORDER := Color(1.00, 0.38, 0.08, 0.90)
const THREAT_FILL   := Color(0.85, 0.10, 0.10, 0.28)
const THREAT_BORDER := Color(0.85, 0.10, 0.10, 0.55)

## Set by BattleMap._ready() so highlights are drawn in world-space coordinates.
@onready var _grid_mgr: GridManager = get_parent().get_node("GridManager")

var _threat_cells: Array[Vector2i] = []
var _move_cells:   Array[Vector2i] = []
var _attack_cells: Array[Vector2i] = []

## Show movement range (blue) and attack range (orange) simultaneously.
func show_move_and_attack(move_cells: Array[Vector2i], attack_cells: Array[Vector2i]) -> void:
	_move_cells   = move_cells
	_attack_cells = attack_cells
	queue_redraw()

## Show only attack range (orange) — used after a unit has landed.
func show_attack_only(attack_cells: Array[Vector2i]) -> void:
	_move_cells   = []
	_attack_cells = attack_cells
	queue_redraw()

func set_threat(cells: Array[Vector2i]) -> void:
	_threat_cells = cells
	queue_redraw()

func clear() -> void:
	_move_cells   = []
	_attack_cells = []
	queue_redraw()

func clear_all() -> void:
	_threat_cells = []
	_move_cells   = []
	_attack_cells = []
	queue_redraw()

func _cell_rect(cell: Vector2i) -> Rect2:
	if _grid_mgr:
		return Rect2(_grid_mgr.grid_to_world(cell) - CELL_SIZE / 2.0, CELL_SIZE)
	return Rect2(Vector2(cell) * CELL_SIZE, CELL_SIZE)

func _draw() -> void:
	for cell in _threat_cells:
		var rect := _cell_rect(cell)
		draw_rect(rect, THREAT_FILL,   true)
		draw_rect(rect, THREAT_BORDER, false, 1.5)
	for cell in _move_cells:
		var rect := _cell_rect(cell)
		draw_rect(rect, MOVE_FILL,   true)
		draw_rect(rect, MOVE_BORDER, false, 2.0)
	for cell in _attack_cells:
		var rect := _cell_rect(cell)
		draw_rect(rect, ATTACK_FILL,   true)
		draw_rect(rect, ATTACK_BORDER, false, 2.0)

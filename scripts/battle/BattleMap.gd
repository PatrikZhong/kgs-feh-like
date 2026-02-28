extends Node2D

const UNIT_SCENE := preload("res://scenes/battle/Unit.tscn")
const KNIGHT_DATA  := preload("res://resources/units/KnightData.tres")
const CAVALRY_DATA := preload("res://resources/units/CavalryData.tres")
const ARCHER_DATA  := preload("res://resources/units/ArcherData.tres")
const MAGE_DATA    := preload("res://resources/units/MageData.tres")

## All units on the map.
var units: Array[Unit] = []
var player_units: Array[Unit] = []
var enemy_units: Array[Unit] = []

# Drag state
var _dragged_unit: Unit = null
var _original_cell: Vector2i = Vector2i.ZERO
var _reachable_cells: Array[Vector2i] = []
var _extended_attack_cells: Array[Vector2i] = []  # orange: attackable from any move cell

@onready var grid_mgr: GridManager = $GridManager
@onready var highlight_lyr: HighlightLayer = $HighlightLayer
@onready var units_layer: Node2D = $UnitsLayer

func _ready() -> void:
	TurnManager.start_battle(self)
	_place_test_units()

# ---------------------------------------------------------------------------
# Unit placement
# ---------------------------------------------------------------------------

func _place_test_units() -> void:
	_spawn(KNIGHT_DATA,  Vector2i(1, 1), true)
	_spawn(ARCHER_DATA,  Vector2i(1, 3), true)
	_spawn(MAGE_DATA,    Vector2i(1, 5), true)
	_spawn(KNIGHT_DATA,  Vector2i(6, 2), false)
	_spawn(CAVALRY_DATA, Vector2i(6, 4), false)
	_spawn(ARCHER_DATA,  Vector2i(6, 6), false)

func _spawn(data: UnitData, cell: Vector2i, is_player: bool) -> Unit:
	var unit: Unit = UNIT_SCENE.instantiate()
	unit.data = data
	unit.is_player_unit = is_player
	units_layer.add_child(unit)
	unit.snap_to_cell(cell, grid_mgr)
	grid_mgr.set_cell_solid(cell, true)
	units.append(unit)
	if is_player:
		player_units.append(unit)
	else:
		enemy_units.append(unit)
	unit.died.connect(_on_unit_died)
	return unit

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if TurnManager.current_state != TurnManager.State.PLAYER_TURN:
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_begin_drag(get_global_mouse_position())
		else:
			_end_drag(get_global_mouse_position())
	elif event is InputEventMouseMotion and _dragged_unit:
		_dragged_unit.position = units_layer.to_local(get_global_mouse_position())

# ---------------------------------------------------------------------------
# Drag & drop
# ---------------------------------------------------------------------------

func _begin_drag(world_pos: Vector2) -> void:
	var cell := grid_mgr.world_to_grid(world_pos)
	var unit := get_unit_at(cell)

	if not unit or not unit.is_player_unit or unit.has_moved:
		return

	_dragged_unit = unit
	_original_cell = unit.grid_cell

	var ally_cells: Array = []
	for u in player_units:
		if u != unit:
			ally_cells.append(u.grid_cell)

	_reachable_cells = grid_mgr.get_reachable_cells(
		unit.grid_cell, unit.data.move_range, unit.data.can_jump_allies, ally_cells
	)
	_extended_attack_cells = _get_extended_attack_cells(_reachable_cells, unit.attack_range)

	highlight_lyr.show_move_and_attack(_reachable_cells, _extended_attack_cells)
	unit.start_drag()

func _end_drag(world_pos: Vector2) -> void:
	if not _dragged_unit:
		return

	var drop_cell := grid_mgr.world_to_grid(world_pos)
	var unit := _dragged_unit
	_dragged_unit = null

	unit.end_drag()
	highlight_lyr.clear()

	var occupant := get_unit_at(drop_cell)
	var cell_free := occupant == null or occupant == unit

	# — Drop on a movement tile: just move —
	if drop_cell in _reachable_cells and drop_cell != _original_cell and cell_free:
		_commit_move(unit, drop_cell)
		TurnManager.end_player_turn()

	# — Drop on an attack tile with an enemy: move to best position and attack —
	elif drop_cell in _extended_attack_cells:
		var target := get_unit_at(drop_cell)
		if target and not target.is_player_unit:
			var best_cell := _find_best_attacker_cell(
				_original_cell, drop_cell, _reachable_cells, unit.attack_range
			)
			_commit_move(unit, best_cell)
			perform_combat(unit, target)
			TurnManager.end_player_turn()
		else:
			# Orange cell but no enemy — cancel
			unit.position = grid_mgr.grid_to_world(_original_cell)

	# — Anything else: cancel —
	else:
		unit.position = grid_mgr.grid_to_world(_original_cell)

	_reachable_cells = []
	_extended_attack_cells = []

func _commit_move(unit: Unit, cell: Vector2i) -> void:
	grid_mgr.set_cell_solid(_original_cell, false)
	grid_mgr.set_cell_solid(cell, true)
	unit.grid_cell = cell
	var tween := create_tween()
	tween.tween_property(unit, "position", grid_mgr.grid_to_world(cell), 0.10)
	unit.set_moved()

# ---------------------------------------------------------------------------
# Attack helpers
# ---------------------------------------------------------------------------

## All tiles reachable via attack from any movement cell, excluding the move
## cells themselves (those are shown in blue).
func _get_extended_attack_cells(reachable: Array[Vector2i], atk_range: int) -> Array[Vector2i]:
	var seen: Dictionary = {}
	for move_cell in reachable:
		for dy in range(-atk_range, atk_range + 1):
			for dx in range(-atk_range, atk_range + 1):
				var dist: int = abs(dx) + abs(dy)
				if dist < 1 or dist > atk_range:
					continue
				var cell := move_cell + Vector2i(dx, dy)
				if grid_mgr.is_in_bounds(cell) and cell not in reachable:
					seen[cell] = true
	var result: Array[Vector2i] = []
	for cell in seen:
		result.append(cell)
	return result

## Reachable cell closest to `from` that is within `atk_range` of `target`.
## Minimises movement so the unit travels the shortest path to attack.
func _find_best_attacker_cell(
		from: Vector2i,
		target: Vector2i,
		reachable: Array[Vector2i],
		atk_range: int) -> Vector2i:

	var best_cell := from
	var best_dist := INF
	for cell in reachable:
		var to_target: int = abs(cell.x - target.x) + abs(cell.y - target.y)
		if to_target <= atk_range:
			var from_start: int = abs(cell.x - from.x) + abs(cell.y - from.y)
			if from_start < best_dist:
				best_dist = from_start
				best_cell = cell
	return best_cell

# ---------------------------------------------------------------------------
# Combat (public so EnemyAI can call it)
# ---------------------------------------------------------------------------

func perform_combat(attacker: Unit, defender: Unit) -> void:
	if attacker.has_attacked:
		return
	CombatResolver.resolve(attacker, defender)
	attacker.set_attacked()

# ---------------------------------------------------------------------------
# Query helpers
# ---------------------------------------------------------------------------

func get_unit_at(cell: Vector2i) -> Unit:
	for unit in units:
		if is_instance_valid(unit) and unit.grid_cell == cell:
			return unit
	return null

# ---------------------------------------------------------------------------
# Unit death
# ---------------------------------------------------------------------------

func _on_unit_died(unit: Unit) -> void:
	units.erase(unit)
	player_units.erase(unit)
	enemy_units.erase(unit)
	grid_mgr.set_cell_solid(unit.grid_cell, false)
	unit.queue_free()
	TurnManager.check_end_conditions()

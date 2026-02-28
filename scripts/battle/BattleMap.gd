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
	# Player side (left)
	_spawn(KNIGHT_DATA,  Vector2i(1, 1), true)
	_spawn(ARCHER_DATA,  Vector2i(1, 3), true)
	_spawn(MAGE_DATA,    Vector2i(1, 5), true)
	# Enemy side (right)
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
# Input — drag & drop
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

func _begin_drag(world_pos: Vector2) -> void:
	var cell := grid_mgr.world_to_grid(world_pos)
	var unit := get_unit_at(cell)

	if not unit or not unit.is_player_unit or unit.has_moved:
		return

	_dragged_unit = unit
	_original_cell = unit.grid_cell

	# Compute ally cells to block (unless unit can jump)
	var ally_cells: Array = []
	for u in player_units:
		if u != unit:
			ally_cells.append(u.grid_cell)

	_reachable_cells = grid_mgr.get_reachable_cells(
		unit.grid_cell,
		unit.data.move_range,
		unit.data.can_jump_allies,
		ally_cells
	)
	highlight_lyr.show_reachable(_reachable_cells)
	unit.start_drag()

func _end_drag(world_pos: Vector2) -> void:
	if not _dragged_unit:
		return

	var target_cell := grid_mgr.world_to_grid(world_pos)
	highlight_lyr.clear()

	var is_valid := (
		target_cell in _reachable_cells
		and target_cell != _original_cell
		and get_unit_at(target_cell) == null
	)

	_dragged_unit.end_drag()

	if is_valid:
		_commit_move(_dragged_unit, target_cell)
	else:
		# Snap back to original position
		_dragged_unit.position = grid_mgr.grid_to_world(_original_cell)

	_dragged_unit = null
	_reachable_cells = []

func _commit_move(unit: Unit, cell: Vector2i) -> void:
	grid_mgr.set_cell_solid(_original_cell, false)
	grid_mgr.set_cell_solid(cell, true)

	var dest := grid_mgr.grid_to_world(cell)
	unit.grid_cell = cell

	var tween := create_tween()
	tween.tween_property(unit, "position", dest, 0.10)
	unit.set_moved()

	# Check for attackable enemies after move
	_check_attack(unit)

func _check_attack(unit: Unit) -> void:
	if unit.has_attacked:
		return
	for enemy in enemy_units:
		if not is_instance_valid(enemy):
			continue
		var dist: int = abs(unit.grid_cell.x - enemy.grid_cell.x) + abs(unit.grid_cell.y - enemy.grid_cell.y)
		if dist <= unit.data.attack_range:
			perform_combat(unit, enemy)
			break

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

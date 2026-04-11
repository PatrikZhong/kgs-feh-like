extends Node2D

const _BattleCam := preload("res://scripts/battle/BattleCamera.gd")

const UNIT_SCENE := preload("res://scenes/battle/Unit.tscn")
const KNIGHT_DATA      := preload("res://resources/units/KnightData.tres")
const CAVALRY_DATA     := preload("res://resources/units/CavalryData.tres")
const ARCHER_DATA      := preload("res://resources/units/ArcherData.tres")
const MAGE_DATA        := preload("res://resources/units/MageData.tres")
const ARMORED_ORC_DATA := preload("res://resources/units/ArmoredOrcData.tres")

## Enemy spawn positions per battle node (wraps if more nodes than entries).
const BATTLE_ENEMY_SPAWNS: Array = [
	[Vector2i(6, 2), Vector2i(6, 4), Vector2i(6, 6)],  # node 0 — Tutorial
	[Vector2i(7, 1), Vector2i(5, 3), Vector2i(7, 6)],  # node 1 — Forest Path
	[Vector2i(7, 0), Vector2i(6, 4), Vector2i(7, 7)],  # node 2 — River Ford
]

## All units on the map.
var units: Array[Unit] = []
var player_units: Array[Unit] = []
var enemy_units: Array[Unit] = []

# Drag state
var _dragged_unit: Unit = null
var _inspected_enemy: Unit = null
var _threat_visible: bool = true
var _original_cell: Vector2i = Vector2i.ZERO
var _reachable_cells: Array[Vector2i] = []
var _extended_attack_cells: Array[Vector2i] = []  # orange: attackable from any move cell
var _last_hovered_move_cell: Vector2i = Vector2i.ZERO  # last blue tile the cursor touched

# Drag overlay: ghost afterimage + directional arrows
var _ghost: Node2D = null
var _drag_arrow: Line2D = null
var _drag_arrowhead: Polygon2D = null
var _attack_arrow: Line2D = null
var _attack_arrowhead: Polygon2D = null

# Path tracing for bending arrow
var _arrow_path: Array[Vector2i] = []

# Non-null when cursor hovers an orange enemy cell
var _hovered_attack_target: Unit = null

@onready var grid_mgr: GridManager = $GridManager
@onready var highlight_lyr: HighlightLayer = $HighlightLayer
@onready var units_layer: Node2D = $UnitsLayer
@onready var spawners_layer: Node2D = $SpawnersLayer
@onready var _cam: _BattleCam = $Camera2D

func _ready() -> void:
	TurnManager.start_battle(self)
	_fit_camera()
	_place_test_units()
	TurnManager.turn_changed.connect(_on_turn_changed)
	$HUD.threat_toggled.connect(_on_threat_toggled)
	_refresh_enemy_threat()

## Fit the camera so the full grid is visible above the HUD bar, then hand off
## to BattleCamera which handles panning and scroll-zoom from that point on.
func _fit_camera() -> void:
	var world_size    := grid_mgr.grid_world_size()
	var viewport_size := get_viewport().get_visible_rect().size
	var usable        := Vector2(viewport_size.x,
								 viewport_size.y - _BattleCam.HUD_HEIGHT)
	var zoom_x: float = floor(usable.x / world_size.x)
	var zoom_y: float = floor(usable.y / world_size.y)
	var z := maxf(1.0, minf(zoom_x, zoom_y))
	_cam.setup(grid_mgr.grid_world_center(), world_size, z)

# ---------------------------------------------------------------------------
# Unit placement
# ---------------------------------------------------------------------------

func _place_test_units() -> void:
	var spawners: Array = spawners_layer.get_children().filter(
			func(c: Node) -> bool: return c is UnitSpawner and c.unit_data != null)

	if spawners.size() > 0:
		for s: UnitSpawner in spawners:
			_spawn(s.unit_data, s.cell, s.is_player_unit)
	else:
		push_warning("BattleMap: SpawnersLayer is empty — using hardcoded fallback layout.")
		_spawn(KNIGHT_DATA, Vector2i(1, 1), true)
		_spawn(ARCHER_DATA, Vector2i(1, 3), true)
		_spawn(MAGE_DATA,   Vector2i(1, 5), true)
		var spawns: Array = BATTLE_ENEMY_SPAWNS[SaveData.current_battle_id % BATTLE_ENEMY_SPAWNS.size()]
		for cell: Vector2i in spawns:
			_spawn(ARMORED_ORC_DATA, cell, false)

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
	elif event is InputEventMouseMotion and not _dragged_unit:
		var cell := grid_mgr.world_to_grid(get_global_mouse_position())
		var hovered := get_unit_at(cell)
		if hovered and not hovered.is_player_unit:
			if hovered != _inspected_enemy:
				_inspect_enemy(hovered)
		elif _inspected_enemy:
			_clear_inspection()
	elif event is InputEventMouseMotion and _dragged_unit:
		var hovered := grid_mgr.world_to_grid(get_global_mouse_position())

		# Track last valid blue (movement) tile and build bending path.
		if hovered in _reachable_cells and hovered not in _extended_attack_cells:
			_last_hovered_move_cell = hovered
			var idx := _arrow_path.find(hovered)
			if idx >= 0:
				_arrow_path = _arrow_path.slice(0, idx + 1)
			else:
				_arrow_path.append(hovered)

		# Track whether cursor is over an attackable enemy.
		if hovered in _extended_attack_cells:
			var t := get_unit_at(hovered)
			_hovered_attack_target = t if (t and not t.is_player_unit) else null
		else:
			_hovered_attack_target = null

		# Ghost: freeze at movement tile when aiming at an enemy, else follow cursor.
		if _ghost:
			if _hovered_attack_target:
				_ghost.position = units_layer.to_local(
						grid_mgr.grid_to_world(_last_hovered_move_cell))
			else:
				_ghost.position = units_layer.to_local(get_global_mouse_position())

		_update_drag_arrow()

# ---------------------------------------------------------------------------
# Drag & drop
# ---------------------------------------------------------------------------

func _begin_drag(world_pos: Vector2) -> void:
	var cell := grid_mgr.world_to_grid(world_pos)
	var unit := get_unit_at(cell)

	if not unit or not unit.is_player_unit or unit.has_moved:
		return

	_cam.panning_locked = true
	_clear_inspection()

	_dragged_unit = unit
	_original_cell = unit.grid_cell
	_last_hovered_move_cell = unit.grid_cell
	_arrow_path = [unit.grid_cell]

	var ally_cells: Array = []
	for u in player_units:
		if u != unit:
			ally_cells.append(u.grid_cell)

	_reachable_cells = grid_mgr.get_reachable_cells(
		unit.grid_cell, unit.data.move_range, unit.data.can_jump_allies, ally_cells
	)
	_extended_attack_cells = _get_extended_attack_cells(_reachable_cells, unit.attack_range)

	# Enemies that sit inside movement range are also valid attack targets.
	# The geometric orange ring excludes reachable cells, so we add them manually.
	for u in enemy_units:
		if is_instance_valid(u) and u.grid_cell in _reachable_cells \
				and u.grid_cell not in _extended_attack_cells:
			_extended_attack_cells.append(u.grid_cell)

	highlight_lyr.show_move_and_attack(_reachable_cells, _extended_attack_cells)
	unit.start_drag()

	# Ghost afterimage — follows the cursor while dragging.
	_ghost = Node2D.new()
	_ghost.z_index = 20
	var gs := unit.make_ghost_sprite()
	if gs:
		_ghost.add_child(gs)
	units_layer.add_child(_ghost)
	_ghost.position = grid_mgr.grid_to_world(_original_cell)

	# Arrow from origin to the proposed landing tile.
	var origin := grid_mgr.grid_to_world(_original_cell)
	_drag_arrow = Line2D.new()
	_drag_arrow.width = 3.0
	_drag_arrow.default_color = Color(1.0, 0.95, 0.3, 0.9)
	_drag_arrow.z_index = 1
	_drag_arrow.add_point(origin)
	_drag_arrow.add_point(origin)
	add_child(_drag_arrow)

	_drag_arrowhead = Polygon2D.new()
	_drag_arrowhead.color = Color(1.0, 0.95, 0.3, 0.9)
	_drag_arrowhead.z_index = 1
	add_child(_drag_arrowhead)

	_attack_arrow = Line2D.new()
	_attack_arrow.width = 3.0
	_attack_arrow.default_color = Color(1.0, 0.35, 0.1, 0.9)
	_attack_arrow.z_index = 1
	add_child(_attack_arrow)

	_attack_arrowhead = Polygon2D.new()
	_attack_arrowhead.color = Color(1.0, 0.35, 0.1, 0.9)
	_attack_arrowhead.z_index = 1
	add_child(_attack_arrowhead)

func _end_drag(world_pos: Vector2) -> void:
	if not _dragged_unit:
		return

	_cam.panning_locked = false
	# Clean up ghost and arrow overlay.
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	if _drag_arrow:
		_drag_arrow.queue_free()
		_drag_arrow = null
	if _drag_arrowhead:
		_drag_arrowhead.queue_free()
		_drag_arrowhead = null
	if _attack_arrow:
		_attack_arrow.queue_free()
		_attack_arrow = null
	if _attack_arrowhead:
		_attack_arrowhead.queue_free()
		_attack_arrowhead = null

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
			var best_cell := _pick_attacker_cell(drop_cell, unit)
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
	_last_hovered_move_cell = Vector2i.ZERO
	_arrow_path = []
	_hovered_attack_target = null

func _update_drag_arrow() -> void:
	if not _drag_arrow or not _drag_arrowhead:
		return

	# --- Movement arrow: trace the actual path of visited cells ---
	var pts := PackedVector2Array()
	for cell in _arrow_path:
		pts.append(grid_mgr.grid_to_world(cell))
	_drag_arrow.points = pts

	if _arrow_path.size() >= 2:
		var to      := grid_mgr.grid_to_world(_arrow_path[-1])
		var from_pt := grid_mgr.grid_to_world(_arrow_path[-2])
		var dir  := (to - from_pt).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var hs   := 6.0
		_drag_arrowhead.polygon = PackedVector2Array([
			to + dir * hs * 1.5,
			to - dir * hs + perp * hs,
			to - dir * hs - perp * hs,
		])
	else:
		_drag_arrowhead.polygon = PackedVector2Array()

	# --- Attack arrow: from movement tile toward hovered enemy ---
	if _hovered_attack_target and _attack_arrow:
		var a := grid_mgr.grid_to_world(_last_hovered_move_cell)
		var b := grid_mgr.grid_to_world(_hovered_attack_target.grid_cell)
		_attack_arrow.points = PackedVector2Array([a, b])
		var dir  := (b - a).normalized()
		var perp := Vector2(-dir.y, dir.x)
		var hs   := 6.0
		_attack_arrowhead.polygon = PackedVector2Array([
			b + dir * hs * 1.5,
			b - dir * hs + perp * hs,
			b - dir * hs - perp * hs,
		])
	else:
		if _attack_arrow:
			_attack_arrow.points = PackedVector2Array()
		if _attack_arrowhead:
			_attack_arrowhead.polygon = PackedVector2Array()

func _commit_move(unit: Unit, cell: Vector2i) -> void:
	grid_mgr.set_cell_solid(_original_cell, false)
	grid_mgr.set_cell_solid(cell, true)
	unit.grid_cell = cell
	var faction := "Player" if unit.is_player_unit else "Enemy"
	print("[%s %s] moved to %s" % [faction, unit.data.class_label(), str(cell)])
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

## Returns the cell the attacker should land on.
## Prefers the last blue tile the cursor touched (player-directed approach angle).
## Falls back to minimum-movement logic if that cell is out of attack range.
func _pick_attacker_cell(target_cell: Vector2i, unit: Unit) -> Vector2i:
	var to_target: int = abs(_last_hovered_move_cell.x - target_cell.x) \
			+ abs(_last_hovered_move_cell.y - target_cell.y)
	var occupant := get_unit_at(_last_hovered_move_cell)
	var cell_free := occupant == null or occupant == unit
	if cell_free and to_target == unit.attack_range:
		return _last_hovered_move_cell
	return _find_best_attacker_cell(_original_cell, target_cell, _reachable_cells, unit.attack_range)

## Reachable cell closest to `from` that is within `atk_range` of `target`.
## Pass 1 prefers cells at exactly max range; Pass 2 falls back to any valid range.
func _find_best_attacker_cell(
		from: Vector2i,
		target: Vector2i,
		reachable: Array[Vector2i],
		atk_range: int) -> Vector2i:

	var best_cell := from
	var best_dist := INF

	# Pass 1: prefer exact max range.
	for cell in reachable:
		var to_target: int = abs(cell.x - target.x) + abs(cell.y - target.y)
		if to_target == atk_range:
			var d: int = abs(cell.x - from.x) + abs(cell.y - from.y)
			if d < best_dist:
				best_dist = d
				best_cell = cell

	# Pass 2: fallback — accept any cell within range.
	if best_cell == from:
		best_dist = INF
		for cell in reachable:
			var to_target: int = abs(cell.x - target.x) + abs(cell.y - target.y)
			if to_target >= 1 and to_target <= atk_range:
				var d: int = abs(cell.x - from.x) + abs(cell.y - from.y)
				if d < best_dist:
					best_dist = d
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
	if not unit.is_player_unit:
		_refresh_enemy_threat()
	TurnManager.check_end_conditions()

# ---------------------------------------------------------------------------
# Threat range
# ---------------------------------------------------------------------------

func _refresh_enemy_threat() -> void:
	if not _threat_visible:
		highlight_lyr.set_threat([])
		return
	for e in enemy_units:
		if is_instance_valid(e):
			grid_mgr.set_cell_solid(e.grid_cell, false)

	var seen: Dictionary = {}
	var player_cells: Array = player_units.map(func(u): return u.grid_cell)

	for enemy in enemy_units:
		if not is_instance_valid(enemy):
			continue
		var reachable := grid_mgr.get_reachable_cells(
			enemy.grid_cell, enemy.data.move_range, false, player_cells)
		var attack_cells := _get_extended_attack_cells(reachable, enemy.attack_range)
		for cell in reachable:
			seen[cell] = true
		for cell in attack_cells:
			seen[cell] = true

	for e in enemy_units:
		if is_instance_valid(e):
			grid_mgr.set_cell_solid(e.grid_cell, true)

	var threat: Array[Vector2i] = []
	for cell in seen:
		threat.append(cell)
	highlight_lyr.set_threat(threat)

func _on_turn_changed(state) -> void:
	if state == TurnManager.State.PLAYER_TURN:
		_refresh_enemy_threat()

func _on_threat_toggled(on: bool) -> void:
	_threat_visible = on
	if on:
		_refresh_enemy_threat()
	else:
		highlight_lyr.set_threat([])

func _inspect_enemy(enemy: Unit) -> void:
	_inspected_enemy = enemy
	var player_cells: Array = player_units.map(func(u): return u.grid_cell)
	grid_mgr.set_cell_solid(enemy.grid_cell, false)
	var move_cells := grid_mgr.get_reachable_cells(
		enemy.grid_cell, enemy.data.move_range, false, player_cells)
	grid_mgr.set_cell_solid(enemy.grid_cell, true)
	var attack_cells := _get_extended_attack_cells(move_cells, enemy.attack_range)
	highlight_lyr.show_move_and_attack(move_cells, attack_cells)

func _clear_inspection() -> void:
	_inspected_enemy = null
	highlight_lyr.clear()

## Autoload: EnemyAI
## Simple greedy AI: each enemy moves toward the nearest player unit and attacks.
## Parameters are untyped to avoid class-name resolution issues in autoloads.
extends Node

const ACTION_DELAY := 0.35  # seconds between enemy actions so the player can follow

func execute_turn() -> void:
	var map = TurnManager.battle_map
	if not map:
		TurnManager.end_enemy_turn()
		return

	# Snapshot list so removals during iteration don't skip units
	var enemies: Array = map.enemy_units.duplicate()

	for enemy in enemies:
		if not is_instance_valid(enemy):
			continue
		await get_tree().create_timer(ACTION_DELAY).timeout
		_act(enemy, map)

	TurnManager.end_enemy_turn()

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _act(enemy, map) -> void:
	if map.player_units.is_empty():
		return

	var nearest = _find_nearest(enemy, map.player_units)
	if not nearest:
		return

	if not enemy.has_moved:
		_move_toward(enemy, nearest, map)

	if not enemy.has_attacked:
		var dist: int = _manhattan(enemy.grid_cell, nearest.grid_cell)
		if dist <= enemy.data.attack_range:
			map.perform_combat(enemy, nearest)

func _find_nearest(enemy, player_units: Array):
	var nearest = null
	var min_dist := INF
	for pu in player_units:
		if not is_instance_valid(pu):
			continue
		var d: int = _manhattan(enemy.grid_cell, pu.grid_cell)
		if d < min_dist:
			min_dist = d
			nearest = pu
	return nearest

func _move_toward(enemy, target, map) -> void:
	var grid_mgr = map.grid_mgr

	# Temporarily unblock the enemy's own cell for pathfinding
	grid_mgr.set_cell_solid(enemy.grid_cell, false)
	var path: Array = grid_mgr.get_path_to(enemy.grid_cell, target.grid_cell)
	grid_mgr.set_cell_solid(enemy.grid_cell, true)

	if path.is_empty():
		return

	# Walk as many steps as allowed; stop before stepping onto another unit
	var best_cell: Vector2i = enemy.grid_cell
	var steps: int = mini(enemy.data.move_range, path.size() - 1)
	for i in range(1, steps + 1):
		var candidate: Vector2i = path[i]
		if map.get_unit_at(candidate) != null:
			break
		best_cell = candidate

	if best_cell == enemy.grid_cell:
		return

	grid_mgr.set_cell_solid(enemy.grid_cell, false)
	enemy.snap_to_cell(best_cell, grid_mgr)
	grid_mgr.set_cell_solid(best_cell, true)
	enemy.set_moved()

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

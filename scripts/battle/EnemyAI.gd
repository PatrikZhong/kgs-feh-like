## Autoload: EnemyAI
## Simple greedy AI: each enemy moves toward the nearest player unit and attacks.
## Parameters are untyped to avoid class-name resolution issues in autoloads.
extends Node

const ACTION_DELAY := 0.35  # seconds before the enemy acts so the player can follow

## Cycles through enemies one per player turn.
var _next_idx: int = 0

func execute_turn() -> void:
	var map = TurnManager.battle_map
	if not map or map.enemy_units.is_empty():
		TurnManager.end_enemy_turn()
		return

	var enemies: Array = map.enemy_units

	# Clamp index in case enemies have died since last turn
	if _next_idx >= enemies.size():
		_next_idx = 0

	var enemy = enemies[_next_idx]
	_next_idx = (_next_idx + 1) % enemies.size()

	await get_tree().create_timer(ACTION_DELAY).timeout

	if is_instance_valid(enemy):
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

	# Temporarily unblock both the enemy's cell and the target's cell so
	# AStarGrid2D can find a path (it refuses to path to a solid destination)
	grid_mgr.set_cell_solid(enemy.grid_cell, false)
	grid_mgr.set_cell_solid(target.grid_cell, false)
	var path: Array = grid_mgr.get_astar_path(enemy.grid_cell, target.grid_cell)
	grid_mgr.set_cell_solid(enemy.grid_cell, true)
	grid_mgr.set_cell_solid(target.grid_cell, true)

	if path.is_empty():
		return

	# Move exactly one tile toward the target
	var best_cell: Vector2i = enemy.grid_cell
	var steps: int = mini(1, path.size() - 1)
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

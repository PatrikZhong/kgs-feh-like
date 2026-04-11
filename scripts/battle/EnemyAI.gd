## Autoload: EnemyAI
## Simple greedy AI: each enemy moves toward the nearest player unit and attacks.
extends Node

const _Unit := preload("res://scripts/battle/Unit.gd")
const _BattleMap := preload("res://scripts/battle/BattleMap.gd")

const ACTION_DELAY := 0.35  # seconds before the enemy acts so the player can follow

func execute_turn() -> void:
	var map: _BattleMap = TurnManager.battle_map
	if not map or map.enemy_units.is_empty():
		TurnManager.end_enemy_turn()
		return

	# Find the first enemy that hasn't moved this round
	var enemy: _Unit = null
	for e: _Unit in map.enemy_units:
		if is_instance_valid(e) and not e.has_moved:
			enemy = e
			break

	if not enemy:
		TurnManager.end_enemy_turn()
		return

	await get_tree().create_timer(ACTION_DELAY).timeout

	if is_instance_valid(enemy):
		_act(enemy, map)
		# Always mark the enemy as spent after its turn, even if it couldn't
		# move (e.g. adjacent to a player unit — target cell is occupied so
		# _move_toward returns early without calling set_moved).
		if is_instance_valid(enemy) and not enemy.has_moved:
			enemy.set_moved()

	TurnManager.end_enemy_turn()

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _act(enemy: _Unit, map: _BattleMap) -> void:
	if map.player_units.is_empty():
		return

	var nearest: _Unit = _find_nearest(enemy, map.player_units)
	if not nearest:
		return

	if not enemy.has_moved:
		_move_toward(enemy, nearest, map)

	if not enemy.has_attacked:
		var dist: int = _manhattan(enemy.grid_cell, nearest.grid_cell)
		if dist <= enemy.data.attack_range:
			map.perform_combat(enemy, nearest)

func _find_nearest(enemy: _Unit, player_units: Array[_Unit]) -> _Unit:
	var nearest: _Unit = null
	var min_dist := INF
	for pu: _Unit in player_units:
		if not is_instance_valid(pu):
			continue
		var d: int = _manhattan(enemy.grid_cell, pu.grid_cell)
		if d < min_dist:
			min_dist = d
			nearest = pu
	return nearest

func _move_toward(enemy: _Unit, target: _Unit, map: _BattleMap) -> void:
	var grid_mgr: GridManager = map.grid_mgr

	# Temporarily unblock both the enemy's cell and the target's cell so
	# AStarGrid2D can find a path (it refuses to path to a solid destination)
	grid_mgr.set_cell_solid(enemy.grid_cell, false)
	grid_mgr.set_cell_solid(target.grid_cell, false)
	var path: Array = grid_mgr.get_astar_path(enemy.grid_cell, target.grid_cell)
	grid_mgr.set_cell_solid(enemy.grid_cell, true)
	grid_mgr.set_cell_solid(target.grid_cell, true)

	if path.is_empty():
		return

	# Walk up to the enemy's full move_range along the path, stopping if blocked.
	var best_cell: Vector2i = enemy.grid_cell
	var steps: int = mini(enemy.data.move_range, path.size() - 1)
	for i in range(1, steps + 1):
		var candidate: Vector2i = path[i]
		if map.get_unit_at(candidate) != null:
			break
		best_cell = candidate

	if best_cell == enemy.grid_cell:
		return

	map.move_unit_instant(enemy, best_cell)
	enemy.set_moved()
	print("[Enemy %s] moved to %s" % [enemy.data.class_label(), str(best_cell)])

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

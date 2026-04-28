## Autoload: EnemyAI
## Greedy AI: moves the given enemy toward the nearest player unit and attacks.
## Called by TurnManager with the specific unit whose queue slot is active.
extends Node

const _Unit     := preload("res://scripts/battle/Unit.gd")
const _BattleMap := preload("res://scripts/battle/BattleMap.gd")

## Pause before the enemy acts so the player can register intent (seconds).
const ACTION_DELAY         := 0.40
## How long the attack arrow is shown before combat resolves (seconds).
const ATTACK_DISPLAY_DELAY := 0.30

func execute_turn(unit: _Unit) -> void:
	var map: _BattleMap = TurnManager.battle_map
	if not map or not is_instance_valid(unit):
		TurnManager.end_enemy_turn()
		return

	await get_tree().create_timer(ACTION_DELAY).timeout

	if is_instance_valid(unit):
		await _act(unit, map)
		# Fallback: if the unit still hasn't been marked as moved (e.g. no path,
		# no valid attack) force it spent so the round can advance.
		if is_instance_valid(unit) and not unit.has_moved:
			unit.set_moved()

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
		await _move_toward(enemy, nearest, map)

	# Attack if the nearest target is still valid and in range.
	if not enemy.has_attacked and is_instance_valid(nearest):
		var dist: int = _manhattan(enemy.grid_cell, nearest.grid_cell)
		if dist <= enemy.data.attack_range:
			map.show_enemy_attack_arrow(enemy.grid_cell, nearest.grid_cell)
			await get_tree().create_timer(ATTACK_DISPLAY_DELAY).timeout
			if is_instance_valid(enemy) and is_instance_valid(nearest):
				map.perform_combat(enemy, nearest)
			map.clear_enemy_arrows()

func _move_toward(enemy: _Unit, target: _Unit, map: _BattleMap) -> void:
	var grid_mgr: GridManager = map.grid_mgr

	# Temporarily unblock both cells so A* can path between them.
	grid_mgr.set_cell_solid(enemy.grid_cell, false)
	grid_mgr.set_cell_solid(target.grid_cell, false)
	var path: Array[Vector2i] = grid_mgr.get_astar_path(enemy.grid_cell, target.grid_cell)
	grid_mgr.set_cell_solid(enemy.grid_cell, true)
	grid_mgr.set_cell_solid(target.grid_cell, true)

	if path.is_empty():
		return

	# Walk as many steps as possible up to move_range, stopping before occupied cells.
	var max_steps: int = mini(enemy.data.move_range, path.size() - 1)
	var actual_steps: int = 0
	for i in range(1, max_steps + 1):
		if map.get_unit_at(path[i]) != null:
			break
		actual_steps = i

	if actual_steps == 0:
		return

	# Build the traversed path slice [start .. dest] for arrow and animation.
	var path_slice: Array[Vector2i] = []
	for i in range(actual_steps + 1):
		path_slice.append(path[i])

	map.show_enemy_arrow(path_slice)
	await map.move_unit_animated(enemy, path_slice, actual_steps)
	map.clear_enemy_arrows()
	enemy.set_moved()
	print("[Enemy %s] moved to %s" % [enemy.data.class_label(), str(path_slice[-1])])

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

func _manhattan(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)

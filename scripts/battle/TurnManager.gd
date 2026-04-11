## Autoload: TurnManager
## Alternating PLAYER ↔ ENEMY actions. A round ends when every living unit
## on both sides has moved; the turn counter then increments and all units reset.
extends Node

signal turn_changed(state: State)
signal battle_won
signal battle_lost
signal new_round(count: int)

enum State { PLACEMENT, PLAYER_TURN, ENEMY_TURN }

var current_state: State = State.PLACEMENT
var turn_count: int = 1
var battle_map = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func start_battle(map) -> void:
	battle_map = map
	turn_count = 1
	current_state = State.PLACEMENT
	turn_changed.emit(current_state)

## Called by HUD "Begin Battle" button to leave the placement phase.
func start_combat() -> void:
	if current_state != State.PLACEMENT:
		return
	current_state = State.PLAYER_TURN
	turn_changed.emit(current_state)

## Called by BattleMap after a player unit moves, or by HUD End Turn button.
func end_player_turn() -> void:
	if current_state != State.PLAYER_TURN:
		return
	if _is_battle_over():
		return
	current_state = State.ENEMY_TURN
	turn_changed.emit(current_state)
	if _any_enemy_unmoved():
		EnemyAI.execute_turn()
	else:
		end_enemy_turn()

## Called by EnemyAI after one enemy has acted.
func end_enemy_turn() -> void:
	if _is_battle_over():
		return
	if _all_player_done() and _all_enemy_done():
		_new_round()
	elif _all_player_done():
		# Player is exhausted but enemies still to act — keep going
		EnemyAI.execute_turn()
	else:
		current_state = State.PLAYER_TURN
		turn_changed.emit(current_state)

func check_end_conditions() -> void:
	if not battle_map:
		return
	if battle_map.enemy_units.is_empty():
		battle_won.emit()
	elif battle_map.player_units.is_empty():
		battle_lost.emit()

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _new_round() -> void:
	turn_count += 1
	for unit in battle_map.player_units + battle_map.enemy_units:
		if is_instance_valid(unit):
			unit.reset_turn()
	current_state = State.PLAYER_TURN
	turn_changed.emit(current_state)
	new_round.emit(turn_count)

func _is_battle_over() -> bool:
	return not battle_map \
		or battle_map.enemy_units.is_empty() \
		or battle_map.player_units.is_empty()

func _all_player_done() -> bool:
	for unit in battle_map.player_units:
		if is_instance_valid(unit) and not unit.has_moved:
			return false
	return true

func _all_enemy_done() -> bool:
	for unit in battle_map.enemy_units:
		if is_instance_valid(unit) and not unit.has_moved:
			return false
	return true

func _any_enemy_unmoved() -> bool:
	for unit in battle_map.enemy_units:
		if is_instance_valid(unit) and not unit.has_moved:
			return true
	return false

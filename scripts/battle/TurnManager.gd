## Autoload: TurnManager
## Owns the PLAYER_TURN ↔ ENEMY_TURN state machine.
extends Node

signal turn_changed(state: State)
signal battle_won
signal battle_lost

enum State { PLAYER_TURN, ENEMY_TURN }

var current_state: State = State.PLAYER_TURN
## Set by BattleMap on _ready so TurnManager can access unit lists.
var battle_map = null

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func start_battle(map) -> void:
	battle_map = map
	current_state = State.PLAYER_TURN
	emit_signal("turn_changed", current_state)

func end_player_turn() -> void:
	if current_state != State.PLAYER_TURN:
		return
	current_state = State.ENEMY_TURN
	emit_signal("turn_changed", current_state)
	_reset_units(false)
	EnemyAI.execute_turn()

func end_enemy_turn() -> void:
	if current_state != State.ENEMY_TURN:
		return
	current_state = State.PLAYER_TURN
	emit_signal("turn_changed", current_state)
	_reset_units(true)

func check_end_conditions() -> void:
	if not battle_map:
		return
	if battle_map.enemy_units.is_empty():
		emit_signal("battle_won")
	elif battle_map.player_units.is_empty():
		emit_signal("battle_lost")

# ---------------------------------------------------------------------------
# Internal
# ---------------------------------------------------------------------------

func _reset_units(is_player: bool) -> void:
	if not battle_map:
		return
	var unit_list: Array = battle_map.player_units if is_player else battle_map.enemy_units
	for unit in unit_list:
		if is_instance_valid(unit):
			unit.reset_turn()

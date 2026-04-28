## Autoload: TurnManager
## Queue-based turn order: all units act in initiative order each round.
## The active slot determines whether the player or the AI controls the next action.
extends Node

signal turn_changed(state: State)
signal queue_updated(queue: Array, active_index: int)
signal battle_won
signal battle_lost
signal new_round(count: int)

enum State { PLACEMENT, PLAYER_TURN, ENEMY_TURN, ACTING }

var current_state: State = State.PLACEMENT
var turn_count: int = 1
var battle_map = null

## Ordered list of units for the current round (sorted by initiative desc).
var _round_queue: Array = []
## Index of the unit whose slot is currently active.
var _queue_index: int = 0

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func start_battle(map) -> void:
	battle_map = map
	turn_count = 1
	_round_queue.clear()
	_queue_index = 0
	current_state = State.PLACEMENT
	turn_changed.emit(current_state)

## Called by HUD "Begin Battle" button to leave the placement phase.
func start_combat() -> void:
	if current_state != State.PLACEMENT:
		return
	_build_queue()
	_activate_current()

## Called by BattleMap after a player unit commits an action,
## or by HUD "End Turn" (which first marks all remaining player units as moved).
func end_player_turn() -> void:
	if current_state != State.PLAYER_TURN:
		return
	if _is_battle_over():
		return
	_queue_index += 1
	_activate_current()

## Called by EnemyAI after the enemy unit has finished acting.
func end_enemy_turn() -> void:
	if _is_battle_over():
		return
	_queue_index += 1
	_activate_current()

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

## Builds the round queue by sorting all living units by initiative (desc).
## Player units go before enemy units when initiative is tied.
func _build_queue() -> void:
	if not battle_map:
		return
	var all_units: Array = []
	for u in battle_map.player_units:
		if is_instance_valid(u):
			all_units.append(u)
	for u in battle_map.enemy_units:
		if is_instance_valid(u):
			all_units.append(u)
	all_units.sort_custom(func(a, b) -> bool:
		if a.data.initiative != b.data.initiative:
			return a.data.initiative > b.data.initiative
		# Same initiative: player before enemy
		return int(a.is_player_unit) > int(b.is_player_unit)
	)
	_round_queue = all_units
	_queue_index = 0

## Advances to the unit at _queue_index, skipping dead or already-moved slots.
## Starts a new round when the queue is exhausted.
func _activate_current() -> void:
	# Skip over dead or already-spent slots.
	while _queue_index < _round_queue.size():
		var u = _round_queue[_queue_index]
		if is_instance_valid(u) and not u.has_moved:
			break
		_queue_index += 1

	if _queue_index >= _round_queue.size():
		_new_round()
		return

	var actor = _round_queue[_queue_index]
	queue_updated.emit(_round_queue, _queue_index)

	if actor.is_player_unit:
		current_state = State.PLAYER_TURN
		turn_changed.emit(current_state)
	else:
		# Emit ENEMY_TURN so HUD can disable the End Turn button, then
		# switch to ACTING (blocks BattleMap input) before the coroutine starts.
		current_state = State.ENEMY_TURN
		turn_changed.emit(current_state)
		current_state = State.ACTING
		EnemyAI.execute_turn(actor)

func _new_round() -> void:
	turn_count += 1
	for unit in battle_map.player_units + battle_map.enemy_units:
		if is_instance_valid(unit):
			unit.reset_turn()
	new_round.emit(turn_count)
	_build_queue()
	_activate_current()

func _is_battle_over() -> bool:
	return not battle_map \
		or battle_map.enemy_units.is_empty() \
		or battle_map.player_units.is_empty()

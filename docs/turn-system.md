# Turn System

## State Machine

```
                    ┌──────────────────────────────────┐
                    │          PLAYER_TURN              │
                    │                                   │
                    │  Player drags and drops a unit.   │
                    │  BattleMap calls                  │
                    │  TurnManager.end_player_turn()    │
                    └──────────────┬───────────────────┘
                                   │
                    TurnManager.end_player_turn()
                                   │
                    ┌──────────────▼───────────────────┐
                    │          ENEMY_TURN               │
                    │                                   │
                    │  Any unmoved enemies?             │
                    │  → EnemyAI.execute_turn()         │
                    │  No unmoved enemies?              │
                    │  → end_enemy_turn() immediately   │
                    └──────────────┬───────────────────┘
                                   │
                    TurnManager.end_enemy_turn()
                                   │
               ┌───────────────────┼──────────────────────┐
               │                   │                      │
        all_player_done       all_player_done        player still
        AND all_enemy_done    enemies remain          has moves
               │                   │                      │
         _new_round()        EnemyAI.execute_turn()  PLAYER_TURN ◄─┘
               │              (loop until done)
      increment turn_count
      reset all units
      emit "new_round"
      PLAYER_TURN
```

## Round Lifecycle

A **round** spans the window from all units being fresh until all units have
moved. The turn counter tracks rounds (not individual moves).

```
Round N begins
  ├── All units: has_moved=false, has_attacked=false
  ├── current_state = PLAYER_TURN
  │
  ├── Player moves unit 1 → end_player_turn() → ENEMY_TURN
  │     EnemyAI acts → end_enemy_turn()
  │     player still has unmoved units → PLAYER_TURN
  │
  ├── Player moves unit 2 → end_player_turn() → ENEMY_TURN
  │     EnemyAI acts → end_enemy_turn()
  │     player still has unmoved units → PLAYER_TURN
  │
  └── Player moves last unit → end_player_turn() → ENEMY_TURN
        EnemyAI acts → end_enemy_turn()
        all_player_done AND all_enemy_done → _new_round()

Round N+1 begins (turn_count incremented, units reset)
```

The HUD "End Turn" button marks all remaining player units as moved
(`set_moved()`), then calls `TurnManager.end_player_turn()` — fast-forwarding
to the enemy phase.

## Battle End & Overworld Progression

```
TurnManager.check_end_conditions()
  ├── enemy_units empty  → emit "battle_won"
  └── player_units empty → emit "battle_lost"

HUD._on_battle_won()
  ├── result_panel.visible = true  ("Victory!")
  └── SaveData.unlock_after_battle(SaveData.current_battle_id)
            └── appends (current_battle_id + 1) to unlocked_node_ids

HUD._on_battle_lost()
  └── result_panel.visible = true  ("Defeat!")

HUD._on_continue_pressed()            ← Continue button on result panel
  └── get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")
```

When the player returns to the overworld, `Overworld._spawn_nodes()` reads
`SaveData.is_node_unlocked(id)` for each node. The newly unlocked node now
renders in gold and its button is enabled.

`SaveData.current_battle_id` is set by `Overworld._on_node_clicked(id)` before
the scene transition, so the next battle inherits the correct node index for
tileset selection and enemy spawn positions.

## EnemyAI Coroutine

```
EnemyAI.execute_turn()   [async coroutine — called fire-and-forget]
  │
  ├── get battle_map from TurnManager
  ├── find first enemy where not has_moved
  │    └── none found → TurnManager.end_enemy_turn(); return
  │
  ├── await 0.35 s          ← visible delay (ACTION_DELAY) so player can follow action
  │
  ├── _act(enemy, map)
  │         │
  │         ├── _find_nearest(enemy, player_units) → nearest player
  │         │         └── linear scan, Manhattan distance
  │         │
  │         ├── if not has_moved:
  │         │    _move_toward(enemy, nearest, map)
  │         │         │
  │         │         ├── temporarily unblock enemy cell + target cell
  │         │         │    (AStarGrid2D refuses solid destinations)
  │         │         ├── grid_mgr.get_astar_path(enemy.cell, target.cell)
  │         │         ├── restore solid state
  │         │         │
  │         │         ├── walk path up to 1 step (current AI cap)
  │         │         │    skip step if occupied
  │         │         └── snap_to_cell(best_cell) + enemy.set_moved()
  │         │
  │         └── if not has_attacked:
  │              dist = manhattan(enemy.cell, nearest.cell)
  │              if dist <= enemy.data.attack_range:
  │                map.perform_combat(enemy, nearest)
  │
  ├── anti-freeze guard: if enemy still has_moved == false after _act()
  │    (e.g. blocked on all sides, path leads to occupied cell)
  │    → enemy.set_moved()   ← forces spent so the round can advance
  │
  └── TurnManager.end_enemy_turn()
```

**Current AI limitation:** enemies move exactly 1 tile per turn regardless of
`move_range` (`steps = mini(1, path.size() - 1)`). The pathfinding works
correctly for longer paths; expanding AI to use full move range means
iterating `min(move_range, path.size()-1)` steps and checking occupancy at each.

## Predicates (TurnManager internals)

| Function              | Returns true when…                                 |
|-----------------------|----------------------------------------------------|
| `_all_player_done()`  | Every living player unit has `has_moved == true`   |
| `_all_enemy_done()`   | Every living enemy unit has `has_moved == true`    |
| `_any_enemy_unmoved()`| At least one living enemy has `has_moved == false` |
| `_is_battle_over()`   | Either army's unit list is empty                   |

## Signals

| Signal                | Emitted by               | Consumed by                                           |
|-----------------------|--------------------------|-------------------------------------------------------|
| `turn_changed(state)` | end_player/enemy_turn    | HUD (turn label + End Turn button enable/disable)     |
| `new_round(count)`    | _new_round()             | HUD (turn label refresh)                              |
| `battle_won`          | check_end_conditions()   | HUD → shows modal, calls SaveData.unlock_after_battle |
| `battle_lost`         | check_end_conditions()   | HUD → shows modal                                     |

## HUD Signals

| Signal                   | Emitted by           | Consumed by                                     |
|--------------------------|----------------------|-------------------------------------------------|
| `threat_toggled(on:bool)`| HUD ThreatToggleButton | BattleMap._on_threat_toggled → _refresh_enemy_threat or clear |

# Turn System

## State Machine

```
                    ┌───────────────────────────────────┐
                    │           PLACEMENT               │
                    │  Player repositions units freely.  │
                    │  HUD "Begin Battle" →             │
                    │  TurnManager.start_combat()        │
                    └──────────────┬────────────────────┘
                                   │
                    _build_queue() + _activate_current()
                                   │
               ┌───────────────────┼──────────────────────┐
               │ current slot is   │ current slot is       │
               │ a player unit     │ an enemy unit         │
               ▼                   ▼                       │
        PLAYER_TURN           ENEMY_TURN ──► ACTING        │
               │              (turn_changed  (current_state│
               │               emitted)      after signal) │
               │                   │                       │
      player drags    EnemyAI.execute_turn(actor)          │
      and drops       [coroutine, awaits animation]        │
               │                   │                       │
        end_player_turn()    end_enemy_turn()              │
               │                   │                       │
               └──────── _queue_index++ ─────────────────►┘
                         _activate_current()
                                   │
                         queue exhausted?
                         ┌─────Yes─┤
                         │         │ No → next slot (back to branch above)
                    _new_round()
                    reset all units
                    _build_queue()
                    _activate_current()
```

## Queue Construction

`_build_queue()` runs at `start_combat()` and at the start of every new round.

1. Collect all living player units, then all living enemy units into a flat array.
2. Sort descending by `unit.data.initiative`.  
   Tie-break: player units go before enemy units at the same initiative.
3. Set `_queue_index = 0`.
4. Emit `queue_updated(queue, 0)` via `_activate_current()`.

| Class       | Initiative |
|-------------|-----------|
| Cavalry     | 8         |
| Mage        | 7         |
| Archer      | 6         |
| Knight      | 5         |
| Armored Orc | 4         |

## Round Lifecycle

```
Round N begins
  ├── _build_queue(): [CavalryP, MageP, ArcherP, KnightP, OrcE, OrcE, OrcE]
  │   (example — actual order depends on who is still alive)
  │
  ├── Slot 0 (Cavalry — player): PLAYER_TURN
  │   Player drags Cavalry → end_player_turn() → slot 1
  │
  ├── Slot 1 (Mage — player): PLAYER_TURN
  │   Player drags Mage → end_player_turn() → slot 2
  │
  ├── Slot 2 (Archer — player): PLAYER_TURN
  │   ...
  │
  ├── Slot 3 (Knight — player): PLAYER_TURN
  │   ...
  │
  ├── Slot 4 (Orc 1 — enemy): ENEMY_TURN → ACTING
  │   EnemyAI coroutine: delay → move (animated) → attack → end_enemy_turn()
  │
  ├── Slot 5 (Orc 2 — enemy): ENEMY_TURN → ACTING
  │   ...
  │
  └── Slot 6 (Orc 3 — enemy): ENEMY_TURN → ACTING
        end_enemy_turn() → _queue_index == queue.size() → _new_round()

Round N+1 begins
```

## Active Highlight / Inactive Dim

When `queue_updated` fires, `BattleMap._on_queue_updated()`:
- Calls `unit.set_inactive_dim()` on every living unit  
  (`INACTIVE_MODULATE = Color(0.55, 0.55, 0.55, 1.0)` — already-spent units skip via `has_moved` guard)
- Calls `unit.set_active_highlight()` on `queue[active_index]`  
  (restores `_animated_sprite.modulate = Color.WHITE`)

This makes it visually clear whose turn it is without displaying numbers on the grid.

## HUD Queue Bar

`TurnManager.queue_updated(queue: Array, active_index: int)` is consumed by `HUD._on_queue_updated`.

The queue banner at the top of the screen rebuilds its icon row on every emission:
- One `PanelContainer` per living unit in the queue (dead slots are skipped).
- Blue background for player units, red for enemies.
- Active slot has a white `QUEUE_ACTIVE_BORDER`-wide border.
- Inactive slots are at `QUEUE_INACTIVE_ALPHA` transparency.

All style constants are defined at the top of `HUD.gd` and require no scene edits to change.

## EnemyAI Coroutine

```
EnemyAI.execute_turn(unit: Unit)  [coroutine — called fire-and-forget by TurnManager]
  │
  ├── validity check (unit, map) — bail to end_enemy_turn() if invalid
  │
  ├── await ACTION_DELAY (0.40 s) — player sees the active highlight before the move
  │
  ├── await _act(unit, map)
  │       │
  │       ├── _find_nearest(unit, player_units) → nearest player
  │       │
  │       ├── if not has_moved:
  │       │    await _move_toward(unit, nearest, map)
  │       │         │
  │       │         ├── get_astar_path (temporarily unblock src+dst)
  │       │         ├── walk up to move_range steps, stop before occupied cells
  │       │         ├── BattleMap.show_enemy_arrow(path_slice)   ← yellow Line2D
  │       │         ├── await BattleMap.move_unit_animated(...)   ← 70 ms/cell tween
  │       │         ├── BattleMap.clear_enemy_arrows()
  │       │         └── unit.set_moved()
  │       │
  │       └── if not has_attacked and dist <= attack_range:
  │            BattleMap.show_enemy_attack_arrow(from, to)   ← orange Line2D
  │            await ATTACK_DISPLAY_DELAY (0.30 s)
  │            BattleMap.perform_combat(unit, nearest)
  │            BattleMap.clear_enemy_arrows()
  │
  ├── fallback: if unit still not has_moved → unit.set_moved()
  │
  └── TurnManager.end_enemy_turn()
```

**Timing constants** (top of `EnemyAI.gd`):

| Constant              | Default | Purpose                                      |
|-----------------------|---------|----------------------------------------------|
| `ACTION_DELAY`        | 0.40 s  | Pause before enemy acts (player can see who) |
| `ATTACK_DISPLAY_DELAY`| 0.30 s  | Attack arrow shown before combat resolves    |
| movement step         | 0.07 s/cell | Hard-coded in `BattleMap.move_unit_animated` |

## States Reference

| State        | Meaning                                              | Input? |
|--------------|------------------------------------------------------|--------|
| `PLACEMENT`  | Pre-battle, drag units within placement zone         | Yes    |
| `PLAYER_TURN`| Player unit's queue slot — awaiting drag             | Yes    |
| `ENEMY_TURN` | Enemy slot just activated; signal emitted for HUD    | No     |
| `ACTING`     | EnemyAI coroutine running; locks BattleMap input     | No     |

`ACTING` is set immediately after `turn_changed(ENEMY_TURN)` is emitted and before
`EnemyAI.execute_turn()` is called.  It is never emitted via `turn_changed`.

## Signals

| Signal                      | Emitted by          | Consumed by                                                 |
|-----------------------------|---------------------|-------------------------------------------------------------|
| `turn_changed(state)`       | `_activate_current` | HUD (label + button), BattleMap (`_on_turn_changed`)        |
| `queue_updated(queue, pos)` | `_activate_current` | HUD (rebuild queue bar), BattleMap (dim/highlight units)    |
| `new_round(count)`          | `_new_round()`      | HUD (label refresh)                                         |
| `battle_won`                | `check_end_conditions` | HUD → shows modal, calls SaveData.unlock_after_battle    |
| `battle_lost`               | `check_end_conditions` | HUD → shows modal                                        |

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

HUD._on_continue_pressed()
  └── get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")
```

# Battle System

## Drag-and-Drop Input Flow

```
BattleMap._unhandled_input(event)
│
│  Guard: TurnManager.current_state == PLAYER_TURN
│
├── InputEventMouseButton LEFT PRESSED
│    └── _begin_drag(world_pos)
│             │
│             ├── grid_mgr.world_to_grid(world_pos)        → cell
│             ├── get_unit_at(cell)                        → unit | null
│             ├── guard: unit exists, is_player_unit, not has_moved
│             │
│             ├── collect ally_cells (all player units except this one)
│             ├── grid_mgr.get_reachable_cells(            → _reachable_cells  [blue]
│             │       unit.grid_cell, move_range,
│             │       can_jump_allies, ally_cells)
│             ├── _get_extended_attack_cells(              → _extended_attack_cells [orange]
│             │       _reachable_cells, unit.attack_range)
│             │
│             ├── highlight_lyr.show_move_and_attack(blue, orange)
│             └── unit.start_drag()   ← raises z_index, semi-transparent
│
├── InputEventMouseMotion  (while _dragged_unit != null)
│    └── _dragged_unit.position = cursor world pos
│         (unit node moves freely under the cursor)
│
└── InputEventMouseButton LEFT RELEASED
     └── _end_drag(world_pos)
               │
               ├── grid_mgr.world_to_grid(world_pos)       → drop_cell
               ├── unit.end_drag()
               ├── highlight_lyr.clear()
               │
               ├── [A] drop_cell in _reachable_cells AND cell_free
               │         └── _commit_move(unit, drop_cell)
               │             TurnManager.end_player_turn()
               │
               ├── [B] drop_cell in _extended_attack_cells
               │    ├── get_unit_at(drop_cell)             → target
               │    ├── target exists AND is enemy?
               │    │    ├── _find_best_attacker_cell(     → best_cell
               │    │    │       _original_cell, drop_cell,
               │    │    │       _reachable_cells, attack_range)
               │    │    ├── _commit_move(unit, best_cell)
               │    │    ├── perform_combat(unit, target)
               │    │    └── TurnManager.end_player_turn()
               │    └── no enemy → cancel (snap back)
               │
               └── [C] anywhere else
                         └── unit.position = grid_mgr.grid_to_world(_original_cell)
```

## Movement Commit

```
_commit_move(unit, cell)
  │
  ├── grid_mgr.set_cell_solid(_original_cell, false)   ← free old cell
  ├── grid_mgr.set_cell_solid(cell, true)              ← claim new cell
  ├── unit.grid_cell = cell
  ├── Tween: unit.position → grid_to_world(cell)  (0.10 s)
  └── unit.set_moved()   ← has_moved = true, triggers grey-out redraw
```

## Attack Range Computation

### Extended attack cells (orange highlight)

```
_get_extended_attack_cells(reachable, atk_range) → Array[Vector2i]

For every move_cell in reachable:
  For dx in [-atk_range .. +atk_range]:
    For dy in [-atk_range .. +atk_range]:
      dist = |dx| + |dy|          ← Manhattan distance
      if dist < 1 or dist > atk_range: skip
      candidate = move_cell + (dx, dy)
      if in_bounds AND candidate NOT in reachable:
        add to result set

Returns: all cells reachable via attack from any move cell,
         excluding move cells themselves (no blue/orange overlap).
```

Example (atk_range=1, single move_cell at origin):
```
  O O O
  O X O      X = move cell (blue)
  O O O      O = attack cells (orange)
```

### Best attacker cell (minimum-movement attack)

```
_find_best_attacker_cell(from, target, reachable, atk_range) → Vector2i

For every cell in reachable:
  to_target = manhattan(cell, target)
  if to_target <= atk_range:               ← can reach target from here
    from_start = manhattan(cell, from)
    if from_start < best_dist:             ← closer to unit's start?
      best_cell = cell

Returns: reachable cell closest to where the unit started that
         still allows attacking the target.
         (Minimises unnecessary movement, feels natural.)
```

## Combat Resolution

```
BattleMap.perform_combat(attacker, defender)
  │
  ├── guard: attacker.has_attacked == false
  └── CombatResolver.resolve(attacker, defender)
               │
               ├── dmg = max(1, attacker.data.attack - defender.data.defense)
               ├── defender.take_damage(dmg)
               │         └── defender.current_hp -= dmg
               │             if hp ≤ 0 → emit "died" signal
               ├── attacker.play_hit_flash()   ← red→white tween 0.075s×2
               │
               ├── is defender still alive?
               │    counter_dist = manhattan(defender.grid_cell, attacker.grid_cell)
               │    if counter_dist <= defender.data.attack_range:
               │         counter = max(1, defender.data.attack - attacker.data.defense)
               │         attacker.take_damage(counter)
               │         defender.play_hit_flash()
               │
               └── [back in perform_combat]
                   attacker.set_attacked()   ← has_attacked = true

Unit death (signal handler in BattleMap):
  _on_unit_died(unit)
    ├── units.erase(unit)
    ├── player_units.erase(unit)  OR  enemy_units.erase(unit)
    ├── grid_mgr.set_cell_solid(unit.grid_cell, false)
    ├── unit.queue_free()
    └── TurnManager.check_end_conditions()
              └── enemy_units empty → emit "battle_won"
                  player_units empty → emit "battle_lost"
```

## GridManager: Dual Pathfinding

Two separate systems coexist in GridManager:

| System         | Used by       | Algorithm | Solid source         |
|----------------|---------------|-----------|----------------------|
| BFS reachability | Player drag | Breadth-first search | `_solid_cells` dict + tile type |
| A* pathfinding  | EnemyAI      | AStarGrid2D (built-in) | AStarGrid2D internal solid state |

Both are kept in sync via `set_cell_solid(cell, solid)`, which updates both
the dict and `_astar.set_point_solid()`.

**AStarGrid2D quirk:** the destination cell must NOT be solid when calling
`get_astar_path`. EnemyAI temporarily unblocks both endpoints before querying,
then restores them.

## Unit Visual States

```
Unit._draw()
  │
  ├── base_color = PLAYER_COLOR (blue) or ENEMY_COLOR (red)
  ├── if is_spent():  base_color = base_color.darkened(0.45)   ← grey-out
  ├── if _is_dragging: base_color.a = 0.70                     ← translucent
  │
  ├── draw_circle(ZERO, 22px, base_color)
  ├── draw_arc(ZERO, 22px, white outline)
  ├── draw_string(class_letter, centered)   ← K / C / A / M
  └── HP bar:
        background rect (dark red)
        foreground rect (green, width scaled by current_hp / max_hp)
```

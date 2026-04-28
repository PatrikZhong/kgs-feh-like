# Battle System

## Drag-and-Drop Input Flow

The drag gesture uses a **ghost afterimage** pattern: the real unit stays
at its cell (dimmed), a translucent ghost follows the cursor, and a yellow
breadcrumb arrow shows the proposed path. A second orange arrow appears when
hovering over an enemy to show the attack vector. On release, ghost and
arrows are freed and the real unit tweens to the destination.

```
BattleMap._unhandled_input(event)
│
│  Guard: TurnManager.current_state == PLAYER_TURN
│
├── InputEventMouseMotion  (while _dragged_unit == null)
│    └── hover enemy unit → _inspect_enemy(hovered)
│         or leave enemy  → _clear_inspection()
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
│             ├── enemies inside move range added to _extended_attack_cells
│             │
│             ├── highlight_lyr.show_move_and_attack(blue, orange)
│             ├── unit.start_drag()   ← dims real unit (modulate.a=0.4), stays in place
│             │
│             ├── spawn _ghost (Node2D + AnimatedSprite2D clone, 65% opacity, "walk")
│             │       added to UnitsLayer, z_index=20
│             │       initial position = grid_to_world(_original_cell)
│             │
│             ├── spawn _drag_arrow (Line2D, yellow) + _drag_arrowhead (Polygon2D)
│             │       added to BattleMap root, z_index=1
│             │       color: Color(1.0, 0.95, 0.3, 0.9)  ← yellow
│             │
│             └── spawn _attack_arrow (Line2D, orange) + _attack_arrowhead (Polygon2D)
│                     added to BattleMap root, z_index=1
│                     color: Color(1.0, 0.35, 0.1, 0.9)  ← orange-red
│
├── InputEventMouseMotion  (while _dragged_unit != null)
│    ├── if hovered in _reachable_cells (blue tile):
│    │    ├── _last_hovered_move_cell = hovered
│    │    └── update _arrow_path (breadcrumb; trim loop if cell revisited)
│    │
│    ├── if hovered in _extended_attack_cells (orange tile):
│    │    └── _hovered_attack_target = enemy unit at cell (or null)
│    │
│    ├── ghost position:
│    │    ├── _hovered_attack_target set → snap ghost to _last_hovered_move_cell
│    │    └── otherwise              → follow cursor freely
│    │
│    └── _update_drag_arrow()
│             ├── _drag_arrow.points = path of all cells in _arrow_path
│             ├── _drag_arrowhead at last path cell, pointing along last segment
│             ├── if _hovered_attack_target:
│             │    _attack_arrow points: _last_hovered_move_cell → enemy cell
│             │    _attack_arrowhead at enemy cell
│             └── else: _attack_arrow/head cleared
│
└── InputEventMouseButton LEFT RELEASED
     └── _end_drag(world_pos)
               │
               ├── queue_free: _ghost, _drag_arrow, _drag_arrowhead,
               │              _attack_arrow, _attack_arrowhead  → all null
               ├── drop_cell = grid_mgr.world_to_grid(world_pos)
               ├── unit.end_drag()       ← restores modulate.a = 1.0
               ├── highlight_lyr.clear()
               │
               ├── [A] drop_cell in _reachable_cells AND cell_free AND drop_cell != origin
               │         └── _commit_move(unit, drop_cell)
               │             TurnManager.end_player_turn()
               │
               ├── [B] drop_cell in _extended_attack_cells
               │    ├── get_unit_at(drop_cell)             → target
               │    ├── target exists AND is enemy?
               │    │    ├── _pick_attacker_cell(drop_cell, unit) → best_cell
               │    │    ├── _commit_move(unit, best_cell)
               │    │    ├── perform_combat(unit, target)
               │    │    └── TurnManager.end_player_turn()
               │    └── no enemy on orange cell → cancel (unit stays at origin)
               │
               └── [C] anywhere else → cancel (unit stays at origin, no-op)
```

## Enemy Inspection on Hover

When the player hovers the cursor over an enemy unit **without dragging**,
BattleMap enters "inspection" mode for that enemy:

```
BattleMap._inspect_enemy(enemy)
  ├── temporarily unblock enemy.grid_cell
  ├── get_reachable_cells(enemy.cell, enemy.move_range, false, player_cells)
  ├── restore enemy.grid_cell as solid
  ├── _get_extended_attack_cells(move_cells, enemy.attack_range)
  └── highlight_lyr.show_move_and_attack(move_cells, attack_cells)
        ← shows that enemy's individual threat in blue + orange
```

Moving the cursor off the enemy calls `_clear_inspection()` which sets
`_inspected_enemy = null` and calls `highlight_lyr.clear()`.

Inspection is cancelled at the start of `_begin_drag()` to avoid stale
highlights during a drag.

## Threat Range (Danger Zone)

An always-visible red overlay shows all cells **any** enemy can reach or
attack this round. The player can toggle it with the "Danger Zone" button in
the HUD.

```
BattleMap._refresh_enemy_threat()
  │
  │  (temporarily unblock all enemy cells so their BFS includes their own tile)
  ├── for each enemy:
  │    reachable  = get_reachable_cells(enemy.cell, move_range, false, player_cells)
  │    attack_ext = _get_extended_attack_cells(reachable, attack_range)
  │    union reachable ∪ attack_ext → seen dict
  │  (restore all enemy cells as solid)
  │
  └── highlight_lyr.set_threat(seen)   ← red overlay
```

`_refresh_enemy_threat()` is called:
- In `BattleMap._ready()` (initial state)
- Whenever `TurnManager` emits `turn_changed` with `PLAYER_TURN`
- Whenever a unit dies (`_on_unit_died`) for enemies

HUD "Danger Zone" button emits `threat_toggled(on: bool)`:

```
HUD.threat_toggle_btn pressed
  └── emit threat_toggled(on)
        └── BattleMap._on_threat_toggled(on)
              ├── on=true  → _refresh_enemy_threat()
              └── on=false → highlight_lyr.set_threat([])
```

## Movement Commit

Two movement primitives exist depending on whether animation is needed:

```
move_unit_instant(unit, cell)            ← used by EnemyAI, placement phase
  │
  ├── _unit_by_cell.erase(unit.grid_cell)
  ├── grid_mgr.set_cell_solid(unit.grid_cell, false)
  ├── unit.snap_to_cell(cell, grid_mgr)  ← teleports instantly, sets unit.grid_cell
  ├── grid_mgr.set_cell_solid(cell, true)
  └── _unit_by_cell[cell] = unit

_commit_move(unit, cell, path)           ← used by player drag (tweened)
  │
  ├── _unit_by_cell.erase(unit.grid_cell)
  ├── grid_mgr.set_cell_solid(unit.grid_cell, false)   ← free old cell
  ├── grid_mgr.set_cell_solid(cell, true)              ← claim new cell
  ├── unit.grid_cell = cell
  ├── _unit_by_cell[cell] = unit
  ├── unit.set_moved()   ← has_moved = true, sprite darkened immediately (SPENT_DARKEN=0.45)
  └── Tween: 0.07 s per step along path; 0.10 s direct move if path is empty
      (set_moved fires before tween; unit is greyed out as soon as move starts)
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
        add to result set (deduped via dict)

Returns: all cells attackable from any move cell,
         excluding move cells themselves (no blue/orange overlap).
```

### Best attacker cell

```
_find_best_attacker_cell(from, target, reachable, atk_range) → Vector2i

Pass 1 — prefer cells at EXACTLY atk_range from target:
  for cell in reachable:
    if manhattan(cell, target) == atk_range:
      pick closest to `from`

Pass 2 — fallback, accept any cell within atk_range:
  for cell in reachable:
    if 1 <= manhattan(cell, target) <= atk_range:
      pick closest to `from`

Returns best_cell (defaults to `from` if no valid cell found).
```

`_pick_attacker_cell` first tries `_last_hovered_move_cell`:
- The check is **exact**: `to_target == unit.attack_range` (not ≤).
  For range-2 units the hover cell must be exactly 2 tiles from the target.
  Range-1 units (melee) must be exactly adjacent. If the hover cell fails
  this check, falls back to `_find_best_attacker_cell`.

### Arrow path (shortest path)

`_arrow_path` holds the current path from the origin to the last valid hovered
blue tile. It is recomputed (not accumulated) each time the cursor enters a
new reachable cell:

```
Mouse enters a blue tile (hovered):
  new_path = grid_mgr.get_shortest_path(
      _original_cell, hovered, can_jump_allies, ally_cells)
  if new_path.size() - 1 <= move_range:
      _arrow_path = new_path    ← replaces old path entirely
```

- Start: `_arrow_path = [_original_cell]`
- On each valid hover: replaced with the A*-shortest path to that tile
- Paths longer than the unit's `move_range` are rejected (path stays unchanged)
- `_drag_arrow.points` traces this path cell-by-cell in world space

On drop, if `_arrow_path[-1] != drop_cell`, a fresh shortest path is computed
to guarantee the tween ends at the exact drop target.

## Combat Resolution

```
BattleMap.perform_combat(attacker, defender)
  │
  ├── guard: attacker.has_attacked == false
  └── CombatResolver.resolve(attacker, defender)
               │
               ├── attacker.play_hit_flash()   ← attacker flashes (attack animation)
               ├── dmg = max(1, attacker.data.attack - defender.data.defense)
               ├── defender.take_damage(dmg)
               │         └── defender.current_hp -= dmg
               │             if hp ≤ 0 → emit "died" signal
               │
               ├── defender still alive?
               │    dist = manhattan(defender.grid_cell, attacker.grid_cell)
               │    if dist <= defender.data.attack_range:
               │         defender.play_hit_flash()   ← defender flashes (counter animation)
               │         counter = max(1, defender.attack - attacker.defense)
               │         attacker.take_damage(counter)
               │
               └── [back in perform_combat]
                   attacker.set_attacked()   ← has_attacked = true

Unit death (signal handler in BattleMap._on_unit_died):
  ├── _unit_by_cell.erase(unit.grid_cell)
  ├── units / player_units / enemy_units  .erase(unit)
  ├── grid_mgr.set_cell_solid(unit.grid_cell, false)
  ├── unit.queue_free()
  ├── if enemy died: _refresh_enemy_threat()
  └── TurnManager.check_end_conditions()
            └── enemy_units empty → battle_won.emit()
                player_units empty → battle_lost.emit()
```

**Damage formula:** `max(1, attack - defense)`. Minimum 1 damage always
applies; negative results are clamped.

## GridManager: Dual Pathfinding

Two separate systems coexist in GridManager:

| System              | Used by    | Algorithm       | Solid source                    |
|---------------------|------------|-----------------|----------------------------------|
| BFS reachability    | Player drag, threat overlay, inspection | Breadth-first | `_solid_cells` dict + tile type |
| A* pathfinding      | EnemyAI    | AStarGrid2D     | AStarGrid2D internal state      |

Both are kept in sync via `set_cell_solid(cell, solid)`, which updates both
the dict and `_astar.set_point_solid()`.

`set_cell_solid(cell, false)` restores the A* point to the tile-type-driven
solid state (solid only if `TileType.BLOCKED`).

**AStarGrid2D configuration:**
- `diagonal_mode = DIAGONAL_MODE_NEVER` — orthogonal movement only.
- `default_estimate_heuristic = HEURISTIC_MANHATTAN` — correct heuristic for
  orthogonal grids; Euclidean (the default) underestimates costs here.
- `get_id_path(from, to, allow_partial_path=true)` — returns the closest
  reachable cell when the destination is blocked, preventing enemies from
  freezing when their target is surrounded.

**AStarGrid2D quirk:** the destination cell must NOT be solid when calling
`get_astar_path`. EnemyAI temporarily unblocks both endpoints before querying,
then restores them.

## Unit Visual States

```
Unit._draw()   (only active when _animated_sprite == null)
  │
  ├── base_color = PLAYER_COLOR (blue) or ENEMY_COLOR (red)
  ├── if is_spent():  base_color = base_color.darkened(0.45)
  ├── if _is_dragging: base_color.a = 0.70
  ├── draw_circle(ZERO, 22px, base_color)
  ├── draw_arc(ZERO, 22px, white outline)
  └── draw_string(class_letter, centered)   ← K / C / A / M / O
```

When `_animated_sprite` is present (all configured classes), the circle is
suppressed. Sprite modulate is used for state instead:

| State          | modulate                               |
|----------------|----------------------------------------|
| Normal         | `Color.WHITE`                          |
| Spent (moved)  | `Color.WHITE.darkened(0.45)`           |
| Dragging (real unit, stays in place) | `Color(1,1,1, 0.4)` |

HP bar (drawn in `_draw()` regardless of sprite state):

```
Sprite present:
  bar_w = SPRITE_FRAME_PX * SPRITE_SCALE * 0.15   ← ~19.5 px world
  bar_y = SPRITE_FRAME_PX * SPRITE_SCALE * 0.15   ← below centre

Fallback circle:
  bar_w = UNIT_RADIUS * 2.0                        ← 44 px
  bar_y = UNIT_RADIUS + 4.0                        ← below circle
```

Both background (dark red 0.3,0,0) and foreground (Color.DARK_RED) rects
drawn at same position; foreground width = `bar_w * (current_hp / max_hp)`.

## Drag Overlay Nodes

Created in `_begin_drag`, freed in `_end_drag`:

| Node              | Type         | Parent      | z_index | Purpose                               |
|-------------------|--------------|-------------|---------|---------------------------------------|
| `_ghost`          | Node2D       | UnitsLayer  | 20      | Follows cursor; child AnimatedSprite2D cloned from unit |
| `_drag_arrow`     | Line2D       | BattleMap   | 1       | Yellow breadcrumb path origin → proposed tile |
| `_drag_arrowhead` | Polygon2D    | BattleMap   | 1       | Yellow triangle tip at path end        |
| `_attack_arrow`   | Line2D       | BattleMap   | 1       | Orange shaft from landing cell → hovered enemy |
| `_attack_arrowhead` | Polygon2D  | BattleMap   | 1       | Orange triangle tip at enemy cell      |

Ghost sprite is created via `Unit.make_ghost_sprite()` which shares the
same `SpriteFrames` resource (no duplication) and plays "walk" at 65% opacity.

Ghost behavior:
- Normal drag: ghost follows cursor freely
- Hovering orange enemy cell: ghost **freezes** at `_last_hovered_move_cell`
  (shows where the unit will actually land, not where cursor is)

Arrow endpoint (`_drag_arrow` via `_arrow_path`) tracks the breadcrumb of
visited blue tiles — not the raw cursor position. The attack arrow only
appears when `_hovered_attack_target` is non-null.

## Unit Spawning

`BattleMap._begin_placement()` runs at scene start and populates the board.
All `UnitSpawner` nodes that live under `SpawnersLayer` and have a `unit_data`
assigned are split by their `is_player_unit` flag:

```
SpawnersLayer children (UnitSpawner, unit_data != null)
  │
  ├── is_player_unit = true  → player_spawners
  └── is_player_unit = false → enemy_spawners
```

### Player units

Unit types come from `player_spawners` (or fall back to `[KNIGHT, ARCHER, MAGE]`
if none are present). Positions are assigned left-to-right from `PlacementZoneLayer`
cells — the spawner `cell` property is **ignored** for players.

**Future:** replace this entirely with `SaveData.player_roster` once the
unit-selection screen is implemented. At that point per-battle player `UnitSpawner`
nodes become unnecessary.

### Enemy units

If `enemy_spawners` exist, each one defines **both** the unit type (`unit_data`)
and the spawn cell (`cell`). This is the preferred path for new battle scenes —
it makes each `Battle_*.tscn` self-contained.

**Fallback (legacy):** if no enemy spawners are present, falls back to 3×
`ArmoredOrc` spawned at cells painted in `EnemySpawnLayer`. This keeps
pre-existing scenes working without modification.

### Authoring a new battle with custom enemies

1. Open the `Battle_N.tscn` in the Godot editor.
2. In `SpawnersLayer`, instance `scenes/battle/UnitSpawner.tscn` for each enemy.
3. In the Inspector for each spawner:
   - Set **Unit Data** → the desired `.tres` (e.g. `ArmoredOrcData.tres`).
   - Set **Is Player Unit** → `false`.
   - Set **Cell** → the grid cell where the enemy should start (Vector2i).
4. Repeat for player units if you want a fixed roster for this battle (set
   **Is Player Unit** → `true`). Otherwise the default three will be used.

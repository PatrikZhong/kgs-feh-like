# Architecture Overview

## Scene Tree

```
[Overworld.tscn]  ← main scene (project.godot)
  └── OverworldNode.tscn × N     scripts/overworld/Overworld.gd
                                  scripts/overworld/OverworldNode.gd

[BattleMap.tscn]  ← loaded on node click
  ├── GridManager.tscn            scripts/battle/GridManager.gd
  ├── HighlightLayer (Node2D)     scripts/battle/HighlightLayer.gd
  ├── UnitsLayer (Node2D)
  │    └── Unit.tscn × N         scripts/battle/Unit.gd
  └── HUD.tscn (CanvasLayer)     scripts/ui/HUD.gd
```

## Autoloads (always resident, order matters)

```
TurnManager    scripts/battle/TurnManager.gd   — state machine, round counter
EnemyAI        scripts/battle/EnemyAI.gd       — greedy AI coroutine
CombatResolver scripts/battle/CombatResolver.gd — damage math
SaveData       scripts/data/SaveData.gd         — persistent state (stub)
```

**Important:** Autoloads compile before the global class registry is fully
populated, so their function parameters must be untyped (`var x` not
`var x: Unit`). Local variables inside those functions can still be typed.

## Coordinate System

```
World space            Grid space
───────────            ──────────
(0,0) ┌────────────   (0,0) top-left cell
      │ 64px tiles
      │ TILE_SIZE = Vector2i(64, 64)
      │
      │ grid_to_world(cell) = cell * TILE_SIZE + TILE_SIZE/2
      │   → returns cell CENTER in world pixels
      │
      │ world_to_grid(pos) = Vector2i(pos / TILE_SIZE)
      │   → truncates to cell top-left index
```

Grid is 8×8 (`GRID_WIDTH = GRID_HEIGHT = 8`).

## Data Resources

```
resources/units/
  KnightData.tres   — UnitData resource (HP=50 ATK=12 DEF=15 MOV=3 RNG=1)
  CavalryData.tres  — UnitData resource (HP=36 ATK=14 DEF=8  MOV=5 RNG=1 jump)
  ArcherData.tres   — UnitData resource (HP=34 ATK=16 DEF=6  MOV=3 RNG=2)
  MageData.tres     — UnitData resource (HP=26 ATK=20 DEF=4  MOV=3 RNG=2)
```

`UnitData` fields: `unit_name`, `class_type` (enum KNIGHT/CAVALRY/ARCHER/MAGE),
`max_hp`, `attack`, `defense`, `move_range`, `attack_range`, `can_jump_allies`.

## Visual Rendering

No sprite assets exist yet. All visuals are drawn procedurally via `_draw()`:

| Node            | What it draws                                      |
|-----------------|----------------------------------------------------|
| GridManager     | Colored rects per tile type + dark grid border     |
| HighlightLayer  | Blue overlay (move range) + orange overlay (attack)|
| Unit            | Colored circle + class letter + HP bar             |

## Key Invariants

- A cell is "solid" in AStarGrid2D whenever a unit occupies it.
- BFS (reachability) and A* (pathfinding) are separate systems; BFS ignores
  A* solid state and uses its own `_solid_cells` dict + tile type check.
- Enemy cells are **not** passed to `get_reachable_cells` as blocked — they
  are handled at the attack-range level instead.
- `Unit.is_spent()` returns `has_moved` (not `has_attacked`), so a unit
  greyed out immediately after moving even if it hasn't attacked.

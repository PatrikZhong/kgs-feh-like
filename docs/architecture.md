# Architecture Overview

## Scene Tree

```
[Overworld.tscn]  ← main scene (project.godot run/main_scene)
  ├── EdgesContainer (Node2D)        Line2D edges drawn in _draw_edges()
  └── NodesContainer (Node2D)
       └── OverworldNode.tscn × N   scripts/overworld/OverworldNode.gd
                                     scripts/overworld/Overworld.gd

[BattleMap.tscn]  ← loaded on overworld node click
  ├── Camera2D                       position=(160,160) zoom=(2,2)
  ├── GridManager (Node2D)           scripts/battle/GridManager.gd
  ├── HighlightLayer (Node2D)        scripts/battle/HighlightLayer.gd   z_index=1
  ├── UnitsLayer (Node2D)                                                z_index=2
  │    └── Unit.tscn × N            scripts/battle/Unit.gd
  └── HUD (CanvasLayer)              scripts/ui/HUD.gd
       ├── Panel
       │    └── VBox
       │         ├── TurnLabel       "Turn N — Your/Enemy Turn"
       │         └── EndTurnButton   disabled during ENEMY_TURN
       ├── ResultPanel               hidden until battle ends
       │    └── VBox
       │         ├── ResultLabel     "Victory!" or "Defeat!"
       │         └── ContinueButton  → Overworld.tscn
       └── ThreatToggleButton        "Danger Zone: ON/OFF"
```

## Autoloads (always resident, order matters)

```
TurnManager    scripts/battle/TurnManager.gd   — state machine, round counter
EnemyAI        scripts/battle/EnemyAI.gd       — greedy AI coroutine
CombatResolver scripts/battle/CombatResolver.gd — damage math
SaveData       scripts/data/SaveData.gd         — persistent run state
```

**Important:** Autoloads compile before the global class registry is fully
populated, so their function parameters must be untyped (`var x` not
`var x: Unit`). Local variables inside those functions can still be typed.

## Coordinate System

```
World space            Grid space
───────────            ──────────
(0,0) ┌────────────   (0,0) top-left cell
      │ 40px tiles
      │ TILE_SIZE = Vector2i(40, 40)
      │
      │ grid_to_world(cell) = cell * TILE_SIZE + TILE_SIZE/2
      │   → returns cell CENTER in world pixels
      │
      │ world_to_grid(pos) = Vector2i(pos / TILE_SIZE)
      │   → truncates to cell top-left index
```

Grid is 8×8 (`GRID_WIDTH = GRID_HEIGHT = 8`).
Total world extent: 320×320 px.

**Camera:** `Camera2D` at world position (160, 160) with zoom (2, 2).
At 2× zoom the 40px world tiles appear as 80px on screen and the 320×320
grid is centred inside the 1152×820 viewport with ~128px margins.

## Display Settings (project.godot)

```
[display]
window/size/viewport_width  = 1152
window/size/viewport_height = 820

[rendering]
environment/defaults/default_clear_color = Color(0.10, 0.09, 0.07, 1)
```

The dark earthy clear colour fills the margins around the grid that are
visible outside the 320×320 world area.

## Data Resources

### Unit data (`resources/units/`)

| File                | class_type | HP | ATK | DEF | MOV | RNG | Jump |
|---------------------|------------|----|-----|-----|-----|-----|------|
| KnightData.tres     | KNIGHT (0) | 50 | 12  | 15  |  3  |  1  | no   |
| CavalryData.tres    | CAVALRY (1)| 36 | 14  |  8  |  5  |  1  | yes  |
| ArcherData.tres     | ARCHER (2) | 34 | 16  |  6  |  3  |  2  | no   |
| MageData.tres       | MAGE (3)   | 26 | 20  |  4  |  3  |  2  | no   |
| ArmoredOrcData.tres | ARMORED_ORC (4) | 50 | 12 | 15 | 3 | 1 | no |

`UnitData` fields: `unit_name`, `class_type` (enum),
`max_hp`, `attack`, `defense`, `move_range`, `attack_range`, `can_jump_allies`.

`UnitData.class_label()` — returns the enum key string (e.g. `"KNIGHT"`);
used in debug print statements.

ArmoredOrc is the enemy unit type. It shares Knight stats but has its own
`ClassType` entry so it receives the correct sprite.

### SaveData (autoload)

```gdscript
var unlocked_node_ids:    Array[int] = [0]  # nodes accessible/completed
var unlocked_edge_indices: Array[int] = []  # edge indices now open (unused)
var current_battle_id:    int = 0           # node ID of the active battle
```

`current_battle_id` is set by `Overworld._on_node_clicked()` before the
scene transition, and read by GridManager (tileset) and BattleMap (spawns).

`unlock_after_battle(completed_id)` — appends `completed_id + 1` to
`unlocked_node_ids`, opening the next overworld node on victory.

`is_node_unlocked(id)` — returns `id in unlocked_node_ids`.

`unlock_edge(index)` / `is_edge_unlocked(index)` — edge unlock helpers;
defined but not yet called anywhere (reserved for future use).

## Sprite System

### Character sprites

Located in `assets/sprites/Characters(100x100)/`.
Each class has a folder with a `<Class> with shadows/` subfolder containing
horizontal sprite-sheet PNGs — one sheet per animation state, 100×100 px
per frame:

| Animation | Frames | Loops | On finish         |
|-----------|--------|-------|-------------------|
| idle      | 6      | yes   | —                 |
| walk      | 8      | yes   | —                 |
| hurt      | 4      | no    | → resumes idle    |
| death     | 4      | no    | stays on last frame |

All animations run at **8.0 FPS** (`frames.set_animation_speed(anim_name, 8.0)`).

Class → sprite folder mapping:

| ClassType   | Folder                          |
|-------------|---------------------------------|
| KNIGHT      | `Knight/Knight with shadows/`   |
| CAVALRY     | `Lancer/Lancer with shadows/`   |
| ARCHER      | `Archer/Archer with shadows/`   |
| MAGE        | `Wizard/Wizard with shadows/`   |
| ARMORED_ORC | `Armored Orc/Armored Orc with shadows/` |

`Unit._setup_sprite()` builds a `SpriteFrames` resource at runtime by
slicing each sheet with `AtlasTexture` (100×100 px regions).
`SPRITE_SCALE = 1.3` → sprites display at 130 px in world space (260 px
on screen at 2× camera zoom). Characters intentionally overflow the 40px
tile for the FEH aesthetic.

Enemy sprites are **horizontally flipped** (`flip_h = not is_player_unit`)
so enemies always face left toward the player side.

Fallback: if no sprite is loaded, `_draw()` renders a coloured circle with
a class-letter label (`K/C/A/M/O`).

### Background tileset

`assets/sprites/GRASS+.png` — 400×224 px, 16×16 px per tile → 25 cols × 14 rows = **350 tiles**.

`GridManager._ready()` slices the sheet with `_slice_tile(index)`:

```
atlas.region = Rect2(
  (index % cols) * 16,
  (index / cols) * 16,
  16, 16)
```

The tile index equals `SaveData.current_battle_id`, so each overworld node
gets a distinct tile:

| Node | Tile index | Visual |
|------|-----------|--------|
| 0 — Tutorial    | 0 | first tile in GRASS+ |
| 1 — Forest Path | 1 | second tile           |
| 2 — River Ford  | 2 | third tile            |
| …               | N | Nth tile (350 total)  |

`texture_filter = TEXTURE_FILTER_NEAREST` keeps 16 px pixels crisp at 5× world scale.

## GridManager: Tile Types

`GridManager` declares a `TileType` enum used for future gameplay modifiers:

```gdscript
enum TileType { NORMAL, HIGH_GROUND, DANGEROUS, BLOCKED }
```

| Type        | Visual tint                          | BFS effect     | A* effect   |
|-------------|--------------------------------------|----------------|-------------|
| NORMAL      | none                                 | passable       | passable    |
| HIGH_GROUND | goldish (0.55, 0.45, 0.10, 0.50)     | passable       | passable    |
| DANGEROUS   | red    (0.60, 0.15, 0.15, 0.50)      | passable       | passable    |
| BLOCKED     | dark   (0.10, 0.10, 0.10, 0.70)      | impassable     | solid       |

`set_tile_type(cell, type)` — updates `_tile_types` dict and marks the
A* point solid if `type == BLOCKED`. Triggers `queue_redraw()`.

`get_tile_type(cell)` — returns `_tile_types.get(cell, TileType.NORMAL)`.

No tile types other than NORMAL are set at runtime in the current prototype.
HIGH_GROUND and DANGEROUS effects (e.g. damage, defense bonus) are stretch
goals not yet implemented.

## Per-Battle Configuration

Both `GridManager` and `BattleMap` read `SaveData.current_battle_id` in
`_ready()` to configure themselves:

**GridManager** — `_slice_tile(current_battle_id)` picks the background tile.

**BattleMap** — `BATTLE_ENEMY_SPAWNS` array (wraps with `%`):

```gdscript
const BATTLE_ENEMY_SPAWNS := [
  [Vector2i(6,2), Vector2i(6,4), Vector2i(6,6)],  # node 0
  [Vector2i(7,1), Vector2i(5,3), Vector2i(7,6)],  # node 1
  [Vector2i(7,0), Vector2i(6,4), Vector2i(7,7)],  # node 2
]
```

Player spawns are fixed: Knight (1,1), Archer (1,3), Mage (1,5).
All three enemies are Armored Orcs (`ARMORED_ORC_DATA`).

## Overworld

### World graph (hardcoded in Overworld.gd)

```gdscript
_WORLD_NODES = [
  {id:0, label:"Tutorial",    pos:(200,300), scene:"BattleMap.tscn"},
  {id:1, label:"Forest Path", pos:(420,180), scene:"BattleMap.tscn"},
  {id:2, label:"River Ford",  pos:(640,310), scene:"BattleMap.tscn"},
]
_WORLD_EDGES = [{a:0, b:1}, {a:1, b:2}]
```

TODO: migrate to a `WorldGraph.tres` resource.

### OverworldNode visuals (OverworldNodeUI)

Each node is a circle of radius 28 px:

| State    | Circle color          | modulate                 | Button   |
|----------|-----------------------|--------------------------|----------|
| Unlocked | Gold (0.90,0.75,0.20) | `Color.WHITE`            | enabled  |
| Locked   | Grey (0.40,0.40,0.40) | `Color(0.55,0.55,0.55)`  | disabled |

A white outline arc is always drawn. A `Label` below the circle shows the
node's name.

### Overworld edge visuals

Edges are `Line2D` nodes (width 4.0) added to `EdgesContainer`:

| Condition               | Color                        |
|-------------------------|------------------------------|
| Both endpoints unlocked | `Color.WHITE`                |
| Any endpoint locked     | `Color(0.5, 0.5, 0.5, 0.6)` |

### Scene flow

```
Overworld._on_node_clicked(id, scene_path)
  └── SaveData.current_battle_id = id
      get_tree().change_scene_to_file(scene_path)   → BattleMap.tscn
```

## HighlightLayer: Color Reference

`HighlightLayer` (`scripts/battle/HighlightLayer.gd`) draws three
independent highlight layers (drawn in this z-order: threat → move → attack):

| Layer   | Fill                            | Border                          | API                         |
|---------|---------------------------------|---------------------------------|-----------------------------|
| Threat  | Color(0.85,0.10,0.10, 0.28)    | Color(0.85,0.10,0.10, 0.55)    | `set_threat(cells)`         |
| Move    | Color(0.20,0.60,1.00, 0.35)    | Color(0.20,0.60,1.00, 0.85)    | `show_move_and_attack()`    |
| Attack  | Color(1.00,0.38,0.08, 0.38)    | Color(1.00,0.38,0.08, 0.90)    | `show_move_and_attack()`    |

Available methods:

| Method                              | Effect                                          |
|-------------------------------------|-------------------------------------------------|
| `show_move_and_attack(move, atk)`   | Show both move (blue) and attack (orange) cells |
| `show_attack_only(atk)`             | Show only attack cells (move cleared)           |
| `set_threat(cells)`                 | Update red danger zone overlay                  |
| `clear()`                           | Clear move + attack; leave threat intact        |
| `clear_all()`                       | Clear move + attack + threat                    |

## Key Invariants

- A cell is "solid" in AStarGrid2D whenever a unit occupies it.
- BFS (reachability) and A* (pathfinding) are separate systems; BFS ignores
  A* solid state and uses its own `_solid_cells` dict + tile type check.
- Enemy cells are **not** passed to `get_reachable_cells` as blocked — they
  are handled at the attack-range level instead.
- `Unit.is_spent()` returns `has_moved` (not `has_attacked`), so a unit
  greys out immediately after moving even if it hasn't attacked.
- Drag overlay nodes (`_ghost`, `_drag_arrow`, `_drag_arrowhead`,
  `_attack_arrow`, `_attack_arrowhead`) are created on drag start and
  `queue_free()`d on drag end; they are never kept between drags.
- `_refresh_enemy_threat()` temporarily unblocks enemy cells before calling
  BFS (so enemies can "see" their own movement), then restores them.

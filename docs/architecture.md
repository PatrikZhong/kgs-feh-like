# Architecture Overview

## Scene Tree

```
[Overworld.tscn]  ← main scene (project.godot run/main_scene)
  ├── EdgesContainer (Node2D)        reserved; no edges are drawn at runtime
  └── NodesContainer (Node2D)
       └── OverworldNode.tscn × N   scripts/overworld/OverworldNode.gd
                                     scripts/overworld/Overworld.gd

[BattleMap.tscn]  ← loaded on overworld node click
  ├── Camera2D (BattleCamera)        scripts/battle/BattleCamera.gd — dynamic fit-zoom, edge pan, scroll zoom
  ├── GridManager (Node2D)           scripts/battle/GridManager.gd
  ├── HighlightLayer (Node2D)        scripts/battle/HighlightLayer.gd   z_index=1
  ├── UnitsLayer (Node2D)                                                z_index=2
  │    └── Unit.tscn × N            scripts/battle/Unit.gd
  ├── SpawnersLayer (Node2D)         holds UnitSpawner nodes for player & enemy spawns
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

**Typing in autoloads:** Autoload scripts use `const _Unit := preload("res://scripts/battle/Unit.gd")`
and `const _BattleMap := preload("res://scripts/battle/BattleMap.gd")` to resolve
types without relying on the global class registry. Function parameters are typed
against these preload aliases (e.g. `func resolve(attacker: _Unit, defender: _Unit)`).

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

**Camera:** `BattleCamera` (`scripts/battle/BattleCamera.gd`, extends Camera2D).
`BattleMap._fit_camera()` computes an integer fit-zoom so the full 320×320 grid
fills the viewport above the HUD (HUD_HEIGHT=64 px reserved), then calls
`_cam.setup(grid_center, grid_size, fit_zoom)`.

After setup, BattleCamera supports:

| Feature       | Detail                                                                 |
|---------------|------------------------------------------------------------------------|
| Edge panning  | Mouse within 60 px of viewport edge moves camera at 400 px/s (world-corrected) |
| Scroll zoom   | Mouse-wheel zooms toward cursor; ZOOM_STEP=1.25 per tick; range [fit_zoom, 5.0] |
| Pan lock      | `panning_locked = true` while the player is dragging a unit            |
| Bounds clamp  | Camera stays within grid rect at all zoom levels                       |

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

### Unit data — data-driven design

There is a **single generic `Unit` scene** (`scenes/battle/Unit.tscn`) used for every unit
in the game — player or enemy. No per-class scripts or scenes exist (no `KnightUnit.gd`,
`ArcherUnit.gd`, etc.). The "class" of a unit is entirely determined by a `UnitData`
resource injected before the node enters the scene tree:

```
BattleMap._spawn(data, cell, is_player)
  unit.data = data          ← assigned before add_child()
  add_child(unit)           ← Unit._ready() fires here
    └── current_hp = data.max_hp
        attack_range = data.attack_range
        _setup_sprite()     ← picks PNG paths from data.class_type
```

Adding a new unit type requires: (1) a new `.tres` file, (2) a new `ClassType` enum value,
(3) a new `match` arm in `Unit._get_sprite_paths()`. No new scripts or scenes are needed.

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

### World graph (scene-driven)

`Overworld.gd` reads the graph from the scene tree at runtime:

- **Nodes** — `OverworldNodeUI` children under `NodesContainer` in `Overworld.tscn`.
  Each node exposes an `id` and a `scene_path` (battle scene to load).
  `_setup_nodes()` iterates these children and connects `node_clicked` signals.

- **Edges** — `@export var edges: Array = [[0, 1], [1, 2]]` in `Overworld.gd`.
  Each entry is `[id_a, id_b]`. Edges are not drawn at runtime; they exist only
  to express connectivity for future use (e.g. progression gating).

To add a new overworld node: add an `OverworldNodeUI` instance to `NodesContainer`
in the Godot editor and append its edge pairs to the `edges` export array.

TODO: migrate to a `WorldGraph.tres` resource for cleaner authoring.

### OverworldNode visuals (OverworldNodeUI)

Each node is a circle of radius 28 px:

| State    | Circle color          | modulate                 | Button   |
|----------|-----------------------|--------------------------|----------|
| Unlocked | Gold (0.90,0.75,0.20) | `Color.WHITE`            | enabled  |
| Locked   | Grey (0.40,0.40,0.40) | `Color(0.55,0.55,0.55)`  | disabled |

A white outline arc is always drawn. A `Label` below the circle shows the
node's name.

### Overworld edge visuals

Edges are **not drawn** at runtime. The `_draw_edges()` function was removed;
`EdgesContainer` is retained as a placeholder for future visual work.

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

## BattleMap: Unit Position Cache

`BattleMap` maintains `_unit_by_cell: Dictionary` (Vector2i → Unit) for O(1)
cell lookups. All code paths that change a unit's cell must keep it in sync:

| Code path                | Action                                    |
|--------------------------|-------------------------------------------|
| `_spawn()`               | `_unit_by_cell[cell] = unit`              |
| `_commit_move()`         | erase old cell, insert new cell; `set_moved()` fires before tween |
| `_commit_placement_move()` | erase old cell, insert new cell         |
| `move_unit_instant()`    | erase old cell, snap, insert new cell     |
| `_on_unit_died()`        | `_unit_by_cell.erase(unit.grid_cell)`     |

`get_unit_at(cell) → Unit` reads directly from this dict (single lookup, no loop).

`move_unit_instant(unit, cell)` is the shared primitive for all non-tweened
moves. EnemyAI calls this instead of touching `snap_to_cell` + `set_cell_solid`
directly. BattleMap also exposes `perform_combat()` as public for EnemyAI.

## UnitSpawner

`scripts/battle/UnitSpawner.gd` — `@tool` Node2D used to author unit spawns
inside battle scenes. Fields:

| Property       | Type      | Meaning                                          |
|----------------|-----------|--------------------------------------------------|
| `unit_data`    | UnitData  | Which unit type to spawn                         |
| `is_player_unit` | bool    | `true` → player roster; `false` → enemy          |
| `cell`         | Vector2i  | Grid cell for enemy spawns (ignored for players) |

Setting `cell` in the inspector snaps the node's world position to the cell
centre (TILE_SIZE=40 px). In the editor, the spawner draws a coloured indicator
(blue for player, red for enemy) with the class initial letter so the level
layout is visible without running the game.

`BattleMap._begin_placement()` reads all `UnitSpawner` children of `SpawnersLayer`
to determine the player roster and enemy positions. See battle-system.md for
the full spawn logic.

## Key Invariants

- A cell is "solid" in AStarGrid2D whenever a unit occupies it.
- `_unit_by_cell` and A* solidity are always updated together via `move_unit_instant`
  or the `_commit_*` helpers — never update one without the other.
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

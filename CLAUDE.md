This is the repository that contains a game. The game is:

- A tactical RPG
- Grid-based

It seeks to emulate Fire Emblem, specifically the mobile version, Fire Emblem Heroes (FEH). However, it will modify it with several things:

- The movement must be extremely fluid and feel good.
- Minimal animations to maximize gameplay time. The board should mutate rapidly, with choices having to be done quickly.
- Another inspiration is chess, specifically the blitz time control. We seek to implement the feeling of "take, take, take" in chess when exchanging pieces and coming into favourable positions.

# Claude Code conventions

- Do not add `Co-Authored-By` lines to commit messages.
- Furthermore, we need to document every single gameplay feature we have in the game, so that claude code can keep track of the entire state of the game. Never make any commits until this is done. 

# WORKFLOW

After every code or scene change, in this order:
1. Run headless check: `"D:/godot-engine/Godot_v4.5-stable_win64_console.exe" --path "D:/code/kgs-feh-like" --headless --quit-after 5 "res://scenes/battle/battles/Battle_0.tscn" 2>&1` — fix all errors before proceeding.
2. Update the `Implemented` section in this file if a feature was added, changed, or removed.
3. Update the relevant file in `docs/` if architecture, a system's internals, or a public API changed.

# Technical Documentation

Detailed codebase documentation lives in `docs/`:

- `docs/architecture.md` — scene tree, autoloads, coordinate system, data resources
- `docs/battle-system.md` — drag-drop flow, attack range math, combat resolution, GridManager pathfinding
- `docs/turn-system.md` — PLAYER/ENEMY state machine, round lifecycle, EnemyAI coroutine

# Tech Stack

- **Engine:** Godot 4.5 (stable)
- **Executable:** `D:\godot-engine\Godot_v4.5-stable_win64_console.exe`
- **Language:** GDScript
- **External libraries:** None initially

# User controls:

- Drag and drop
- The player clicks and holds a sprite to move it. It then drops it on an available square within its range.

# Turn structure

- **One action per turn:** moving a unit immediately passes the turn to the enemy. There is no multi-unit selection.
- **Alternating actions:** player moves one unit → one enemy moves → repeat.
- **Round counter:** a round ends when every living unit on both sides has moved. The counter increments and all units reset (become selectable again).
- **Grey-out:** a unit is greyed out as soon as it has moved. It cannot be selected again until the next round.
- **End Turn button:** skips all remaining player moves for the round, then lets enemies finish their actions.
- This structure enforces the fast, blitz-chess pace of the game.

# Player

- Control several characters
- Several classes with skill trees should be available.

## Classes

- Knight, more hp and defense.
- Cavalry, can jump over allied units (intentional design choice — unlike standard FEH cavalry), more movement.
- Archer, ranged damage.
- Mage, spells that modify the board.

# Map

The game should have an overworld, which is basically a graph with edges and nodes with a background.
Each node is clickable, and represents an instance. Once the instance is entered, we change into a grid-based tactical tile.

## Overworld

A graph with edges. Each node represents an instance, and each edge represents a possible route. We open up edges progressively as a way to show progress.

## Instance
- grid-based, consisting of tiles. Units stand on tiles and move through them.

# Enemies

- **Armored Orc** (ClassType 4): enemy-only unit. HP 50, ATK 12, DEF 15, MOV 3, RNG 1. 3 spawn per battle at positions defined in `BattleMap.BATTLE_ENEMY_SPAWNS`. Same stats as Knight — the "tank" archetype for early battles.
- Future: add enemy variety (ranged, fast, boss units).

# Future / Stretch Goals

The following are potential ideas not in the confirmed scope of the initial build:

- A time control variant, a bit like Blitz. Maybe 3+2 (3 minute start, with a 2 second increment for each move)
- Certain tiles are more important, such as high ground tiles (attack/defense bonus).
- Certain tiles are dangerous (deal damage at end of turn to units standing on them).
- Formations. Attach units to each other for various bonuses, forsaking mobility and potentially action economy-
- Classes with skill trees.


# Implemented (as of Phase 9 completion)

- All 4 player classes + Armored Orc enemy with animated sprites (horizontal strip PNGs)
- 8×8 grid with A* pathfinding; Cavalry can jump allied units
- Drag-and-drop with ghost sprite, shortest-path arrow, and orange attack-range overlay
- Arrow always shows the true shortest BFS path from origin to hovered tile; capped at the unit's `move_range` (path never draws longer than the unit can move)
- Unit movement animates step-by-step along the shortest path (70 ms/cell) instead of tweening directly to the destination
- Single drag gesture: drop on movement tile = move; drop on enemy = move-then-attack
- TurnManager state machine: PLAYER_TURN ↔ ENEMY_TURN, round counter, grey-out
- EnemyAI: moves up to its full `move_range` toward the nearest player unit along an A* path, attacks if in range
- CombatResolver: ATK − DEF damage, counterattack if defender in range
- HUD: turn/round label, End Turn button, result screen (Victory/Defeat), Danger Zone toggle
- Danger Zone: red overlay showing all tiles enemy units can reach or attack
- Enemy hover inspection: hovering an enemy shows its move+attack range
- UnitSpawner nodes in Battle_*.tscn scenes for per-battle unit placement
- 3 battle nodes (Battle_0, Battle_1, Battle_2) with distinct enemy spawn positions
- Overworld graph with SaveData progression; victory unlocks next node
- Overworld nodes and edges are fully editor-configurable (see **Overworld authoring** below)
- Camera auto-fits to grid (largest integer zoom that keeps grid in viewport)
- `BattleMap._unit_by_cell` dictionary for O(1) cell→unit lookup (replaces O(n) linear scan)
- `BattleMap.move_unit_instant(unit, cell)` — shared primitive for all non-tweened moves; keeps `_unit_by_cell` and A* solidity in sync; used by EnemyAI
- `GridManager.get_shortest_path(start, goal, can_jump_allies, blocked_cells)` — BFS returning the actual cell path with the same blocking rules as `get_reachable_cells`
- `PlacementZoneLayer` (TileMapLayer, blue modulate) in each `Battle_*.tscn`: paint tiles in the Godot editor to define the pre-battle placement zone; hidden at runtime; falls back to `placement_zone_cols × placement_zone_rows` rectangle if empty
- `EnemySpawnLayer` (TileMapLayer, red modulate) in each `Battle_*.tscn`: each painted cell defines one enemy spawn point; hidden at runtime; falls back to random valid cells if empty
- `GridManager.tilemap_to_grid(tilemap_cell)` — converts a TileMapLayer cell coordinate to grid-local coords (subtracts `_origin`); used by all authoring layers
- `GridManager.TILE_TYPE_LAYERS` registry — maps TileMapLayer node name → `TileType`; `_read_tile_type_layers()` iterates it on `_ready()` to populate `_tile_types` and A* solidity; **adding a new tile type = one enum value + one dict entry + one new TileMapLayer node**
- `CollisionLayer` (near-black) — painted cells become `TileType.BLOCKED`: impassable to all units and A*
- `HighGroundLayer` (gold) — painted cells become `TileType.HIGH_GROUND`: ATK/DEF bonus (effect not yet implemented)
- `DangerousLayer` (orange) — painted cells become `TileType.DANGEROUS`: end-of-turn damage (effect not yet implemented)
- `AStarGrid2D` configured with `HEURISTIC_MANHATTAN` (correct for orthogonal grids) and `allow_partial_path=true` (enemies pathfind to nearest reachable cell when target is blocked)

# Overworld authoring

All overworld content is set up in `scenes/overworld/Overworld.tscn` — no code changes needed for new nodes, edges, or backgrounds.

## Adding a battle node

1. Open `Overworld.tscn` in the Godot editor.
2. In the scene tree, select `NodesContainer`.
3. Instance `scenes/overworld/OverworldNode.tscn` as a child.
4. Move it to the desired position on the map canvas.
5. In the Inspector, fill in three exported properties:
   - **Node Id** — unique integer (increment from the last node; must match the id used in SaveData progression)
   - **Node Label** — display name shown under the node circle
   - **Battle Scene** — res:// path to the battle scene (e.g. `res://scenes/battle/battles/Battle_3.tscn`)

## Adding an edge

1. Select the root `Overworld` node.
2. In the Inspector, find the **Edges** array.
3. Add an entry: `[id_a, id_b]` — the two node ids to connect.
4. Edges are drawn as white lines (unlocked) or grey lines (locked) at runtime; no further setup needed.

## Setting the map background

1. Select the `MapSprite` node (Sprite2D, `z_index = -1`).
2. In the Inspector, assign any JPG or PNG to its **Texture** property.
3. Adjust **Scale** so the image fills the viewport (1280×720). The `Background` ColorRect (`z_index = -2`) covers anything outside the image edges.

## Progression unlock rule

`SaveData.unlock_after_battle(battle_id)` appends `battle_id + 1` to `unlocked_node_ids`. Node 0 is always unlocked. New nodes start locked until the preceding battle is won.

# TODO


## Pre-battle state

- Do not use the existing battle movement system during placement. We should simply be able to drop the units.

## Overworld
- Add interesting side-nodes and more complex graph paths
- Dynamic battle grid sizing (currently fixed 8×8)

## Battle
- Bosses with unique stats or behaviour
- Class-specific active traits to distinguish units beyond stats (e.g. Mage board spells, Knight shield)
- Special tiles: high-ground (ATK/DEF bonus) and dangerous tiles (end-of-turn damage)

## Items
- Inventory slots and equippable items

## Art
- Additional enemy sprites and class variants

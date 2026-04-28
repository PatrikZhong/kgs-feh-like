# kgs-feh-like — Tactical RPG

A grid-based tactical RPG inspired by Fire Emblem Heroes (FEH), modified with a focus on speed and fluidity:

- Movement must feel extremely fluid and responsive.
- Minimal animations to maximize gameplay time — the board should mutate rapidly.
- A second inspiration is chess blitz: the feeling of "take, take, take" when exchanging pieces and seizing favourable positions.

---

# Instructions for Claude

## Conventions

- Do not add `Co-Authored-By` lines to commit messages.
- Every gameplay feature must be documented so Claude can track the full state of the game.

## Workflow

1. After every implementation, run the Godot headless check (see below) and fix all errors before finishing.
2. After every feature change, update the relevant file in `docs/`.
3. Never commit until both of the above are done.

### Headless check commands

```bash
# Battle scene
"D:/godot-engine/Godot_v4.5-stable_win64_console.exe" --path "D:/code/kgs-feh-like" --headless --quit-after 5 "res://scenes/battle/battles/Battle_0.tscn" 2>&1

# Overworld scene
"D:/godot-engine/Godot_v4.5-stable_win64_console.exe" --path "D:/code/kgs-feh-like" --headless --quit-after 5 "res://scenes/overworld/Overworld.tscn" 2>&1
```

Exit 0 + no `ERROR:` / `SCRIPT ERROR:` / `WARNING:` lines = clean.

---

# Project Setup

## Tech Stack

- **Engine:** Godot 4.5 (stable)
- **Executable:** `D:\godot-engine\Godot_v4.5-stable_win64_console.exe`
- **Language:** GDScript
- **External libraries:** None

## Documentation

Full codebase documentation lives in `docs/`:

- `docs/architecture.md` — scene tree, autoloads, coordinate system, data resources, BattleCamera, UnitSpawner
- `docs/battle-system.md` — drag-drop flow, attack range math, combat resolution, GridManager pathfinding
- `docs/turn-system.md` — PLAYER/ENEMY state machine, round lifecycle, EnemyAI coroutine

---

# Game Design

## Controls

- **Drag and drop.** The player clicks and holds a unit sprite to pick it up, then releases on a valid tile within its movement or attack range.

## Turn Structure

- **One action per turn:** moving a unit immediately ends that unit's turn. There is no multi-unit selection.
- **Initiative order:** units act in descending initiative order each round (Cavalry → Mage → Archer → Knight → Armored Orc).
- **Round counter:** a round ends when every living unit on both sides has acted. All units reset and become selectable again.
- **Grey-out:** a unit is visually darkened as soon as it moves. It cannot be selected again until the next round.
- **End Turn button:** skips all remaining player moves for the round, then lets enemies finish their actions.
- **Begin Battle button:** ends the placement phase and starts combat.

## Player Classes

| Class   | HP | ATK | DEF | MOV | RNG | Special |
|---------|----|-----|-----|-----|-----|---------|
| Knight  | 50 | 12  | 15  |  3  |  1  | Tank archetype |
| Cavalry | 36 | 14  |  8  |  5  |  1  | Can jump over allied units (intentional — unlike standard FEH) |
| Archer  | 34 | 16  |  6  |  3  |  2  | Ranged attacks |
| Mage    | 26 | 20  |  4  |  3  |  2  | Ranged attacks |

## Enemies

| Unit        | HP | ATK | DEF | MOV | RNG | Notes |
|-------------|----|----|-----|-----|-----|-------|
| Armored Orc | 50 | 12  | 15  |  3  |  1  | Enemy-only; tank archetype; 3 spawn per battle via UnitSpawner nodes |

## Map & Overworld

**Overworld:** A graph of clickable nodes connected by edges. Edges unlock progressively to show progression. Nodes are authored as `OverworldNodeUI` scene children; edges are an `@export var edges: Array` in `Overworld.gd`.

**Battle instance:** A grid-based tactical map. Units stand on tiles and move through them. Each battle is a `Battle_N.tscn` scene with `UnitSpawner` nodes defining enemy positions and types.

---

# How-To: Adding a New Unit Class

All character sprites live in `assets/sprites/Characters(100x100)/`.
Each class needs a sub-folder with 4 horizontal-strip PNGs (100×100 px per frame):

| File suffix   | Loops? | Typical frame count |
|---------------|--------|---------------------|
| `*-Idle.png`  | yes    | 6                   |
| `*-Walk.png`  | yes    | 8                   |
| `*-Hurt.png`  | no     | 4                   |
| `*-Death.png` | no     | 4                   |

**Step 1 — Add sprite sheets (manual)**

Place PNGs in a new folder:
```
assets/sprites/Characters(100x100)/MyClass/MyClass with shadows/
  MyClass-Idle.png
  MyClass-Walk.png
  MyClass-Hurt.png
  MyClass-Death.png
```
Each PNG must be a horizontal strip where every frame is exactly 100×100 px.

**Step 2 — Extend the `ClassType` enum in `scripts/data/UnitData.gd`**
```gdscript
enum ClassType { KNIGHT = 0, CAVALRY = 1, ARCHER = 2, MAGE = 3, ARMORED_ORC = 4, MY_CLASS = 5 }
```

**Step 3 — Add a `match` arm in `scripts/battle/Unit.gd:_get_sprite_paths()`**
```gdscript
UnitData.ClassType.MY_CLASS:
    return {
        "idle":  BASE + "MyClass/MyClass with shadows/MyClass-Idle.png",
        "walk":  BASE + "MyClass/MyClass with shadows/MyClass-Walk.png",
        "hurt":  BASE + "MyClass/MyClass with shadows/MyClass-Hurt.png",
        "death": BASE + "MyClass/MyClass with shadows/MyClass-Death.png",
    }
```

**Step 4 — Create a `.tres` resource file**

Duplicate an existing file in `resources/units/` (e.g. `KnightData.tres`) and update: `unit_name`, `class_type` (enum int), `max_hp`, `attack`, `defense`, `move_range`, `attack_range`, `can_jump_allies`, `initiative`.

**Step 5 — Add a `CLASS_LABELS` entry in `scripts/battle/Unit.gd`**
```gdscript
const CLASS_LABELS := ["K", "C", "A", "M", "O", "X"]  # one letter per ClassType
```

No other code changes required. The sprite system, HUD queue bar, and ghost drag pick up the new class automatically.

# TODO

## Unique Selling Point, FORMATION

A formation is when a specific type of character (A captain) has another type of character, a "troop", close to it in its nearby 3x3 grid. Depending on the relative position between the character and the other friendly character near it, it produces bonuses for the characters in formation.

Mechanics

- When in formation, the unit moves "as one". it means we treat their drag and drop as one single movement. 
- The initiative of the formation is the average initiative value. Maybe plus a constant from the captain.
- All initatives assume that facing east is "forward". We always keep the cardinal direction in such a way. 
- When attaching to a formation, we must confirm the move.
- We can leave a formation by clicking the unit, and then press a leave formation button. 
Algorithm for finding a formation:
- Any character around a NxN grid around the character. 



ideas for formations:

- In a formation, movement is reduced, but all units move the same time. 
- In a formation, stats are massively boosted (if its a good formation, such as a frontline with arrows in the back).
- Some people increase the formation range (such as a captain, that has a formation range of 4x4).
- Some people want to leave the formation, such as an assassin or rogue, to accomplish objectives or to harrass the enemy formation. Maybe they intend to kill the other enemy captain.
- The enemies will also be in formation.
    - This will be a good way of determining the difficulty of each map. As the enemy becomes smarter, they spawn in better formations and act more as a unit.
    - As we add more and more units to the formation, stats and interesting combinations inrease exponentially. 
- Getting into certain formations will trigger certain actions. A spearwall might create a spear thrust.
- The main playable character will mostly be a captain. The captain will be the one that decides the "flavour" of the run.

### Classes and Formations
Two specific types of units will exist:
- A "Captain" that keeps the formation together and acts as the pillar of whether a formation is allowed to exist or not. 
- A "Trooper" that is part of the formation. Troopers alone cannot create a formation. They need a captain somewhere in the geometry for a formation to work.

Examples:

    - A ranger captain might start with two knight troops to create a frontline formation.
    - A mage captain might have a single strong elemental troop to shield themselves from damage, will casting spells behind it. 
    - A knight captain might have a healer + ranger troops.
    - A bard captain might be weaker, but have more troops.

All units can be all classes, but there must be a captain version  and a trooper version. 

# Future / Stretch Goals

The following are potential ideas not in the confirmed scope of the initial build:

- Certain tiles are more important, such as high ground tiles (attack/defense bonus).
- Certain tiles are dangerous (deal damage at end of turn to units standing on them).
- Formations. Attach units to each other for various bonuses, forsaking mobility and potentially action economy-
- Classes with skill trees.
- Implement a roguelike aspect, where death is permanent but with small persistent rewards over time. 



## Stats

- Attack damage
- Defence
- Leadership. 1 leadership is one tile around the character. 2 leadership is two tiles etc... 1 = 3x3 grid, 2 = 4x4 grid. 
- Initiative. When in the turn you play.

## Overworld
- Add interesting side-nodes and more complex graph paths

### Battle
- Bosses with unique stats or behaviour
- Class-specific active abilities (e.g. Mage board spells, Knight shield)
- Special tiles: high-ground (ATK/DEF bonus) and dangerous tiles (end-of-turn damage)

### Items
- Inventory slots and equippable items

### Art
- Additional enemy sprites and class variants

## Stretch Goals

- **Blitz time control** — e.g. 3+2 (3 min start, 2 sec increment per move)
- **Tile modifiers** — high-ground (ATK/DEF bonus), dangerous tiles (end-of-turn damage)
- **Formations** — link units for bonuses at the cost of mobility and action economy
- **Skill trees** — per-class progression

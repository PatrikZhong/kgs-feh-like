# Formation System — Implementation Plan

> Source: CLAUDE.md §"Unique Selling Point, FORMATION"
>
> A formation is a Captain unit + one or more Trooper units within the
> Captain's leadership radius. The Captain anchors the formation; Troopers
> cannot form one alone. All members move simultaneously as a single drag.
> The relative position of each Trooper to the Captain (with East = forward)
> determines the bonus type — effects are **placeholders** throughout.

---

## 1. New Concepts Added to the Data Model

### 1.1 Unit roles

Every unit is either a **Captain** or a **Trooper**. This is a flag on `UnitData`:

```gdscript
# UnitData.gd — new field
@export var is_captain: bool = false
```

Troopers (`is_captain = false`) can exist on the board independently but cannot
anchor a formation. A Captain with no Troopers in range is also just an
independent unit — the formation only activates when at least one Trooper is
within range.

### 1.2 Leadership stat

A new integer stat on `UnitData`:

```gdscript
@export var leadership: int = 1
```

Determines the square Chebyshev radius within which Troopers can join:
- `leadership = 1` → 3×3 grid (8 neighbours + self)
- `leadership = 2` → 5×5 grid (24 neighbours + self)
- Formula: a Trooper at offset `(dx, dy)` from the Captain is in range when
  `max(abs(dx), abs(dy)) <= leadership`

Leadership 0 is valid (Captain with no formation range — effectively a solo unit).

### 1.3 `FormationGroup`

A plain `RefCounted` object created at runtime when a formation activates.
One instance per active formation; stored in `BattleMap`.

```gdscript
# scripts/battle/FormationGroup.gd
class_name FormationGroup
extends RefCounted

var captain: Unit
var troopers: Array[Unit] = []   # ordered; may be empty during join ceremony

## All members including the captain.
func members() -> Array[Unit]:
    return [captain] + troopers

## Grid offset of `member` relative to the captain's current cell.
## East (+x) = forward.
func relative_offset(member: Unit) -> Vector2i:
    return member.grid_cell - captain.grid_cell

## Classifies an offset into a named role — used to look up bonus type.
## Exact bonus = TODO. Only the role name matters for the plan.
func position_role(offset: Vector2i) -> StringName:
    if offset == Vector2i.ZERO:
        return &"CAPTAIN"
    if offset.x > 0 and offset.y == 0:
        return &"FRONT"
    if offset.x < 0 and offset.y == 0:
        return &"REAR"
    if offset.x == 0:
        return &"FLANK"
    return &"DIAGONAL"

## Combined initiative: average of all member initiatives.
## TODO: add captain's leadership as a flat bonus once balanced.
func formation_initiative() -> int:
    var total := 0
    for m in members():
        total += m.data.initiative
    return total / members().size()
```

---

## 2. Formation Lifecycle

```
State diagram for a single FormationGroup:

  [INACTIVE]
      │
      │  Trooper enters Captain's leadership range
      │  → BattleMap detects overlap → shows "Join Formation?" UI
      │
      ▼
  [PENDING JOIN]
      │  Player confirms
      │  → Trooper.formation_group = group
      │  → FormationGroup.troopers.append(trooper)
      │
      ▼
  [ACTIVE]
      │  Any move drag on Captain → moves all members
      │  Initiative queue entry = group (not individual units)
      │
      ├── Player clicks a trooper → "Leave Formation" button shown
      │        └── confirmed → trooper removed from group; acts independently
      │
      └── Captain dies → group dissolved; all troopers revert to independent
```

---

## 3. Formation Join Mechanic

### 3.1 When to check

After **every unit move** (`_commit_move`, `move_unit_instant`), scan for new
in-range relationships:

```
_check_formation_joins(moved_unit):
  if moved_unit is Captain:
    for each trooper on the board not already in a group:
      if max(|dx|, |dy|) <= captain.data.leadership:
        _open_join_prompt(trooper, captain's group)
  if moved_unit is Trooper (not in a group):
    for each Captain on the board:
      if max(|dx|, |dy|) <= captain.data.leadership:
        _open_join_prompt(moved_unit, captain's group)
```

Only player units prompt the player. Enemy formation joins happen silently
(auto-accepted).

### 3.2 Join prompt UI

A minimal confirmation that does not interrupt flow:

- A small **"Join?"** label appears above the Trooper.
- The Trooper's cell flashes gold.
- Player clicks **"Join"** (confirm) or **"Skip"** (dismiss for this round).
- Skipping does not permanently block joining — the prompt re-appears next time
  the Trooper moves back into range.

No modal dialog; the game is still live during the prompt (other units can still
act). The prompt auto-dismisses when either unit moves out of range.

Implementation: `_pending_join: Dictionary` on BattleMap (`trooper → captain`).
`HUD` gains a small overlay area for the join prompt, separate from the main HUD.

### 3.3 Confirming a join

```
_confirm_join(trooper, formation_group):
  formation_group.troopers.append(trooper)
  trooper.formation_group = formation_group  ← back-reference on Unit
  _pending_join.erase(trooper)
  formation_layer.refresh()
  TurnManager.rebuild_queue()   ← re-sort; formation now acts as one entry
```

---

## 4. Formation Leave Mechanic

No drag gesture. Leaving is always a deliberate button press:

1. Player clicks any Trooper that is in a formation (not dragging — just a click).
2. HUD shows a **"Leave Formation"** button (context-sensitive; only visible when
   a formation member is selected without dragging).
3. Player presses the button.
4. `_leave_formation(trooper)` is called — trooper is removed from the group and
   acts independently for the rest of the round.

Leaving does **not** consume the Trooper's action. The Trooper can still move
this round after leaving.

```
_leave_formation(trooper):
  var group = trooper.formation_group
  group.troopers.erase(trooper)
  trooper.formation_group = null
  if group.troopers.is_empty():
    _disband_group(group)   ← captain is now independent too
  formation_layer.refresh()
  TurnManager.rebuild_queue()
```

---

## 5. Formation Movement — The Core Mechanic

### 5.1 Detecting a formation drag

In `_begin_drag(unit)`: if `unit.is_captain` and `unit.formation_group != null`
and the group has at least one trooper → enter **formation drag mode**.

```gdscript
var _formation_drag: bool = false
var _formation_group: FormationGroup = null
```

### 5.2 Movement range in formation drag

The formation moves as a rigid block. Its effective move range is:

```
formation_move_range = min(member.data.move_range for all members)
```

The slowest member limits the group. This is the mobility cost.

### 5.3 Reachable cells for the formation

The BFS in `GridManager.get_reachable_cells` is called from the **Captain's**
cell with `formation_move_range`. But each candidate destination `dest` must
also be checked: can all Troopers fit at `dest + relative_offset(trooper)`?

```
_get_formation_reachable(group, grid_mgr) -> Array[Vector2i]:
  base_reachable = grid_mgr.get_reachable_cells(
      group.captain.grid_cell,
      formation_move_range,
      false,              ← formations do not jump over units
      enemy_cells)
  result = []
  for dest in base_reachable:
    all_fit = true
    for trooper in group.troopers:
      target_cell = dest + group.relative_offset(trooper)
      if not _cell_available_for_formation(target_cell, group):
        all_fit = false
        break
    if all_fit:
      result.append(dest)
  return result
```

`_cell_available_for_formation(cell, group)`: returns true if cell is in bounds,
not solid, and not occupied by a unit outside the group.

### 5.4 Ghost visuals during formation drag

Instead of one ghost, spawn one ghost per formation member. Each ghost maintains
its relative offset from the Captain ghost. As the Captain ghost follows the
cursor, all Trooper ghosts follow proportionally.

```
_formation_ghosts: Array[Node2D] = []

For each member in group.members():
    ghost = Node2D.new()
    ghost.add_child(member.make_ghost_sprite())
    units_layer.add_child(ghost)
    _formation_ghosts.append(ghost)
```

On mouse motion: Captain ghost follows cursor; Trooper ghosts snap to
`captain_ghost.position + grid_to_world(relative_offset(trooper))`.

### 5.5 Committing a formation move

On release at a valid `dest` cell:

```
_commit_formation_move(group, dest):
  for each member in group.members():
    target = dest + group.relative_offset(member)
    _commit_move(member, target, path=[])   ← instant snap; no individual tween
  TurnManager.end_player_turn()
  FormationManager.on_unit_moved(group)     ← Tier 3 hook for future use
```

All members are marked `has_moved = true` simultaneously. Formation groups use
`move_unit_instant` internally — the tween is reserved for solo units.

---

## 6. Initiative Integration

Currently `TurnManager` builds a flat queue of individual units sorted by
`initiative`. With formations, a group acts as **one queue entry**.

```
TurnManager.rebuild_queue():
  entries = []
  handled_units = {}

  for unit in all_units:
    if unit in handled_units: continue
    if unit.formation_group != null:
      group = unit.formation_group
      entries.append({
          "type": "formation",
          "group": group,
          "initiative": group.formation_initiative()
      })
      for m in group.members(): handled_units[m] = true
    else:
      entries.append({
          "type": "unit",
          "unit": unit,
          "initiative": unit.data.initiative
      })
      handled_units[unit] = true

  entries.sort_custom(func(a, b): return a.initiative > b.initiative)
  _queue = entries
```

When it is a formation's turn, the player drags the Captain. The Captain's
drag triggers the formation drag mode (§5.1). Enemy formations: EnemyAI moves
the Captain; all Troopers follow.

---

## 7. Relative Position Bonuses (Placeholder)

The bonus type for each Trooper is determined at combat time by
`FormationGroup.position_role(offset)`. The role names are fixed; the
stat deltas are `TODO`:

| Role | Offset (East = +x) | TODO effect |
|------|--------------------|-------------|
| `FRONT` | x > 0, y == 0 | TODO |
| `REAR` | x < 0, y == 0 | TODO |
| `FLANK` | x == 0, y ≠ 0 | TODO |
| `DIAGONAL` | x ≠ 0, y ≠ 0 | TODO |
| `CAPTAIN` | (0, 0) | TODO (captain bonus from having troopers) |

The lookup happens in `CombatResolver.resolve()` — same integration point as
before. `unit.formation_group?.position_role(...)` returns a `StringName`; a
`match` block maps it to stat deltas.

---

## 8. New Fields on `Unit`

```gdscript
# scripts/battle/Unit.gd — new fields

## The formation this unit belongs to, or null if independent.
var formation_group: FormationGroup = null
```

No `is_formation_anchor` needed anymore — the Captain role replaces it.
`has_moved` continues to be set for the whole group on formation commit.

---

## 9. Death and Dissolution

In `BattleMap._on_unit_died(unit)`:

```gdscript
if unit.formation_group != null:
    if unit.is_captain:
        _disband_group(unit.formation_group)  # all troopers become independent
    else:
        unit.formation_group.troopers.erase(unit)
        unit.formation_group = null
```

`_disband_group(group)`:
- Set `captain.formation_group = null`
- Set `trooper.formation_group = null` for each trooper
- Remove group from `_formations` array
- `TurnManager.rebuild_queue()`

---

## 10. `FormationLayer` Visual

Redraws on `turn_changed` and after every move. For each active formation:

- Draw a **gold line** from the Captain to each Trooper (shows the link).
- Draw a **gold ring** around the Captain (shows it as the anchor).
- Draw a faint **gold square** at the boundary of the Captain's leadership
  radius (shows the join zone) — only during placement, hidden in combat.

---

## 11. New Files

| File | Purpose |
|------|---------|
| `scripts/battle/FormationGroup.gd` | Data object: captain, troopers, offset helpers |
| `scripts/battle/FormationLayer.gd` | CanvasLayer: draws gold rings and lines |

No new autoload. Formation state lives on `BattleMap` (`_formations: Array[FormationGroup]`).

---

## 12. Implementation Sequence & Validation

### Step 1 — Data scaffold (no behaviour yet)

- Add `is_captain: bool` and `leadership: int` to `UnitData`.
- Add `formation_group: FormationGroup` to `Unit`.
- Add `FormationGroup.gd` (data only — no game logic).
- Add `_formations: Array[FormationGroup]` to `BattleMap`.
- **Headless check must pass.** No behaviour change yet.

### Step 2 — Formation creation (validation target)

Create a test formation manually in `BattleMap._ready()` after `_begin_placement()`:

```gdscript
# Temporary: wire up the first player Captain to all Troopers in range.
for unit in player_units:
    if unit.data.is_captain:
        var group := FormationGroup.new()
        group.captain = unit
        for other in player_units:
            if other != unit and not other.data.is_captain:
                var off := other.grid_cell - unit.grid_cell
                if max(abs(off.x), abs(off.y)) <= unit.data.leadership:
                    group.troopers.append(other)
                    other.formation_group = group
        unit.formation_group = group
        _formations.append(group)
        print("Formation: Captain + %d troopers" % group.troopers.size())
        break
```

**Validation**: run headless, confirm print fires with correct count.

### Step 3 — Formation drag

Implement formation drag mode (§5). Ghost shows all members moving.
**Validation**: drag Captain in editor, all Trooper ghosts follow. Dropping
moves all members.

### Step 4 — Join/Leave UI

Implement `_check_formation_joins`, join prompt overlay, leave button.
Remove the manual formation creation from Step 2.
**Validation**: move a Trooper adjacent to a Captain → prompt appears → confirm
→ both now drag as one.

### Step 5 — Initiative integration

Wire formations into `TurnManager.rebuild_queue()`.
**Validation**: formation acts as single entry in the HUD initiative bar.

### Step 6 — Balance pass

Fill in `position_role` → stat delta mappings in `CombatResolver`.

---

## 13. Open Questions

1. **Can a formation attack while moving?** Currently moving = end of turn.
   Does a formation drag onto an enemy trigger combat for all members, or just
   the Captain?
2. **Multiple Captains** — if two Captains are adjacent, do they merge or remain
   separate formations?
3. **Trooper initiative** — do Troopers outside a formation act on their own
   initiative, or does being a Trooper class mean they *always* need a Captain?
4. **Enemy formation visibility** — should the enemy's leadership radius be
   shown as a danger zone overlay (like the existing threat range)?
5. **Formation size limit** — is there a maximum number of Troopers per
   formation, or is it only bounded by the leadership radius?

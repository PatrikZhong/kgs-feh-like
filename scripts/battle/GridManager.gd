class_name GridManager
extends Node2D

enum TileType { NORMAL, HIGH_GROUND, DANGEROUS, BLOCKED }

const TILE_SIZE := Vector2i(40, 40)
const GRID_WIDTH := 8
const GRID_HEIGHT := 8

## Stores overridden tile types (cells not listed are NORMAL).
var _tile_types: Dictionary = {}
## Cells currently blocked by a unit.
var _solid_cells: Dictionary = {}

var _astar: AStarGrid2D

## GRASS+.png is sliced into 16×16 tiles; each battle node uses the next tile.
const GRASS_SHEET_PATH := "res://assets/sprites/GRASS+.png"
const GRASS_TILE_PX    := 16

var _bg_tile: Texture2D = null

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_bg_tile = _slice_tile(SaveData.current_battle_id)
	_setup_astar()
	queue_redraw()

## Returns an AtlasTexture for tile at `index` in GRASS+.png
## (left-to-right, top-to-bottom order).
func _slice_tile(index: int) -> Texture2D:
	var sheet: Texture2D = load(GRASS_SHEET_PATH)
	if not sheet:
		return null
	var cols: int = sheet.get_width() / GRASS_TILE_PX
	var atlas := AtlasTexture.new()
	atlas.atlas  = sheet
	atlas.region = Rect2(
		(index % cols) * GRASS_TILE_PX,
		(index / cols) * GRASS_TILE_PX,
		GRASS_TILE_PX, GRASS_TILE_PX)
	return atlas

func _setup_astar() -> void:
	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, GRID_WIDTH, GRID_HEIGHT)
	_astar.cell_size = Vector2(TILE_SIZE)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()

# ---------------------------------------------------------------------------
# Coordinate helpers
# ---------------------------------------------------------------------------

func grid_to_world(cell: Vector2i) -> Vector2:
	return Vector2(cell * TILE_SIZE) + Vector2(TILE_SIZE) / 2.0

func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(world_pos / Vector2(TILE_SIZE))

func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < GRID_WIDTH and cell.y >= 0 and cell.y < GRID_HEIGHT

# ---------------------------------------------------------------------------
# Tile type helpers
# ---------------------------------------------------------------------------

func get_tile_type(cell: Vector2i) -> TileType:
	return _tile_types.get(cell, TileType.NORMAL)

func set_tile_type(cell: Vector2i, type: TileType) -> void:
	_tile_types[cell] = type
	var solid = (type == TileType.BLOCKED)
	_astar.set_point_solid(cell, solid)
	queue_redraw()

# ---------------------------------------------------------------------------
# Unit occupancy (for pathfinding blocking)
# ---------------------------------------------------------------------------

func set_cell_solid(cell: Vector2i, solid: bool) -> void:
	if solid:
		_solid_cells[cell] = true
		_astar.set_point_solid(cell, true)
	else:
		_solid_cells.erase(cell)
		# Restore to tile-type-driven solid state
		_astar.set_point_solid(cell, get_tile_type(cell) == TileType.BLOCKED)

# ---------------------------------------------------------------------------
# Reachability (BFS, does not use A*)
# ---------------------------------------------------------------------------

## Returns all cells reachable from `start` within `move_range` steps.
## If `ignore_cells` is provided (e.g. enemy cells), those cells block movement
## but are still counted as reachable for attack purposes.
func get_reachable_cells(
		start: Vector2i,
		move_range: int,
		can_jump_allies: bool,
		blocked_cells: Array) -> Array[Vector2i]:

	var reachable: Array[Vector2i] = []
	var visited: Dictionary = {}
	# Queue entries: [cell, remaining_steps]
	var queue: Array = [[start, move_range]]

	while queue.size() > 0:
		var entry = queue.pop_front()
		var cell: Vector2i = entry[0]
		var remaining: int = entry[1]

		if visited.has(cell):
			continue
		visited[cell] = true
		reachable.append(cell)

		if remaining <= 0:
			continue

		for neighbor in _get_neighbors(cell):
			if visited.has(neighbor):
				continue
			if get_tile_type(neighbor) == TileType.BLOCKED:
				continue
			if not can_jump_allies and neighbor in blocked_cells:
				continue
			queue.append([neighbor, remaining - 1])

	return reachable

func _get_neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var n: Vector2i = cell + d
		if is_in_bounds(n):
			result.append(n)
	return result

# ---------------------------------------------------------------------------
# Pathfinding (A*)
# ---------------------------------------------------------------------------

func get_astar_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not is_in_bounds(from) or not is_in_bounds(to):
		return []
	return _astar.get_id_path(from, to)

# ---------------------------------------------------------------------------
# Visual (drawn without a TileSet for the prototype)
# ---------------------------------------------------------------------------

func _draw() -> void:
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var cell := Vector2i(x, y)
			var rect := Rect2(Vector2(cell * TILE_SIZE), Vector2(TILE_SIZE))

			# Draw base tile sprite (fallback to solid green if texture not loaded).
			if _bg_tile:
				draw_texture_rect(_bg_tile, rect, false)
			else:
				draw_rect(rect, Color(0.28, 0.44, 0.28), true)

			# Overlay a semi-transparent tint for non-normal tile types.
			match get_tile_type(cell):
				TileType.HIGH_GROUND: draw_rect(rect, Color(0.55, 0.45, 0.10, 0.50), true)
				TileType.DANGEROUS:   draw_rect(rect, Color(0.60, 0.15, 0.15, 0.50), true)
				TileType.BLOCKED:     draw_rect(rect, Color(0.10, 0.10, 0.10, 0.70), true)

@tool
class_name GridManager
extends Node2D

enum TileType { NORMAL, HIGH_GROUND, DANGEROUS, BLOCKED }

const TILE_SIZE := Vector2i(40, 40)
@export var grid_width: int = 8
@export var grid_height: int = 8
## Set false once you have a TileMapLayer painting the background.
@export var draw_background: bool = true

## Stores overridden tile types (cells not listed are NORMAL).
var _tile_types: Dictionary = {}
## Cells currently blocked by a unit.
var _solid_cells: Dictionary = {}
## TileMapLayer painted-area origin in tile coordinates (usually (0,0)).
var _origin: Vector2i = Vector2i.ZERO

var _astar: AStarGrid2D

## GRASS+.png is sliced into 16×16 tiles; each battle node uses the next tile.
const GRASS_SHEET_PATH := "res://assets/sprites/GRASS+.png"
const GRASS_TILE_PX    := 16

var _bg_tile: Texture2D = null

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if not Engine.is_editor_hint():
		_bg_tile = _slice_tile(SaveData.current_battle_id)
	_read_dimensions_from_tilemap()
	_setup_astar()
	queue_redraw()

## Reads grid dimensions and origin from the sibling TileMapLayer's painted area.
## Handles non-zero origins: the painted area can start at any tile coordinate.
## If the layer is absent or empty, the exported defaults are kept.
func _read_dimensions_from_tilemap() -> void:
	var tml := get_parent().get_node_or_null("TileMapLayer") as TileMapLayer
	if tml == null:
		return
	var rect: Rect2i = tml.get_used_rect()
	if rect.size == Vector2i.ZERO:
		return
	_origin     = rect.position
	grid_width  = rect.size.x
	grid_height = rect.size.y
	draw_background = false  # TileMapLayer owns the visual; suppress GridManager's fallback draw

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
	_astar.region = Rect2i(0, 0, grid_width, grid_height)
	_astar.cell_size = Vector2(TILE_SIZE)
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	_astar.update()

# ---------------------------------------------------------------------------
# Coordinate helpers
# ---------------------------------------------------------------------------

## World centre of a grid cell (grid coords are 0-based, offset by _origin).
func grid_to_world(cell: Vector2i) -> Vector2:
	return Vector2((cell + _origin) * TILE_SIZE) + Vector2(TILE_SIZE) / 2.0

## Grid cell that contains a world position.
func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i((world_pos - Vector2(_origin * TILE_SIZE)) / Vector2(TILE_SIZE))

func is_in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.x < grid_width and cell.y >= 0 and cell.y < grid_height

## Returns all grid cells that have a painted tile (grid-local 0-based coords).
## Falls back to the full grid if no TileMapLayer is present.
func get_valid_cells() -> Array[Vector2i]:
	var tml := get_parent().get_node_or_null("TileMapLayer") as TileMapLayer
	if tml == null:
		var result: Array[Vector2i] = []
		for y in range(grid_height):
			for x in range(grid_width):
				result.append(Vector2i(x, y))
		return result
	var result: Array[Vector2i] = []
	for world_cell in tml.get_used_cells():
		result.append(world_cell - _origin)
	return result

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

## Total world size of the painted grid in pixels (width × height, no origin offset).
func grid_world_size() -> Vector2:
	return Vector2(grid_width * TILE_SIZE.x, grid_height * TILE_SIZE.y)

## World-space centre of the painted grid (accounts for non-zero TileMapLayer origin).
func grid_world_center() -> Vector2:
	return Vector2((_origin.x + grid_width * 0.5) * TILE_SIZE.x,
				   (_origin.y + grid_height * 0.5) * TILE_SIZE.y)

func get_astar_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not is_in_bounds(from) or not is_in_bounds(to):
		return []
	return _astar.get_id_path(from, to)

# ---------------------------------------------------------------------------
# Visual (drawn without a TileSet for the prototype)
# ---------------------------------------------------------------------------

func _draw() -> void:
	for y in range(grid_height):
		for x in range(grid_width):
			var cell := Vector2i(x, y)
			# Draw position is offset by _origin so it aligns with the TileMapLayer.
			var world_cell := cell + _origin
			var rect := Rect2(Vector2(world_cell * TILE_SIZE), Vector2(TILE_SIZE))

			# Draw base tile sprite (skipped when a TileMapLayer handles the background).
			if draw_background:
				if _bg_tile:
					draw_texture_rect(_bg_tile, rect, false)
				else:
					draw_rect(rect, Color(0.28, 0.44, 0.28), true)

			# Overlay a semi-transparent tint for non-normal tile types.
			match get_tile_type(cell):
				TileType.HIGH_GROUND: draw_rect(rect, Color(0.55, 0.45, 0.10, 0.50), true)
				TileType.DANGEROUS:   draw_rect(rect, Color(0.60, 0.15, 0.15, 0.50), true)
				TileType.BLOCKED:     draw_rect(rect, Color(0.10, 0.10, 0.10, 0.70), true)

	# In the editor: draw cell grid lines and a bright outer border so you can
	# see exactly which TileMapLayer cells to paint.
	if Engine.is_editor_hint():
		var ox := float(_origin.x * TILE_SIZE.x)
		var oy := float(_origin.y * TILE_SIZE.y)
		var gw := float(grid_width  * TILE_SIZE.x)
		var gh := float(grid_height * TILE_SIZE.y)
		for y in range(grid_height + 1):
			var yf := oy + float(y * TILE_SIZE.y)
			draw_line(Vector2(ox, yf), Vector2(ox + gw, yf), Color(1, 1, 1, 0.25), 1.0)
		for x in range(grid_width + 1):
			var xf := ox + float(x * TILE_SIZE.x)
			draw_line(Vector2(xf, oy), Vector2(xf, oy + gh), Color(1, 1, 1, 0.25), 1.0)
		draw_rect(Rect2(ox, oy, gw, gh), Color(1, 1, 0, 0.9), false, 2.0)

extends Camera2D

const PAN_SPEED  := 400.0  ## screen-px/sec; divided by zoom so world movement feels consistent
const PAN_ZONE   := 60.0   ## px from viewport edge that triggers panning
const ZOOM_STEP  := 1.25   ## multiplier per scroll tick
const MAX_ZOOM   := 5.0
## Must match BottomBar custom_minimum_size.y in HUD.tscn.
const HUD_HEIGHT := 64.0

## Set to true while the player is dragging a unit so edge-pan doesn't fire.
var panning_locked: bool = false

var _fit_zoom: float = 1.0
var _grid_rect: Rect2 = Rect2()  # world-space bounding box of the painted grid

# ---------------------------------------------------------------------------
# Public API (called by BattleMap._fit_camera)
# ---------------------------------------------------------------------------

func setup(grid_center: Vector2, grid_size: Vector2, fit_zoom: float) -> void:
	_fit_zoom = fit_zoom
	_grid_rect = Rect2(grid_center - grid_size * 0.5, grid_size)
	position   = grid_center
	zoom       = Vector2(fit_zoom, fit_zoom)

# ---------------------------------------------------------------------------
# Edge panning
# ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	if panning_locked or _grid_rect.size == Vector2.ZERO:
		return

	var vp    := get_viewport().get_visible_rect().size
	var mouse := get_viewport().get_mouse_position()

	var dir := Vector2.ZERO
	if mouse.x < PAN_ZONE:
		dir.x -= 1.0
	elif mouse.x > vp.x - PAN_ZONE:
		dir.x += 1.0
	if mouse.y < PAN_ZONE:
		dir.y -= 1.0
	elif mouse.y > vp.y - HUD_HEIGHT - PAN_ZONE:
		dir.y += 1.0

	if dir == Vector2.ZERO:
		return

	position += dir.normalized() * (PAN_SPEED / zoom.x) * delta
	_clamp_position()

# ---------------------------------------------------------------------------
# Scroll zoom (zoom toward the cursor)
# ---------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var z := zoom.x
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_apply_zoom(z * ZOOM_STEP, event.position)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_apply_zoom(z / ZOOM_STEP, event.position)

func _apply_zoom(new_z: float, mouse_screen: Vector2) -> void:
	new_z = clampf(new_z, _fit_zoom, MAX_ZOOM)
	if is_equal_approx(new_z, zoom.x):
		return
	var vp_center := get_viewport().get_visible_rect().size * 0.5
	# World point currently under the cursor
	var world_before: Vector2 = (mouse_screen - vp_center) / zoom.x + position
	zoom = Vector2(new_z, new_z)
	# Shift so the same world point stays under the cursor after zoom
	position = world_before - (mouse_screen - vp_center) / new_z
	_clamp_position()

# ---------------------------------------------------------------------------
# Bounds clamping (shared by pan and zoom)
# ---------------------------------------------------------------------------

func _clamp_position() -> void:
	var vp    := get_viewport().get_visible_rect().size
	var half_w := (vp.x * 0.5) / zoom.x
	var half_h := ((vp.y - HUD_HEIGHT) * 0.5) / zoom.x

	# X axis
	if half_w * 2.0 >= _grid_rect.size.x:
		position.x = _grid_rect.get_center().x
	else:
		position.x = clampf(position.x,
			_grid_rect.position.x + half_w,
			_grid_rect.end.x      - half_w)

	# Y axis
	if half_h * 2.0 >= _grid_rect.size.y:
		position.y = _grid_rect.get_center().y
	else:
		position.y = clampf(position.y,
			_grid_rect.position.y + half_h,
			_grid_rect.end.y      - half_h)

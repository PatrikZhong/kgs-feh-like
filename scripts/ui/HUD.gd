extends CanvasLayer

signal threat_toggled(on: bool)

# ---------------------------------------------------------------------------
# Queue bar visual constants — adjust these to restyle the banner easily
# ---------------------------------------------------------------------------
const QUEUE_ICON_SIZE      := 100         # width & height of each slot box (px)
const QUEUE_ICON_GAP       := 6# horizontal gap between icons (px)
const QUEUE_ICON_FONT_SIZE := 18          # class-letter font size (fallback)
const QUEUE_SPRITE_SCALE   := 3.2       # portrait renders at this multiple of QUEUE_ICON_SIZE
const QUEUE_BG_COLOR       := Color(0.05, 0.05, 0.05, 1.00)  # near-black background
const QUEUE_PLAYER_COLOR   := Color(0.20, 0.55, 1.00, 1.00)  # blue  — player border
const QUEUE_ENEMY_COLOR    := Color(1.00, 0.25, 0.20, 1.00)  # red   — enemy border
const QUEUE_INACTIVE_ALPHA := 0.45        # border alpha for non-active slots
const QUEUE_BORDER_WIDTH   := 3           # border width for all slots
const QUEUE_ACTIVE_BORDER  := 4           # white border width on the active slot
const QUEUE_CORNER_RADIUS  := 5           # icon corner rounding
# ---------------------------------------------------------------------------

@onready var turn_label: Label          = %TurnLabel
@onready var end_turn_btn: Button       = %EndTurnButton
@onready var result_panel: Panel        = %ResultPanel
@onready var result_label: Label        = %ResultLabel
@onready var continue_btn: Button       = %ContinueButton
@onready var threat_toggle_btn: Button  = %ThreatToggleButton
@onready var queue_container: HBoxContainer = %QueueContainer

var _threat_on: bool = true
## Live icon nodes — rebuilt on every queue_updated emission.
var _queue_icons: Array[Control] = []

func _ready() -> void:
	TurnManager.turn_changed.connect(_on_turn_changed)
	TurnManager.battle_won.connect(_on_battle_won)
	TurnManager.battle_lost.connect(_on_battle_lost)
	TurnManager.new_round.connect(_on_new_round)
	TurnManager.queue_updated.connect(_on_queue_updated)
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	continue_btn.pressed.connect(_on_continue_pressed)
	threat_toggle_btn.pressed.connect(_on_threat_toggle_pressed)
	queue_container.add_theme_constant_override("separation", QUEUE_ICON_GAP)
	result_panel.visible = false
	_refresh_turn_ui(TurnManager.current_state)

# ---------------------------------------------------------------------------
# Queue bar
# ---------------------------------------------------------------------------

func _on_queue_updated(queue: Array, active_index: int) -> void:
	# Remove previous icons.
	for icon in _queue_icons:
		icon.queue_free()
	_queue_icons.clear()

	for i in range(queue.size()):
		var unit = queue[i]
		if not is_instance_valid(unit):
			continue  # dead unit — slot collapses from the bar
		var icon := _make_queue_icon(unit, i == active_index)
		queue_container.add_child(icon)
		_queue_icons.append(icon)

## Creates one queue slot icon.  All visual properties are driven by the
## constants above, so restyling only requires editing those values.
## Uses Panel (not PanelContainer) so the portrait can overflow the box bounds.
func _make_queue_icon(unit: Unit, is_active: bool) -> Control:
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(QUEUE_ICON_SIZE, QUEUE_ICON_SIZE)
	panel.clip_contents = false
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	# Active slot renders above its neighbours so overflowing sprite isn't clipped.
	panel.z_index = 1 if is_active else 0

	var border_color: Color = QUEUE_PLAYER_COLOR if unit.is_player_unit else QUEUE_ENEMY_COLOR
	if not is_active:
		border_color.a = QUEUE_INACTIVE_ALPHA

	var style := StyleBoxFlat.new()
	style.bg_color = QUEUE_BG_COLOR
	style.corner_radius_top_left     = QUEUE_CORNER_RADIUS
	style.corner_radius_top_right    = QUEUE_CORNER_RADIUS
	style.corner_radius_bottom_left  = QUEUE_CORNER_RADIUS
	style.corner_radius_bottom_right = QUEUE_CORNER_RADIUS
	if is_active:
		style.border_color        = Color.WHITE
		style.border_width_top    = QUEUE_ACTIVE_BORDER
		style.border_width_bottom = QUEUE_ACTIVE_BORDER
		style.border_width_left   = QUEUE_ACTIVE_BORDER
		style.border_width_right  = QUEUE_ACTIVE_BORDER
	else:
		style.border_color        = border_color
		style.border_width_top    = QUEUE_BORDER_WIDTH
		style.border_width_bottom = QUEUE_BORDER_WIDTH
		style.border_width_left   = QUEUE_BORDER_WIDTH
		style.border_width_right  = QUEUE_BORDER_WIDTH
	panel.add_theme_stylebox_override("panel", style)

	var portrait := unit.get_portrait_texture()
	if portrait:
		# The portrait is rendered larger than the box and centered, so it
		# overflows on all sides.  clip_contents=false lets it show through.
		var display_size: float = QUEUE_ICON_SIZE * QUEUE_SPRITE_SCALE
		var offset: float = (QUEUE_ICON_SIZE - display_size) / 2.0
		var tex_rect := TextureRect.new()
		tex_rect.texture = portrait
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex_rect.size = Vector2(display_size, display_size)
		tex_rect.position = Vector2(offset, offset)
		tex_rect.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.add_child(tex_rect)
	else:
		# Fallback: class letter when sprite is unavailable.
		var lbl := Label.new()
		lbl.text = Unit.CLASS_LABELS[unit.data.class_type]
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment   = VERTICAL_ALIGNMENT_CENTER
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.add_theme_font_size_override("font_size", QUEUE_ICON_FONT_SIZE)
		lbl.mouse_filter = Control.MOUSE_FILTER_PASS
		panel.add_child(lbl)

	return panel

# ---------------------------------------------------------------------------
# Turn label / button state
# ---------------------------------------------------------------------------

func _on_turn_changed(state: TurnManager.State) -> void:
	_refresh_turn_ui(state)

func _on_new_round(count: int) -> void:
	_refresh_turn_ui(TurnManager.current_state)

func _refresh_turn_ui(state: TurnManager.State) -> void:
	match state:
		TurnManager.State.PLACEMENT:
			turn_label.text = "Placement Phase"
			end_turn_btn.text = "Begin Battle"
			end_turn_btn.disabled = false
		TurnManager.State.PLAYER_TURN:
			turn_label.text = "Round %d — Your Turn" % TurnManager.turn_count
			end_turn_btn.text = "End Turn"
			end_turn_btn.disabled = false
		TurnManager.State.ENEMY_TURN, TurnManager.State.ACTING:
			turn_label.text = "Round %d — Enemy Turn" % TurnManager.turn_count
			end_turn_btn.text = "End Turn"
			end_turn_btn.disabled = true

## "Begin Battle" during placement, or "End Turn" during combat.
func _on_end_turn_pressed() -> void:
	if TurnManager.current_state == TurnManager.State.PLACEMENT:
		TurnManager.start_combat()
		return
	# Skip all remaining player-controlled slots this round.
	if TurnManager.battle_map:
		for unit in TurnManager.battle_map.player_units:
			if is_instance_valid(unit) and not unit.has_moved:
				unit.set_moved()
	TurnManager.end_player_turn()

func _on_battle_won() -> void:
	result_panel.visible = true
	result_label.text = "Victory!"
	SaveData.unlock_after_battle(SaveData.current_battle_id)

func _on_battle_lost() -> void:
	result_panel.visible = true
	result_label.text = "Defeat!"

func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")

func _on_threat_toggle_pressed() -> void:
	_threat_on = not _threat_on
	threat_toggle_btn.text = "Danger Zone: ON" if _threat_on else "Danger Zone: OFF"
	threat_toggled.emit(_threat_on)

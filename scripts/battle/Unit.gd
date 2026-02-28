class_name Unit
extends Node2D

signal died(unit: Unit)

@export var data: UnitData

var current_hp: int = 0
var has_moved: bool = false
var has_attacked: bool = false
var grid_cell: Vector2i = Vector2i.ZERO
var is_player_unit: bool = true

var _is_dragging: bool = false

# Colours used for drawing
const PLAYER_COLOR  := Color(0.20, 0.45, 0.90)
const ENEMY_COLOR   := Color(0.85, 0.25, 0.20)
const SPENT_DARKEN  := 0.45
const UNIT_RADIUS   := 22.0
const CLASS_LABELS  := ["K", "C", "A", "M"]

func _ready() -> void:
	if data:
		current_hp = data.max_hp
	queue_redraw()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func take_damage(amount: int) -> void:
	current_hp -= maxi(1, amount)
	current_hp = maxi(0, current_hp)
	queue_redraw()
	if current_hp <= 0:
		emit_signal("died", self)

func snap_to_cell(cell: Vector2i, grid_manager: GridManager) -> void:
	grid_cell = cell
	position = grid_manager.grid_to_world(cell)

func reset_turn() -> void:
	has_moved = false
	has_attacked = false
	queue_redraw()

func set_moved() -> void:
	has_moved = true
	queue_redraw()

func set_attacked() -> void:
	has_attacked = true
	queue_redraw()

func start_drag() -> void:
	_is_dragging = true
	z_index = 100
	queue_redraw()

func end_drag() -> void:
	_is_dragging = false
	z_index = 0
	queue_redraw()

func play_hit_flash() -> void:
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.RED, 0.075)
	tween.tween_property(self, "modulate", Color.WHITE, 0.075)

func is_spent() -> bool:
	return has_moved

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	var base_color := PLAYER_COLOR if is_player_unit else ENEMY_COLOR
	if is_spent():
		base_color = base_color.darkened(SPENT_DARKEN)
	if _is_dragging:
		base_color.a = 0.70

	# Body circle
	draw_circle(Vector2.ZERO, UNIT_RADIUS, base_color)
	# Outline
	draw_arc(Vector2.ZERO, UNIT_RADIUS, 0.0, TAU, 32, Color.WHITE, 2.0)

	# Class letter
	if data:
		var label: String = CLASS_LABELS[data.class_type]
		var font := ThemeDB.fallback_font
		var font_size := 16
		var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		draw_string(font, -text_size / 2.0 + Vector2(0, text_size.y / 4.0), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# HP bar
	if data and data.max_hp > 0:
		var bar_w := UNIT_RADIUS * 2.0
		var bar_h := 5.0
		var bar_y := UNIT_RADIUS + 4.0
		var hp_ratio := float(current_hp) / float(data.max_hp)
		draw_rect(Rect2(-bar_w / 2.0, bar_y, bar_w, bar_h), Color(0.3, 0.0, 0.0), true)
		draw_rect(Rect2(-bar_w / 2.0, bar_y, bar_w * hp_ratio, bar_h), Color.GREEN, true)

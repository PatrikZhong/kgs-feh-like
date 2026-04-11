class_name Unit
extends Node2D

signal died(unit: Unit)

@export var data: UnitData

var current_hp: int = 0
var has_moved: bool = false
var has_attacked: bool = false
var grid_cell: Vector2i = Vector2i.ZERO
var is_player_unit: bool = true
var attack_range: int = 1

var _is_dragging: bool = false
var _animated_sprite: AnimatedSprite2D = null

# Colours used for drawing
const PLAYER_COLOR  := Color(0.20, 0.45, 0.90)
const ENEMY_COLOR   := Color(0.85, 0.25, 0.20)
const SPENT_DARKEN  := 0.45
const UNIT_RADIUS   := 22.0
const CLASS_LABELS  := ["K", "C", "A", "M", "O"]

# Sprites are 100×100 px per frame; scaled to fill a 64px tile.
const SPRITE_FRAME_PX := 100
const SPRITE_SCALE    := 1.3

func _ready() -> void:
	if data:
		current_hp = data.max_hp
		attack_range = data.attack_range
		_setup_sprite()
	queue_redraw()

# ---------------------------------------------------------------------------
# Sprite setup
# ---------------------------------------------------------------------------

func _setup_sprite() -> void:
	var paths := _get_sprite_paths()
	if paths.is_empty():
		return

	var frames := SpriteFrames.new()
	var loop_anims := ["idle", "walk"]

	for anim_name: String in paths:
		var tex: Texture2D = load(paths[anim_name])
		if not tex:
			continue
		var frame_count: int = tex.get_width() / SPRITE_FRAME_PX
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, anim_name in loop_anims)
		frames.set_animation_speed(anim_name, 8.0)
		for i in frame_count:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(i * SPRITE_FRAME_PX, 0, SPRITE_FRAME_PX, SPRITE_FRAME_PX)
			frames.add_frame(anim_name, atlas)

	_animated_sprite = AnimatedSprite2D.new()
	_animated_sprite.sprite_frames = frames
	_animated_sprite.scale = Vector2(SPRITE_SCALE, SPRITE_SCALE)
	_animated_sprite.flip_h = not is_player_unit  # Enemies face left
	_animated_sprite.animation_finished.connect(_on_animation_finished)
	_animated_sprite.play("idle")
	add_child(_animated_sprite)


func _get_sprite_paths() -> Dictionary:
	const BASE := "res://assets/sprites/Characters(100x100)/"
	match data.class_type:
		UnitData.ClassType.KNIGHT:
			return {
				"idle":  BASE + "Knight/Knight with shadows/Knight-Idle.png",
				"walk":  BASE + "Knight/Knight with shadows/Knight-Walk.png",
				"hurt":  BASE + "Knight/Knight with shadows/Knight-Hurt.png",
				"death": BASE + "Knight/Knight with shadows/Knight-Death.png",
			}
		UnitData.ClassType.CAVALRY:
			return {
				"idle":  BASE + "Lancer/Lancer with shadows/Lancer-Idle.png",
				"walk":  BASE + "Lancer/Lancer with shadows/Lancer-Walk01.png",
				"hurt":  BASE + "Lancer/Lancer with shadows/Lancer-Hurt.png",
				"death": BASE + "Lancer/Lancer with shadows/Lancer-Death.png",
			}
		UnitData.ClassType.ARCHER:
			return {
				"idle":  BASE + "Archer/Archer with shadows/Archer-Idle.png",
				"walk":  BASE + "Archer/Archer with shadows/Archer-Walk.png",
				"hurt":  BASE + "Archer/Archer with shadows/Archer-Hurt.png",
				"death": BASE + "Archer/Archer with shadows/Archer-Death.png",
			}
		UnitData.ClassType.MAGE:
			return {
				"idle":  BASE + "Wizard/Wizard with shadows/Wizard-Idle.png",
				"walk":  BASE + "Wizard/Wizard with shadows/Wizard-Walk.png",
				"hurt":  BASE + "Wizard/Wizard with shadows/Wizard-Hurt.png",
				"death": BASE + "Wizard/Wizard with shadows/Wizard-DEATH.png",
			}
		UnitData.ClassType.ARMORED_ORC:
			return {
				"idle":  BASE + "Armored Orc/Armored Orc with shadows/Armored Orc-Idle.png",
				"walk":  BASE + "Armored Orc/Armored Orc with shadows/Armored Orc-Walk.png",
				"hurt":  BASE + "Armored Orc/Armored Orc with shadows/Armored Orc-Hurt.png",
				"death": BASE + "Armored Orc/Armored Orc with shadows/Armored Orc-Death.png",
			}
	return {}


func _on_animation_finished() -> void:
	if _animated_sprite and _animated_sprite.animation in ["hurt", "death"]:
		if _animated_sprite.animation == "hurt":
			_animated_sprite.play("idle")

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

func take_damage(amount: int) -> void:
	current_hp -= maxi(1, amount)
	current_hp = maxi(0, current_hp)
	queue_redraw()
	if current_hp <= 0:
		died.emit(self)

func snap_to_cell(cell: Vector2i, grid_manager: GridManager) -> void:
	grid_cell = cell
	position = grid_manager.grid_to_world(cell)

func reset_turn() -> void:
	has_moved = false
	has_attacked = false
	if _animated_sprite:
		_animated_sprite.modulate = Color.WHITE
	queue_redraw()

func set_moved() -> void:
	has_moved = true
	if _animated_sprite:
		_animated_sprite.modulate = Color.WHITE.darkened(SPENT_DARKEN)
	queue_redraw()

func set_attacked() -> void:
	has_attacked = true
	queue_redraw()

func start_drag() -> void:
	_is_dragging = true
	modulate.a = 0.4  # dim original in place; ghost takes over visually
	queue_redraw()

func end_drag() -> void:
	_is_dragging = false
	modulate.a = 1.0
	queue_redraw()

## Returns a semi-transparent AnimatedSprite2D clone suitable for use as a
## drag ghost. The caller is responsible for adding it to the scene tree.
func make_ghost_sprite() -> AnimatedSprite2D:
	if not _animated_sprite:
		return null
	var ghost := AnimatedSprite2D.new()
	ghost.sprite_frames = _animated_sprite.sprite_frames
	ghost.scale         = _animated_sprite.scale
	ghost.flip_h        = _animated_sprite.flip_h
	ghost.modulate      = Color(1.0, 1.0, 1.0, 0.65)
	ghost.play("walk")
	return ghost

func play_hit_flash() -> void:
	if _animated_sprite:
		_animated_sprite.play("hurt")
	var tween := create_tween()
	tween.tween_property(self, "modulate", Color.RED, 0.075)
	tween.tween_property(self, "modulate", Color.WHITE, 0.075)

func is_spent() -> bool:
	return has_moved

# ---------------------------------------------------------------------------
# Drawing
# ---------------------------------------------------------------------------

func _draw() -> void:
	# Draw placeholder circle + class letter only when no sprite is active.
	if not _animated_sprite:
		var base_color := PLAYER_COLOR if is_player_unit else ENEMY_COLOR
		if is_spent():
			base_color = base_color.darkened(SPENT_DARKEN)
		if _is_dragging:
			base_color.a = 0.70
		draw_circle(Vector2.ZERO, UNIT_RADIUS, base_color)
		draw_arc(Vector2.ZERO, UNIT_RADIUS, 0.0, TAU, 32, Color.WHITE, 2.0)
		if data:
			var label: String = CLASS_LABELS[data.class_type]
			var font := ThemeDB.fallback_font
			var font_size := 16
			var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
			draw_string(font, -text_size / 2.0 + Vector2(0, text_size.y / 4.0), label,
					HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)

	# HP bar always drawn, positioned below whichever visual is active.
	if data and data.max_hp > 0:
		var bar_w  := (SPRITE_FRAME_PX * SPRITE_SCALE * 0.15) if _animated_sprite else (UNIT_RADIUS * 2.0)
		var bar_h  := 2.0
		var bar_y  := (SPRITE_FRAME_PX * SPRITE_SCALE * 0.15) if _animated_sprite \
				else UNIT_RADIUS + 4.0
		var hp_pct := float(current_hp) / float(data.max_hp)
		draw_rect(Rect2(-bar_w / 2.0, bar_y, bar_w, bar_h), Color(0.3, 0.0, 0.0), true)
		draw_rect(Rect2(-bar_w / 2.0, bar_y, bar_w * hp_pct, bar_h), Color.DARK_RED, true)

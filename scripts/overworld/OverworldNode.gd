class_name OverworldNodeUI
extends Node2D

signal node_clicked(id: int, scene_path: String)

const RADIUS := 28.0
const LOCKED_COLOR   := Color(0.40, 0.40, 0.40)
const UNLOCKED_COLOR := Color(0.90, 0.75, 0.20)

## Set these in the Godot editor — place the node visually, then fill the inspector.
@export var node_id: int = 0
@export var node_label: String = ""
@export var battle_scene: String = ""

var _unlocked: bool = false

@onready var _button: Button = $Button
@onready var _label_node: Label = $Label

func _ready() -> void:
	_unlocked = SaveData.is_node_unlocked(node_id)
	if _label_node:
		_label_node.text = node_label
	if _button:
		_button.disabled = not _unlocked
		_button.pressed.connect(_on_pressed)
	modulate = Color.WHITE if _unlocked else Color(0.55, 0.55, 0.55)
	queue_redraw()

func _on_pressed() -> void:
	emit_signal("node_clicked", node_id, battle_scene)

func _draw() -> void:
	var color := UNLOCKED_COLOR if _unlocked else LOCKED_COLOR
	draw_circle(Vector2.ZERO, RADIUS, color)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, Color.WHITE, 2.5)

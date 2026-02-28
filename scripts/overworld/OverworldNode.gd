class_name OverworldNodeUI
extends Node2D

signal node_clicked(id: int, scene_path: String)

const RADIUS := 28.0
const LOCKED_COLOR  := Color(0.40, 0.40, 0.40)
const UNLOCKED_COLOR := Color(0.90, 0.75, 0.20)

var _id: int = 0
var _label: String = ""
var _scene_path: String = ""
var _unlocked: bool = false

@onready var _button: Button = $Button
@onready var _label_node: Label = $Label

func setup(id: int, label: String, scene_path: String, unlocked: bool) -> void:
	_id = id
	_label = label
	_scene_path = scene_path
	_unlocked = unlocked
	if _label_node:
		_label_node.text = label
	if _button:
		_button.disabled = not unlocked
	modulate = Color.WHITE if unlocked else Color(0.55, 0.55, 0.55)
	queue_redraw()

func _ready() -> void:
	if _button:
		_button.pressed.connect(_on_pressed)

func _on_pressed() -> void:
	emit_signal("node_clicked", _id, _scene_path)

func _draw() -> void:
	var color := UNLOCKED_COLOR if _unlocked else LOCKED_COLOR
	draw_circle(Vector2.ZERO, RADIUS, color)
	draw_arc(Vector2.ZERO, RADIUS, 0.0, TAU, 32, Color.WHITE, 2.5)

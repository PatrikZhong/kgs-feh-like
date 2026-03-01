extends Node2D

const OVERWORLD_NODE_SCENE := preload("res://scenes/overworld/OverworldNode.tscn")

# Inline world data for the prototype.
# TODO: load from a WorldGraph .tres resource.
const _WORLD_NODES := [
	{"id": 0, "label": "Tutorial",    "pos": Vector2(200, 300), "scene": "res://scenes/battle/BattleMap.tscn"},
	{"id": 1, "label": "Forest Path", "pos": Vector2(420, 180), "scene": "res://scenes/battle/BattleMap.tscn"},
	{"id": 2, "label": "River Ford",  "pos": Vector2(640, 310), "scene": "res://scenes/battle/BattleMap.tscn"},
]
const _WORLD_EDGES := [
	{"a": 0, "b": 1},
	{"a": 1, "b": 2},
]

@onready var edges_container: Node2D = $EdgesContainer
@onready var nodes_container: Node2D = $NodesContainer

func _ready() -> void:
	_draw_edges()
	_spawn_nodes()

func _draw_edges() -> void:
	for edge_data in _WORLD_EDGES:
		var a_pos := _get_node_pos(edge_data["a"])
		var b_pos := _get_node_pos(edge_data["b"])
		if a_pos == Vector2.ZERO or b_pos == Vector2.ZERO:
			continue

		var unlocked := SaveData.is_node_unlocked(edge_data["a"]) and SaveData.is_node_unlocked(edge_data["b"])

		var line := Line2D.new()
		line.add_point(a_pos)
		line.add_point(b_pos)
		line.width = 4.0
		line.default_color = Color.WHITE if unlocked else Color(0.5, 0.5, 0.5, 0.6)
		edges_container.add_child(line)

func _spawn_nodes() -> void:
	for node_data in _WORLD_NODES:
		var instance = OVERWORLD_NODE_SCENE.instantiate()
		instance.position = node_data["pos"]
		var unlocked := SaveData.is_node_unlocked(node_data["id"])
		instance.setup(node_data["id"], node_data["label"], node_data["scene"], unlocked)
		instance.node_clicked.connect(_on_node_clicked)
		nodes_container.add_child(instance)

func _on_node_clicked(id: int, scene_path: String) -> void:
	SaveData.current_battle_id = id
	get_tree().change_scene_to_file(scene_path)

func _get_node_pos(id: int) -> Vector2:
	for n in _WORLD_NODES:
		if n["id"] == id:
			return n["pos"]
	return Vector2.ZERO

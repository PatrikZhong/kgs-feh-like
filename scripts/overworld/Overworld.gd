extends Node2D

## Each entry is [id_a, id_b]. Edit in the inspector to wire up connections.
## Add a new entry whenever you add a new battle node to NodesContainer.
@export var edges: Array = [[0, 1], [1, 2]]

@onready var edges_container: Node2D = $EdgesContainer
@onready var nodes_container: Node2D = $NodesContainer

func _ready() -> void:
	_setup_nodes()

func _setup_nodes() -> void:
	for child in nodes_container.get_children():
		if child is OverworldNodeUI:
			child.node_clicked.connect(_on_node_clicked)

func _on_node_clicked(id: int, scene_path: String) -> void:
	SaveData.current_battle_id = id
	get_tree().change_scene_to_file(scene_path)

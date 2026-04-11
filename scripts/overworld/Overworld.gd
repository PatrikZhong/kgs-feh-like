extends Node2D

## Each entry is [id_a, id_b]. Edit in the inspector to wire up connections.
## Add a new entry whenever you add a new battle node to NodesContainer.
@export var edges: Array = [[0, 1], [1, 2]]

@onready var edges_container: Node2D = $EdgesContainer
@onready var nodes_container: Node2D = $NodesContainer

func _ready() -> void:
	_setup_nodes()
	_draw_edges()

func _setup_nodes() -> void:
	for child in nodes_container.get_children():
		if child is OverworldNodeUI:
			child.node_clicked.connect(_on_node_clicked)

func _draw_edges() -> void:
	var positions: Dictionary = {}
	for child in nodes_container.get_children():
		if child is OverworldNodeUI:
			positions[child.node_id] = child.position

	for edge in edges:
		var a_id: int = edge[0]
		var b_id: int = edge[1]
		if not positions.has(a_id) or not positions.has(b_id):
			continue
		var unlocked := SaveData.is_node_unlocked(a_id) and SaveData.is_node_unlocked(b_id)
		var line := Line2D.new()
		line.add_point(positions[a_id])
		line.add_point(positions[b_id])
		line.width = 4.0
		line.default_color = Color.WHITE if unlocked else Color(0.5, 0.5, 0.5, 0.6)
		edges_container.add_child(line)

func _on_node_clicked(id: int, scene_path: String) -> void:
	SaveData.current_battle_id = id
	get_tree().change_scene_to_file(scene_path)

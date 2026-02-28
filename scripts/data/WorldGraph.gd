class_name WorldGraph
extends Resource

@export var nodes: Array[WorldNode] = []
@export var edges: Array[WorldEdge] = []

func get_node(id: int) -> WorldNode:
	for n in nodes:
		if n.id == id:
			return n
	return null

func get_edges_for_node(id: int) -> Array[WorldEdge]:
	var result: Array[WorldEdge] = []
	for e in edges:
		if e.node_a == id or e.node_b == id:
			result.append(e)
	return result

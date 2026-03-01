extends Node

## IDs of overworld nodes the player has unlocked (completed or accessible).
var unlocked_node_ids: Array[int] = [0]
## IDs of overworld edges that are now open.
var unlocked_edge_indices: Array[int] = []
## ID of the battle node currently being played.
var current_battle_id: int = 0

## Called on victory: unlocks the next overworld node.
func unlock_after_battle(completed_id: int) -> void:
	var next_id := completed_id + 1
	if next_id not in unlocked_node_ids:
		unlocked_node_ids.append(next_id)

func is_node_unlocked(id: int) -> bool:
	return id in unlocked_node_ids

func unlock_edge(index: int) -> void:
	if index not in unlocked_edge_indices:
		unlocked_edge_indices.append(index)

func is_edge_unlocked(index: int) -> bool:
	return index in unlocked_edge_indices

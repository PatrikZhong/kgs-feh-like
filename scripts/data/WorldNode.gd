class_name WorldNode
extends Resource

@export var id: int = 0
@export var label: String = ""
@export var position: Vector2 = Vector2.ZERO
## Path to the BattleMap .tscn for this node.
@export var battle_scene: String = "res://scenes/battle/BattleMap.tscn"

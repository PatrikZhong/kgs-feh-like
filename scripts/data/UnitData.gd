class_name UnitData
extends Resource

enum ClassType { KNIGHT = 0, CAVALRY = 1, ARCHER = 2, MAGE = 3, ARMORED_ORC = 4 }

@export var unit_name: String = ""
@export var class_type: ClassType = ClassType.KNIGHT
@export var max_hp: int = 30
@export var attack: int = 10
@export var defense: int = 5
@export var move_range: int = 3
@export var attack_range: int = 1
## Cavalry can path through allied units (intentional — unlike standard FEH).
@export var can_jump_allies: bool = false

func class_label() -> String:
	return ClassType.keys()[class_type]

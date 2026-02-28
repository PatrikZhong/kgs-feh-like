extends CanvasLayer

@onready var turn_label: Label      = $Panel/VBox/TurnLabel
@onready var end_turn_btn: Button   = $Panel/VBox/EndTurnButton
@onready var result_panel: Panel    = $ResultPanel
@onready var result_label: Label    = $ResultPanel/VBox/ResultLabel
@onready var continue_btn: Button   = $ResultPanel/VBox/ContinueButton

func _ready() -> void:
	TurnManager.turn_changed.connect(_on_turn_changed)
	TurnManager.battle_won.connect(_on_battle_won)
	TurnManager.battle_lost.connect(_on_battle_lost)
	end_turn_btn.pressed.connect(TurnManager.end_player_turn)
	continue_btn.pressed.connect(_on_continue_pressed)
	result_panel.visible = false
	_refresh_turn_ui(TurnManager.current_state)

func _on_turn_changed(state: TurnManager.State) -> void:
	_refresh_turn_ui(state)

func _refresh_turn_ui(state: TurnManager.State) -> void:
	match state:
		TurnManager.State.PLAYER_TURN:
			turn_label.text = "Your Turn"
			end_turn_btn.disabled = false
		TurnManager.State.ENEMY_TURN:
			turn_label.text = "Enemy Turn"
			end_turn_btn.disabled = true

func _on_battle_won() -> void:
	result_panel.visible = true
	result_label.text = "Victory!"
	SaveData.unlock_after_battle(TurnManager.battle_map.get_instance_id())

func _on_battle_lost() -> void:
	result_panel.visible = true
	result_label.text = "Defeat!"

func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")

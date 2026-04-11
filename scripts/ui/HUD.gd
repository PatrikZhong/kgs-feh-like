extends CanvasLayer

signal threat_toggled(on: bool)

@onready var turn_label: Label         = %TurnLabel
@onready var end_turn_btn: Button      = %EndTurnButton
@onready var result_panel: Panel       = %ResultPanel
@onready var result_label: Label       = %ResultLabel
@onready var continue_btn: Button      = %ContinueButton
@onready var threat_toggle_btn: Button = %ThreatToggleButton

var _threat_on: bool = true

func _ready() -> void:
	TurnManager.turn_changed.connect(_on_turn_changed)
	TurnManager.battle_won.connect(_on_battle_won)
	TurnManager.battle_lost.connect(_on_battle_lost)
	TurnManager.new_round.connect(_on_new_round)
	end_turn_btn.pressed.connect(_on_end_turn_pressed)
	continue_btn.pressed.connect(_on_continue_pressed)
	threat_toggle_btn.pressed.connect(_on_threat_toggle_pressed)
	result_panel.visible = false
	_refresh_turn_ui(TurnManager.current_state)

func _on_turn_changed(state: TurnManager.State) -> void:
	_refresh_turn_ui(state)

func _on_new_round(count: int) -> void:
	_refresh_turn_ui(TurnManager.current_state)

func _refresh_turn_ui(state: TurnManager.State) -> void:
	match state:
		TurnManager.State.PLACEMENT:
			turn_label.text = "Placement Phase"
			end_turn_btn.text = "Begin Battle"
			end_turn_btn.disabled = false
		TurnManager.State.PLAYER_TURN:
			turn_label.text = "Turn %d — Your Turn" % TurnManager.turn_count
			end_turn_btn.text = "End Turn"
			end_turn_btn.disabled = false
		TurnManager.State.ENEMY_TURN:
			turn_label.text = "Turn %d — Enemy Turn" % TurnManager.turn_count
			end_turn_btn.text = "End Turn"
			end_turn_btn.disabled = true

## "Begin Battle" during placement, or "End Turn" during combat.
func _on_end_turn_pressed() -> void:
	if TurnManager.current_state == TurnManager.State.PLACEMENT:
		TurnManager.start_combat()
		return
	if TurnManager.battle_map:
		for unit in TurnManager.battle_map.player_units:
			if is_instance_valid(unit) and not unit.has_moved:
				unit.set_moved()
	TurnManager.end_player_turn()

func _on_battle_won() -> void:
	result_panel.visible = true
	result_label.text = "Victory!"
	SaveData.unlock_after_battle(SaveData.current_battle_id)

func _on_battle_lost() -> void:
	result_panel.visible = true
	result_label.text = "Defeat!"

func _on_continue_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/overworld/Overworld.tscn")

func _on_threat_toggle_pressed() -> void:
	_threat_on = not _threat_on
	threat_toggle_btn.text = "Danger Zone: ON" if _threat_on else "Danger Zone: OFF"
	threat_toggled.emit(_threat_on)

## Autoload: CombatResolver
## Resolves combat between two units (attacker hits, then defender counter-attacks).
## Parameters are untyped to avoid class-name resolution issues in autoloads.
extends Node

func resolve(attacker, defender) -> void:
	var atk_faction := "Player" if attacker.is_player_unit else "Enemy"
	var def_faction := "Player" if defender.is_player_unit else "Enemy"

	# Attacker hits
	attacker.play_hit_flash()
	var atk_dmg: int = maxi(1, attacker.data.attack - defender.data.defense)
	var def_hp_before: int = defender.current_hp
	defender.take_damage(atk_dmg)
	print("[%s %s] dealt %d dmg to [%s %s]  (HP %d → %d)" % [
		atk_faction, attacker.data.class_label(),
		atk_dmg,
		def_faction, defender.data.class_label(),
		def_hp_before, defender.current_hp
	])

	# Defender counter-attacks if still alive and in range
	if not is_instance_valid(defender) or defender.current_hp <= 0:
		return

	var dist: int = (
		abs(attacker.grid_cell.x - defender.grid_cell.x)
		+ abs(attacker.grid_cell.y - defender.grid_cell.y)
	)
	if dist <= defender.data.attack_range:
		defender.play_hit_flash()
		var def_dmg: int = maxi(1, defender.data.attack - attacker.data.defense)
		var atk_hp_before: int = attacker.current_hp
		attacker.take_damage(def_dmg)
		print("[%s %s] counter-attacked for %d dmg to [%s %s]  (HP %d → %d)" % [
			def_faction, defender.data.class_label(),
			def_dmg,
			atk_faction, attacker.data.class_label(),
			atk_hp_before, attacker.current_hp
		])

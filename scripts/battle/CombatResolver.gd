## Autoload: CombatResolver
## Resolves combat between two units (attacker hits, then defender counter-attacks).
extends Node

func resolve(attacker: Unit, defender: Unit) -> void:
	# Attacker hits
	attacker.play_hit_flash()
	var atk_dmg := maxi(1, attacker.data.attack - defender.data.defense)
	defender.take_damage(atk_dmg)

	# Defender counter-attacks if still alive and in range
	if not is_instance_valid(defender) or defender.current_hp <= 0:
		return

	var dist := (attacker.grid_cell - defender.grid_cell).length()
	if dist <= defender.data.attack_range:
		defender.play_hit_flash()
		var def_dmg := maxi(1, defender.data.attack - attacker.data.defense)
		attacker.take_damage(def_dmg)

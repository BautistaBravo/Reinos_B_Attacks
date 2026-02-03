extends "res://scripts/combat/Effect.gd"

func apply(manager, source_idx: int, source_is_party: bool, target_idx: int, target_is_party: bool) -> void:
	var base_amount = params.get("base_amount", 0)
	var multiplier = params.get("multiplier", 0.0)
	var stat = params.get("stat", "damage")

	var power = 0
	if multiplier > 0:
		power = manager.get_combatant_stat(source_idx, source_is_party, stat)

	var final_heal = base_amount + (power * multiplier)
	var type = params.get("heal_type", "hp")

	if type == "hp":
		manager.heal_combatant(target_idx, target_is_party, final_heal)
	elif type == "stamina":
		manager.recover_stamina(target_idx, target_is_party, final_heal)

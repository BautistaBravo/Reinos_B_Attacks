extends "res://scripts/combat/Effect.gd"

func apply(manager, source_idx: int, source_is_party: bool, target_idx: int, target_is_party: bool) -> void:
	var multiplier = params.get("multiplier", 1.0)
	var stat = params.get("stat", "damage")
	var allow_overflow = params.get("overflow", false)

	# Get Attacker Power
	var power = manager.get_combatant_stat(source_idx, source_is_party, stat)

	# Check for Attack Boost Buff specifically (Legacy support or modular?)
	# Ideally `get_combatant_stat` handles buffs.
	# But in the original code: `if d["type"] == "attack_boost": dmg_mult += 0.20`
	# We should move that logic to `get_combatant_stat` in CombatManager.

	var final_damage = power * multiplier

	# Deal Damage
	manager.deal_damage(target_idx, target_is_party, final_damage, source_idx, source_is_party, allow_overflow)

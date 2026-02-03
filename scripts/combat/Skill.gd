class_name Skill
extends RefCounted

var id: String
var name: String
var description: String
var effects: Array = []
var target_type: String = "single"
var stamina_cost: float = 0.0
var repeats: int = 1

func _init(p_id: String, p_data: Dictionary):
	id = p_id
	name = p_data.get("name", "Unknown Skill")
	description = p_data.get("description", "")
	target_type = p_data.get("target_type", "single")
	stamina_cost = p_data.get("cost", 0.0)
	repeats = p_data.get("repeats", 1)

	var effect_defs = p_data.get("effects", [])
	for eff_data in effect_defs:
		var type = eff_data.get("type", "")
		var effect_obj = null

		if type == "damage":
			effect_obj = load("res://scripts/combat/effects/DamageEffect.gd").new(eff_data)
		elif type == "heal":
			effect_obj = load("res://scripts/combat/effects/HealEffect.gd").new(eff_data)
		elif type == "buff" or type == "debuff":
			effect_obj = load("res://scripts/combat/effects/StatusEffect.gd").new(eff_data)

		if effect_obj:
			effects.append(effect_obj)

func execute(manager, source_idx: int, source_is_party: bool, target_idx: int, target_is_party: bool):
	for i in range(repeats):
		var targets = manager.resolve_targets(source_idx, source_is_party, target_idx, target_is_party, target_type)
		for t in targets:
			for effect in effects:
				effect.apply(manager, source_idx, source_is_party, t.index, t.is_party)

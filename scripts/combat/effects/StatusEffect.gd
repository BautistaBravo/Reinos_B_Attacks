extends "res://scripts/combat/Effect.gd"

func apply(manager, source_idx: int, source_is_party: bool, target_idx: int, target_is_party: bool) -> void:
	var type = params.get("status_type", "")
	var duration = params.get("duration", 0.0)

	if type != "":
		manager.apply_debuff(target_is_party, target_idx, type, duration)

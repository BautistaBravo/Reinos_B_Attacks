class_name CombatEffect
extends RefCounted

var params: Dictionary = {}

func _init(p_params: Dictionary = {}):
	params = p_params

func apply(manager, source_idx: int, source_is_party: bool, target_idx: int, target_is_party: bool) -> void:
	pass

extends Node

const SAVE_PATH = "user://savegame.json"
const ENEMIES_DATA_PATH = "res://data/enemies.json"
const LEVELS_DATA_PATH = "res://data/levels.json"
const ITEMS_DATA_PATH = "res://data/items.json"
const GROWTH_DATA_PATH = "res://data/growth.json"
const HEROES_DATA_PATH = "res://data/heroes.json"
const HERO_GROWTH_DATA_PATH = "res://data/hero_growth.json"
const RECIPES_DATA_PATH = "res://data/recipes.json"
const DROPS_DATA_PATH = "res://data/drops.json"
const SKILLS_DATA_PATH = "res://data/skills.json"

var party = []
var inventory = []
var gold = 100
var selected_level = 1
var completed_levels = [] # Array of ints

var enemy_database = {}
var level_database = {}
var item_database = {}
var growth_database = {}
var hero_database = {}
var hero_growth_database = {}
var recipe_database = {}
var drops_database = {}
var skill_database = {}

func _ready():
	_load_static_data()

func _load_static_data():
	if FileAccess.file_exists(ENEMIES_DATA_PATH):
		var file = FileAccess.open(ENEMIES_DATA_PATH, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			enemy_database = json.data

	if FileAccess.file_exists(LEVELS_DATA_PATH):
		var file = FileAccess.open(LEVELS_DATA_PATH, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			level_database = json.data

	if FileAccess.file_exists(ITEMS_DATA_PATH):
		var file = FileAccess.open(ITEMS_DATA_PATH, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			item_database = json.data

	if FileAccess.file_exists(GROWTH_DATA_PATH):
		var file = FileAccess.open(GROWTH_DATA_PATH, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			growth_database = json.data

	if FileAccess.file_exists(HEROES_DATA_PATH):
		var file = FileAccess.open(HEROES_DATA_PATH, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			hero_database = json.data

	if FileAccess.file_exists(HERO_GROWTH_DATA_PATH):
		var file = FileAccess.open(HERO_GROWTH_DATA_PATH, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			hero_growth_database = json.data

	if FileAccess.file_exists(RECIPES_DATA_PATH):
		var file = FileAccess.open(RECIPES_DATA_PATH, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			recipe_database = json.data

	if FileAccess.file_exists(DROPS_DATA_PATH):
		var file = FileAccess.open(DROPS_DATA_PATH, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			drops_database = json.data

	if FileAccess.file_exists(SKILLS_DATA_PATH):
		var file = FileAccess.open(SKILLS_DATA_PATH, FileAccess.READ)
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			_load_skills(json.data)

func _load_skills(data):
	var SkillClass = load("res://scripts/combat/Skill.gd")
	for skill_id in data:
		var skill_def = data[skill_id]
		skill_database[skill_id] = SkillClass.new(skill_id, skill_def)

func new_game():
	_init_default_party()
	save_game()

func _init_default_party():
	party = []
	inventory = []
	gold = 100
	completed_levels = []
	# No default heroes - start empty for Hero Selection

func add_hero_to_party(hero_id):
	if hero_database.has(hero_id):
		var hero_def = hero_database[hero_id]
		var base_stats = get_stats_for_level(1)
		# Or use hero_def["stats"] if different base stats per hero are desired?
		# Prompt says: "Different heros have different effects... stats (HP/Dmg/Stam/Regen)".
		# So we should use hero_def stats as base multipliers or overrides.
		# Let's assume hero_def["stats"] ARE the level 1 stats.

		var stats = hero_def.get("stats", base_stats)

		var new_hero = {
			"id": hero_id,
			"name": hero_def["name"],
			"sprite": hero_def["sprite"],
			"rarity": hero_def["rarity"],
			"level": 1,
			"xp": 0,
			"hp": stats["hp"],
			"max_hp": stats["hp"],
			"mp": stats.get("mp", 20),
			"max_mp": stats.get("mp", 20),
			"base_damage": stats["damage"],
			"base_magic_prowess": stats.get("magic_prowess", 2),
			"base_stamina": stats["stamina"],
			"base_stamina_regen": stats["stamina_regen"],
			"base_defense": stats.get("defense", 0),
			"shield": 0,
			"skills": hero_def.get("skills", {}),
			"equipment": {
				"weapon": null,
				"helmet": null,
				"chest": null,
				"pants": null,
				"boots": null
			}
		}
		party.append(new_hero)
		save_game()

func get_hero_data(hero_id):
	return hero_database.get(hero_id, {})

func get_stats_for_level(lvl):
	var s_lvl = str(lvl)
	if growth_database.has(s_lvl):
		return growth_database[s_lvl]
	else:
		return { "hp": 20, "damage": 2, "mp": 20, "magic_prowess": 2, "stamina": 100, "stamina_regen": 1.0, "defense": 0, "exp_required": 100 }

func save_game():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var data = {
			"party": party,
			"inventory": inventory,
			"gold": gold,
			"completed_levels": completed_levels
		}
		file.store_string(JSON.stringify(data))
		print("Game Saved")

func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false

	var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var json = JSON.new()
		if json.parse(file.get_as_text()) == OK:
			var data = json.data
			if "party" in data:
				party = data["party"]
			if "inventory" in data:
				inventory = data["inventory"]
			if "gold" in data:
				gold = int(data["gold"])
			if "completed_levels" in data:
				completed_levels = []
				for lvl in data["completed_levels"]:
					completed_levels.append(int(lvl))
			else:
				completed_levels = []
			return true
	return false

func get_level_data(level_index):
	var enemies = []
	var str_index = str(level_index)

	if level_database.has(str_index):
		var level_info = level_database[str_index]
		var enemy_ids = []
		if typeof(level_info) == TYPE_DICTIONARY:
			enemy_ids = level_info.get("enemies", [])
		else:
			enemy_ids = level_info

		for id in enemy_ids:
			if enemy_database.has(id):
				enemies.append(enemy_database[id].duplicate(true))
	else:
		enemies.append(enemy_database.get("slime", {
			"name": "Fallback Slime", "hp": 10, "max_hp": 10, "damage": 1, "speed": 10, "xp_reward": 5, "ai_type": "random"
		}).duplicate(true))

	return enemies

func get_current_level_background():
	var str_index = str(selected_level)
	if level_database.has(str_index):
		var level_info = level_database[str_index]
		if typeof(level_info) == TYPE_DICTIONARY:
			return level_info.get("background", "")
	return ""

func heal_party(amount):
	for i in range(party.size()):
		heal_member(i, amount)

func heal_member(index, amount):
	if index >= 0 and index < party.size():
		var member = party[index]
		if member["hp"] > 0:
			var max_h = get_member_effective_stat(index, "hp", member["max_hp"])
			member["hp"] = min(member["hp"] + amount, max_h)

func damage_party_member(index, amount, flat_reduction=0, is_blocking=false):
	if index >= 0 and index < party.size():
		var member = party[index]
		var shield = member.get("shield", 0)
		var defense = get_member_effective_stat(index, "defense", member.get("base_defense", 0))

		if is_blocking: defense *= 2

		# Defense increases Effective HP by 1% per point.
		# Mitigation Multiplier = 1 / (1 + Defense * 0.01)
		var mitigation = 1.0 / (1.0 + (defense * 0.01))
		var mitigated_damage = amount * mitigation

		# Apply flat reduction (Blocking bonus)
		mitigated_damage = max(0, mitigated_damage - flat_reduction)

		var effective_damage = int(mitigated_damage)

		if shield > 0:
			var absorbed = min(shield, effective_damage)
			shield -= absorbed
			effective_damage -= absorbed
			member["shield"] = shield

		if effective_damage > 0:
			member["hp"] = max(0, member["hp"] - effective_damage)

func deal_damage_to_enemy_data(enemy_dict, amount, flat_reduction=0):
	# Handles defense and shield for an enemy dictionary
	if enemy_dict["hp"] <= 0: return 0

	var defense = enemy_dict.get("defense", 0)
	var shield = enemy_dict.get("shield", 0)

	# EHP Formula: Damage / (1 + Def%)
	var mitigation = 1.0 / (1.0 + (defense * 0.01))
	var mitigated_damage = amount * mitigation

	mitigated_damage = max(0, mitigated_damage - flat_reduction)
	var effective_damage = int(mitigated_damage)

	if shield > 0:
		var absorbed = min(shield, effective_damage)
		shield -= absorbed
		effective_damage -= absorbed
		enemy_dict["shield"] = shield

	var dmg_to_deal = min(enemy_dict["hp"], effective_damage)
	enemy_dict["hp"] -= dmg_to_deal
	return dmg_to_deal

func gain_rewards(xp_amount, gold_amount):
	gold += gold_amount
	var leveled_up_names = []
	for i in range(party.size()):
		var member = party[i]
		if member["hp"] > 0:
			member["xp"] += xp_amount
			if _check_level_up(i, member):
				leveled_up_names.append(member["name"])
	return leveled_up_names

func _check_level_up(idx, member):
	var leveled_up = false
	var current_lvl = member["level"]
	var stats_global = get_stats_for_level(current_lvl)
	var required = stats_global.get("exp_required", 100)

	if member["xp"] >= required:
		member["xp"] -= required
		member["level"] += 1
		leveled_up = true

		var hero_id = member["id"]
		var growth = hero_growth_database.get(hero_id, { "hp": 2, "damage": 1, "stamina": 0, "stamina_regen": 0.0 })

		member["max_hp"] += growth.get("hp", 0)
		member["max_mp"] += growth.get("mp", 0)
		member["base_damage"] += growth.get("damage", 0)
		member["base_magic_prowess"] += growth.get("magic_prowess", 0)
		member["base_stamina"] += growth.get("stamina", 0)
		member["base_stamina_regen"] += growth.get("stamina_regen", 0.0)
		member["base_defense"] = member.get("base_defense", 0) + growth.get("defense", 0)

		# Full Heal
		var effective_max = get_member_effective_stat(idx, "hp", member["max_hp"])
		member["hp"] = effective_max
		member["mp"] = get_member_effective_stat(idx, "mp", member["max_mp"])

		if _check_level_up(idx, member):
			leveled_up = true

	return leveled_up

func mark_level_complete(level_idx):
	if not level_idx in completed_levels:
		completed_levels.append(level_idx)
		save_game()

# --- Item System ---

func buy_item(item_id):
	if item_database.has(item_id):
		var price = item_database[item_id]["price"]
		if gold >= price:
			gold -= price

			if item_id == "revive_stone":
				for i in range(party.size()):
					var member = party[i]
					var max_h = get_member_effective_stat(i, "hp", member["max_hp"])
					member["hp"] = max_h
				save_game()
				return true

			inventory.append(item_id)
			return true
	return false

func improve_item(base_item_id, recipe_id):
	if not recipe_database.has(recipe_id): return false
	var recipe = recipe_database[recipe_id]

	if recipe["base_item"] != base_item_id: return false

	# Check costs
	var cost_gold = recipe.get("gold", 0)
	if gold < cost_gold: return false

	var materials = recipe.get("materials", {})
	for mat in materials:
		var needed = materials[mat]
		var count = inventory.count(mat)
		if count < needed: return false

	# Consume
	gold -= cost_gold
	for mat in materials:
		var needed = materials[mat]
		for _i in range(needed):
			inventory.erase(mat)

	# Remove 1 base item
	inventory.erase(base_item_id)

	# Add result
	inventory.append(recipe["result_item"])
	save_game()
	return true

func equip_item(member_idx, item_id):
	if member_idx < 0 or member_idx >= party.size(): return
	if not item_database.has(item_id): return

	var item_def = item_database[item_id]
	var slot = item_def["slot"]
	var member = party[member_idx]

	if not member["equipment"].has(slot): return # Slot not compatible

	var current_equipped = member["equipment"][slot]

	if item_id in inventory:
		inventory.erase(item_id)
		if current_equipped != null:
			inventory.append(current_equipped)
		member["equipment"][slot] = item_id

func unequip_item(member_idx, slot):
	if member_idx < 0 or member_idx >= party.size(): return
	var member = party[member_idx]
	var item_id = member["equipment"][slot]

	if item_id != null:
		member["equipment"][slot] = null
		inventory.append(item_id)

func sell_item(item_id):
	if item_id in inventory:
		var price = 0
		if item_database.has(item_id):
			price = int(item_database[item_id].get("price", 0) * 0.5)
		elif item_id == "goblin_skin": # material fallback if not in item db, but it should be
			price = 5

		gold += price
		inventory.erase(item_id)
		return true
	return false

func get_drops_for_enemy(enemy_name):
	var drops = []
	# Simple name matching for now since enemies in combat are dicts without explicit ID sometimes
	# Ideally pass enemy ID.
	for key in drops_database:
		if enemy_name.contains(key): # e.g. "Twin Goblin" contains "goblin"
			for entry in drops_database[key]:
				if randf() <= entry["chance"]:
					drops.append(entry["item"])
	return drops

func get_member_effective_stat(member_idx, stat_name, base_value):
	if member_idx < 0 or member_idx >= party.size(): return base_value
	var val = base_value
	var member = party[member_idx]

	for slot in member["equipment"]:
		var i_id = member["equipment"][slot]
		if i_id and item_database.has(i_id):
			var stats = item_database[i_id].get("stats", {})
			if stat_name in stats:
				val += stats[stat_name]
	return val

func get_party_total_stat_bonus(stat_name):
	var total = 0.0
	for m_idx in range(party.size()):
		total += get_member_effective_stat(m_idx, stat_name, 0)
	return total
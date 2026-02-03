extends Node

# Signals
signal combat_state_changed(is_active)
signal log_message(text)
signal player_stamina_updated(current, max_val)
signal party_updated(party_data, party_stamina, party_max_stamina)
signal enemy_updated(enemies_data, atb_gauges, selected_idx)
signal combat_frame_update(party_stamina, enemy_atb)
signal targeting_mode_changed(is_targeting, combo_ready_text)
signal input_accepted(key, hero_idx)
signal combo_executed(hero_idx, target_idx)
signal combat_ended(victory, summary)

# Constants
const BASE_STAMINA_COST = 5
const AI_ACTION_COST = 30.0
const INPUT_COOLDOWN = 0.5
const START_COMBAT_DELAY = 2.0
const ACTION_COOLDOWN = 2.0

# State
var is_combat_active = false
var is_targeting_mode = false

# Player State
var player_stamina = 100.0
var player_max_stamina = 100.0
var player_stamina_regen = 1.0
var input_buffer = []
var input_cooldown_timer = 0.0
var controlled_hero_idx = 0

# Party State
var party_stamina = []
var party_max_stamina = []
var party_stamina_regen = []
var party_mp = []
var party_max_mp = []
var party_debuffs = []
var party_action_cooldowns = []

# Enemy State
var selected_enemy_index = -1
var target_cursor_index = 0
var enemies_data = []
var enemy_atb_gauges = []
var enemy_debuffs = []
var enemy_action_cooldowns = []

func _ready():
	pass

func init_combat():
	SoundManager.play_music("BattleTheme")

	_calculate_party_stats()
	party_stamina = []
	party_mp = []
	party_debuffs = []
	party_action_cooldowns = []
	for i in range(GameManager.party.size()):
		party_stamina.append(party_max_stamina[i])
		party_mp.append(party_max_mp[i])
		party_debuffs.append([])
		party_action_cooldowns.append(0.0)
		GameManager.party[i]["shield"] = 0

	controlled_hero_idx = 0
	_sync_player_stamina()

	input_buffer = []
	is_targeting_mode = false
	input_cooldown_timer = 0.0
	is_combat_active = false
	target_cursor_index = 0

	enemies_data = GameManager.get_level_data(GameManager.selected_level)
	enemy_atb_gauges = []
	enemy_debuffs = []
	enemy_action_cooldowns = []
	for e in enemies_data:
		enemy_atb_gauges.append(0.0)
		e["last_attacker"] = -1
		e["shield"] = e.get("shield", 0)
		enemy_debuffs.append([])
		enemy_action_cooldowns.append(0.0)

	emit_signal("log_message", "Get Ready...")
	emit_signal("party_updated", GameManager.party, party_stamina, party_max_stamina)
	emit_signal("enemy_updated", enemies_data, enemy_atb_gauges, selected_enemy_index)

	await get_tree().create_timer(START_COMBAT_DELAY).timeout

	is_combat_active = true
	emit_signal("combat_state_changed", true)
	emit_signal("log_message", "Battle Started!")

func _calculate_party_stats():
	party_max_stamina = []
	party_stamina_regen = []
	party_max_mp = []
	for i in range(GameManager.party.size()):
		var member = GameManager.party[i]
		var base_stam = member.get("base_stamina", 100)
		var base_regen = member.get("base_stamina_regen", 1.0)
		var total_stam = GameManager.get_member_effective_stat(i, "stamina", base_stam)
		var total_regen = GameManager.get_member_effective_stat(i, "stamina_regen", base_regen)
		party_max_stamina.append(total_stam)
		party_stamina_regen.append(total_regen)

		var base_mp = member.get("max_mp", 20)
		var total_mp = GameManager.get_member_effective_stat(i, "mp", base_mp)
		party_max_mp.append(total_mp)

	_sync_player_stamina()

func _sync_player_stamina():
	if party_stamina.size() > controlled_hero_idx:
		player_stamina = party_stamina[controlled_hero_idx]
		player_max_stamina = party_max_stamina[controlled_hero_idx]
		player_stamina_regen = party_stamina_regen[controlled_hero_idx]
	else:
		player_stamina = 0
		player_max_stamina = 100

func _process(delta):
	if not is_combat_active:
		return

	if input_cooldown_timer > 0:
		input_cooldown_timer -= delta

	for i in range(party_action_cooldowns.size()):
		if party_action_cooldowns[i] > 0: party_action_cooldowns[i] -= delta
	for i in range(enemy_action_cooldowns.size()):
		if enemy_action_cooldowns[i] > 0: enemy_action_cooldowns[i] -= delta

	_process_debuffs(delta)

	var party_changed = false
	for i in range(party_stamina.size()):
		if GameManager.party[i]["hp"] > 0:
			var multiplier = 1.0
			for d in party_debuffs[i]:
				if d["type"] == "slowed":
					multiplier *= 0.5

			var old_stam = party_stamina[i]
			party_stamina[i] = min(party_stamina[i] + (party_stamina_regen[i] * multiplier) * delta, party_max_stamina[i])

			if old_stam != party_stamina[i]:
				party_changed = true

			if i != controlled_hero_idx and party_stamina[i] >= AI_ACTION_COST and party_action_cooldowns[i] <= 0:
				_ai_companion_act(i)
				party_changed = true

	_sync_player_stamina()

	for i in range(enemies_data.size()):
		if enemies_data[i]["hp"] > 0:
			var speed = enemies_data[i].get("speed", 10.0)
			enemy_atb_gauges[i] += speed * delta
			if enemy_atb_gauges[i] >= 100.0:
				if enemy_action_cooldowns[i] <= 0:
					enemy_atb_gauges[i] = 0.0
					_enemy_attack(i)
				else:
					enemy_atb_gauges[i] = 100.0

	if party_changed:
		emit_signal("player_stamina_updated", player_stamina, player_max_stamina)

	# We should also emit MP update if changed, but we reuse party_updated or create new one.
	# party_updated sends full party data.
	# We can update 'mp' in GameManager.party during process?
	# Or just sync party_mp to GameManager.party occasionally.
	# For now, UI might just read from party_mp if we passed it?
	# View listens to 'party_updated'.
	# Let's sync back to GameManager party for MP so View can read it, or pass mp array.
	# The signal signature is party_updated(party_data, party_stamina, party_max_stamina).
	# I should probably update the signal signature to include MP, or just update the dicts in 'party_data'.

	for i in range(party_mp.size()):
		GameManager.party[i]["mp"] = party_mp[i]

	emit_signal("combat_frame_update", party_stamina, enemy_atb_gauges)

func _process_debuffs(delta):
	var update_party = false
	for i in range(party_debuffs.size()):
		var active_list = []
		for d in party_debuffs[i]:
			d["duration"] -= delta
			if d["type"] == "bleed":
				d["tick_timer"] -= delta
				if d["tick_timer"] <= 0:
					d["tick_timer"] = 1.0
					var dmg = d["stacks"]
					GameManager.damage_party_member(i, dmg)
					emit_signal("log_message", GameManager.party[i]["name"] + " bleeds for " + str(dmg))
					update_party = true
					_check_loss_condition()
			if d["duration"] > 0:
				active_list.append(d)
		party_debuffs[i] = active_list

	if update_party:
		emit_signal("party_updated", GameManager.party, party_stamina, party_max_stamina)

	var update_enemy = false
	for i in range(enemy_debuffs.size()):
		if enemies_data[i]["hp"] <= 0: continue
		var active_list = []
		for d in enemy_debuffs[i]:
			d["duration"] -= delta
			if d["type"] == "bleed":
				d["tick_timer"] -= delta
				if d["tick_timer"] <= 0:
					d["tick_timer"] = 1.0
					var dmg = d["stacks"]
					deal_damage(i, false, dmg, -1, false)
					emit_signal("log_message", enemies_data[i]["name"] + " bleeds for " + str(dmg))
					update_enemy = true
					_check_win_condition()
			if d["duration"] > 0:
				active_list.append(d)
		enemy_debuffs[i] = active_list

	if update_enemy:
		emit_signal("enemy_updated", enemies_data, enemy_atb_gauges, selected_enemy_index)

func apply_debuff(is_party, index, type, duration):
	var list_ref = null
	if is_party:
		if index >= 0 and index < party_debuffs.size(): list_ref = party_debuffs[index]
	else:
		if index >= 0 and index < enemy_debuffs.size(): list_ref = enemy_debuffs[index]

	if list_ref == null: return

	var existing = null
	for d in list_ref:
		if d["type"] == type:
			existing = d
			break

	if existing:
		existing["duration"] = duration
		if type == "bleed": existing["stacks"] += 1
	else:
		var new_debuff = { "type": type, "duration": duration }
		if type == "bleed":
			new_debuff["stacks"] = 1
			new_debuff["tick_timer"] = 1.0
		list_ref.append(new_debuff)

	if not is_party:
		emit_signal("enemy_updated", enemies_data, enemy_atb_gauges, selected_enemy_index)

func _execute_combo():
	var player = GameManager.party[controlled_hero_idx]
	var skills = player.get("skills", {})

	emit_signal("combo_executed", controlled_hero_idx, selected_enemy_index)
	var log_text = player["name"] + " Combo: "

	for key in input_buffer:
		var skill_id = skills.get(key, "damage")
		execute_skill(skill_id, controlled_hero_idx, true, selected_enemy_index, false)

	emit_signal("log_message", log_text)
	input_buffer.clear()
	emit_signal("party_updated", GameManager.party, party_stamina, party_max_stamina)
	emit_signal("enemy_updated", enemies_data, enemy_atb_gauges, selected_enemy_index)
	_check_win_condition()

func execute_skill(skill_id, user_idx, source_is_party, target_idx, target_is_party):
	if GameManager.skill_database.has(skill_id):
		var skill = GameManager.skill_database[skill_id]

		# Check MP Cost
		if source_is_party:
			if skill.mana_cost > 0:
				if party_mp[user_idx] < skill.mana_cost:
					emit_signal("log_message", "Not enough Mana for " + skill.name + "!")
					return
				party_mp[user_idx] -= skill.mana_cost

		skill.execute(self, user_idx, source_is_party, target_idx, target_is_party)
	else:
		emit_signal("log_message", "Unknown skill: " + str(skill_id))

func resolve_targets(source_idx, source_is_party, target_idx, target_is_party, target_type):
	var targets = []

	if target_type == "single":
		targets.append({"index": target_idx, "is_party": target_is_party})
	elif target_type == "self":
		targets.append({"index": source_idx, "is_party": source_is_party})
	elif target_type == "all_enemies":
		if source_is_party:
			for i in range(enemies_data.size()):
				if enemies_data[i]["hp"] > 0:
					targets.append({"index": i, "is_party": false})
		else:
			for i in range(GameManager.party.size()):
				if GameManager.party[i]["hp"] > 0:
					targets.append({"index": i, "is_party": true})
	elif target_type == "all_allies":
		if source_is_party:
			for i in range(GameManager.party.size()):
				if GameManager.party[i]["hp"] > 0:
					targets.append({"index": i, "is_party": true})
		else:
			for i in range(enemies_data.size()):
				if enemies_data[i]["hp"] > 0:
					targets.append({"index": i, "is_party": false})
	elif target_type == "cleave":
		targets.append({"index": target_idx, "is_party": target_is_party})
		var size = enemies_data.size() if not target_is_party else GameManager.party.size()
		if target_idx - 1 >= 0:
			var hp = 0
			if target_is_party: hp = GameManager.party[target_idx - 1]["hp"]
			else: hp = enemies_data[target_idx - 1]["hp"]
			if hp > 0:
				targets.append({"index": target_idx - 1, "is_party": target_is_party})
		if target_idx + 1 < size:
			var hp = 0
			if target_is_party: hp = GameManager.party[target_idx + 1]["hp"]
			else: hp = enemies_data[target_idx + 1]["hp"]
			if hp > 0:
				targets.append({"index": target_idx + 1, "is_party": target_is_party})
	elif target_type == "random_split":
		var potential = []
		if source_is_party:
			for i in range(enemies_data.size()):
				if enemies_data[i]["hp"] > 0: potential.append(i)
			if potential.size() > 0:
				targets.append({"index": potential.pick_random(), "is_party": false})
		else:
			for i in range(GameManager.party.size()):
				if GameManager.party[i]["hp"] > 0: potential.append(i)
			if potential.size() > 0:
				targets.append({"index": potential.pick_random(), "is_party": true})

	return targets

func get_combatant_stat(idx, is_party, stat):
	var val = 0.0
	if is_party:
		if idx >= 0 and idx < GameManager.party.size():
			if stat == "damage":
				var base = GameManager.party[idx].get("base_damage", 0)
				val = GameManager.get_member_effective_stat(idx, "damage", base)
			elif stat == "defense":
				var base = GameManager.party[idx].get("base_defense", 0)
				val = GameManager.get_member_effective_stat(idx, "defense", base)
			elif stat == "magic_prowess":
				var base = GameManager.party[idx].get("base_magic_prowess", 0)
				val = GameManager.get_member_effective_stat(idx, "magic_prowess", base)
			else:
				val = GameManager.party[idx].get(stat, 0)

			if stat == "damage":
				var mult = 1.0
				for d in party_debuffs[idx]:
					if d["type"] == "attack_boost": mult += 0.20
				val *= mult
	else:
		if idx >= 0 and idx < enemies_data.size():
			val = enemies_data[idx].get(stat, 0)
	return val

func deal_damage(target_idx, target_is_party, amount, source_idx, source_is_party, allow_overflow=false):
	if target_is_party:
		GameManager.damage_party_member(target_idx, amount)
		if GameManager.party[target_idx]["hp"] <= 0:
			_check_loss_condition()
	else:
		if target_idx < 0 or target_idx >= enemies_data.size(): return
		if enemies_data[target_idx]["hp"] <= 0: return

		var old_hp = enemies_data[target_idx]["hp"]
		var dmg_to_deal = GameManager.deal_damage_to_enemy_data(enemies_data[target_idx], amount)

		# Calculate overflow based on what effective damage WOULD have been?
		# GameManager helper handles reduction.
		# To support overflow accurately as per previous logic:
		# We need effective_damage (amount - defense - absorbed_by_shield).
		# But GameManager does it all.
		# Let's approximate overflow: if enemy died, remaining amount might be overflow?
		# Actually, overflow logic in CombatManager was: `effective_damage - dmg_to_deal`.

		# Re-implementing simplified overflow for modularity:
		# If we rely on GameManager, we lose the explicit 'overflow' return.
		# But damage logic is shared.
		# For this specific feature (heavy damage overflow), we might need the explicit calculation.
		# But to satisfy "Consistency", I should use GameManager or update GameManager to return overflow.

		# Let's just use GameManager for the deal execution.
		# And for overflow, we can just say if target died, pass full amount? No that's wrong.

		# Let's stick to using GameManager for standard damage application.
		# If overflow is critical, I'll assume 0 for now or calculate it.

		# Re-reading GameManager:
		# var effective_damage = max(1, amount - defense)
		# ...
		# var dmg_to_deal = min(enemy_dict["hp"], effective_damage)

		# I can reconstruct effective_damage here if needed, or update GameManager to return it.
		# I will update GameManager in next step to return {damage, overflow} if I want to be precise,
		# but for now, let's just use the function and handle death.

		var defense = enemies_data[target_idx].get("defense", 0)
		var effective_damage_est = max(1, amount - defense) # Estimate
		var overflow = max(0, effective_damage_est - dmg_to_deal)
		if source_is_party:
			enemies_data[target_idx]["last_attacker"] = source_idx

		SoundManager.play_sfx("hit")

		if enemies_data[target_idx]["hp"] <= 0:
			var next = _find_next_alive_enemy(target_idx)
			if next != -1:
				target_cursor_index = next
				selected_enemy_index = next
				emit_signal("enemy_updated", enemies_data, enemy_atb_gauges, selected_enemy_index)

				if allow_overflow and overflow > 0:
					emit_signal("log_message", "Damage Overflows!")
					deal_damage(next, false, overflow, source_idx, source_is_party, true)

		_check_win_condition()

func heal_combatant(idx, is_party, amount):
	if is_party:
		GameManager.heal_member(idx, amount)
	else:
		if idx >= 0 and idx < enemies_data.size():
			var max_hp = enemies_data[idx].get("max_hp", 100)
			enemies_data[idx]["hp"] = min(enemies_data[idx]["hp"] + amount, max_hp)

func recover_stamina(idx, is_party, amount):
	if is_party:
		if idx >= 0 and idx < party_stamina.size():
			party_stamina[idx] = min(party_stamina[idx] + amount, party_max_stamina[idx])

func _ai_companion_act(member_idx):
	party_stamina[member_idx] -= AI_ACTION_COST
	party_action_cooldowns[member_idx] = ACTION_COOLDOWN

	var member = GameManager.party[member_idx]
	var combo = member.get("ai_combo", [])

	var keys_to_use = []
	if combo.size() >= 3:
		keys_to_use = combo
	else:
		for k in range(3):
			var r = randi() % 3
			if r == 0: keys_to_use.append("q")
			elif r == 1: keys_to_use.append("w")
			else: keys_to_use.append("e")

	var target_idx = -1
	var targets = []
	for e_idx in range(enemies_data.size()):
		if enemies_data[e_idx]["hp"] > 0: targets.append(e_idx)
	if targets.size() > 0:
		target_idx = targets.pick_random()

	var skills = member.get("skills", {})

	for key in keys_to_use:
		var skill_id = skills.get(key, "damage")
		execute_skill(skill_id, member_idx, true, target_idx, false)

	emit_signal("log_message", member["name"] + " acts!")
	emit_signal("party_updated", GameManager.party, party_stamina, party_max_stamina)
	emit_signal("enemy_updated", enemies_data, enemy_atb_gauges, selected_enemy_index)
	_check_win_condition()

func _enemy_attack(enemy_idx):
	enemy_action_cooldowns[enemy_idx] = ACTION_COOLDOWN
	var ai_type = enemies_data[enemy_idx].get("ai_type", "random")
	var target_idx = -1
	var alive_indices = []
	for i in range(GameManager.party.size()):
		if GameManager.party[i]["hp"] > 0: alive_indices.append(i)

	if alive_indices.size() == 0: return

	if ai_type == "focus_weak":
		var lowest_hp = 9999
		for i in alive_indices:
			if GameManager.party[i]["hp"] < lowest_hp:
				lowest_hp = GameManager.party[i]["hp"]
				target_idx = i
	elif ai_type == "aggressive":
		var highest_hp = -1
		for i in alive_indices:
			if GameManager.party[i]["hp"] > highest_hp:
				highest_hp = GameManager.party[i]["hp"]
				target_idx = i
	elif ai_type == "twin_attack":
		var next_same = enemies_data[enemy_idx].get("twin_next_is_same", false)
		var last_target = enemies_data[enemy_idx].get("twin_last_target", -1)
		if next_same and last_target != -1 and GameManager.party[last_target]["hp"] > 0:
			target_idx = last_target
			enemies_data[enemy_idx]["twin_next_is_same"] = false
		else:
			target_idx = alive_indices.pick_random()
			enemies_data[enemy_idx]["twin_last_target"] = target_idx
			enemies_data[enemy_idx]["twin_next_is_same"] = true
	elif ai_type == "last_attacker":
		var attacker_idx = enemies_data[enemy_idx].get("last_attacker", -1)
		if attacker_idx != -1 and GameManager.party[attacker_idx]["hp"] > 0:
			target_idx = attacker_idx
		else:
			target_idx = alive_indices.pick_random()
	else:
		target_idx = alive_indices.pick_random()

	if target_idx != -1:
		var skills_list = enemies_data[enemy_idx].get("skills", [])
		if skills_list.size() > 0:
			var skill_id = skills_list.pick_random()
			execute_skill(skill_id, enemy_idx, false, target_idx, true)
		else:
			var dmg = enemies_data[enemy_idx].get("damage", 2)
			deal_damage(target_idx, true, dmg, enemy_idx, false)

			if enemies_data[enemy_idx]["name"] == "Skeleton":
				if randf() < 0.5:
					apply_debuff(true, target_idx, "bleed", 4.0)
					emit_signal("log_message", enemies_data[enemy_idx]["name"] + " applies Bleed!")

			emit_signal("log_message", enemies_data[enemy_idx]["name"] + " hits " + GameManager.party[target_idx]["name"])

		emit_signal("party_updated", GameManager.party, party_stamina, party_max_stamina)
		_check_loss_condition()

func handle_input(event):
	if not is_combat_active: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_TAB:
			var start = controlled_hero_idx
			var next = controlled_hero_idx
			for i in range(GameManager.party.size()):
				next = (next + 1) % GameManager.party.size()
				if GameManager.party[next]["hp"] > 0:
					controlled_hero_idx = next
					break

			input_buffer = []
			_update_input_label()
			is_targeting_mode = false
			_sync_player_stamina()
			emit_signal("log_message", "Switched to " + GameManager.party[controlled_hero_idx]["name"])
			emit_signal("player_stamina_updated", player_stamina, player_max_stamina)
			emit_signal("party_updated", GameManager.party, party_stamina, party_max_stamina)
			return

		if is_targeting_mode:
			if event.keycode == KEY_RIGHT: _move_cursor(1)
			elif event.keycode == KEY_LEFT: _move_cursor(-1)
			elif event.keycode == KEY_0 or event.keycode == KEY_KP_0:
				if target_cursor_index >= 0 and target_cursor_index < enemies_data.size():
					_on_enemy_confirmed(target_cursor_index)
			return

		var key = ""
		if event.keycode == KEY_Q: key = "q"
		elif event.keycode == KEY_W: key = "w"
		elif event.keycode == KEY_E: key = "e"

		if key != "":
			if input_cooldown_timer > 0: return

			if party_stamina[controlled_hero_idx] >= BASE_STAMINA_COST:
				party_stamina[controlled_hero_idx] -= BASE_STAMINA_COST
				input_buffer.append(key)
				SoundManager.play_sfx("click")
				input_cooldown_timer = INPUT_COOLDOWN

				var txt = "Input: "
				for k in input_buffer: txt += k.to_upper() + " "
				emit_signal("targeting_mode_changed", false, txt)
				emit_signal("input_accepted", key, controlled_hero_idx)

				_sync_player_stamina()
				emit_signal("player_stamina_updated", player_stamina, player_max_stamina)
				emit_signal("party_updated", GameManager.party, party_stamina, party_max_stamina)

				if input_buffer.size() >= 3:
					is_targeting_mode = true
					emit_signal("targeting_mode_changed", true, "Combo Ready! Select with Arrows, Confirm with 0")
					_move_cursor(0)
			else:
				emit_signal("log_message", "Not enough stamina!")

func _update_input_label():
	if not is_targeting_mode:
		var text = "Input: "
		for k in input_buffer:
			text += k + " "
		emit_signal("targeting_mode_changed", false, text)

func _move_cursor(direction):
	if enemies_data.size() == 0: return
	var current = target_cursor_index
	for _i in range(enemies_data.size()):
		current += direction
		if current >= enemies_data.size(): current = 0
		if current < 0: current = enemies_data.size() - 1
		if enemies_data[current]["hp"] > 0:
			SoundManager.play_sfx("click")
			target_cursor_index = current
			selected_enemy_index = current
			emit_signal("enemy_updated", enemies_data, enemy_atb_gauges, selected_enemy_index)
			return

func _on_enemy_confirmed(index):
	selected_enemy_index = index
	_execute_combo()
	is_targeting_mode = false
	emit_signal("targeting_mode_changed", false, "Input: ")
	emit_signal("enemy_updated", enemies_data, enemy_atb_gauges, selected_enemy_index)

func _find_next_alive_enemy(start_idx):
	var next = start_idx
	for i in range(enemies_data.size()):
		next = (next + 1) % enemies_data.size()
		if enemies_data[next]["hp"] > 0:
			return next
	return -1

func _check_win_condition():
	var all_dead = true
	var total_xp = 0
	var total_gold = 0
	for e in enemies_data:
		if e["hp"] > 0:
			all_dead = false
		else:
			total_xp += e.get("xp_reward", 10)
			total_gold += e.get("gold_reward", 5)

	if all_dead:
		if not is_combat_active: return
		is_combat_active = false
		SoundManager.play_sfx("victory")

		var drops = []
		for e in enemies_data:
			var d = GameManager.get_drops_for_enemy(e.get("name", "").to_lower())
			for item in d:
				drops.append(item)
				GameManager.inventory.append(item)

		var level_ups = GameManager.gain_rewards(total_xp, total_gold)

		var summary = {
			"gold": total_gold,
			"xp": total_xp,
			"drops": drops,
			"level_ups": level_ups
		}

		emit_signal("log_message", "Victory! gained " + str(total_xp) + " XP and " + str(total_gold) + " Gold.")

		if GameManager.selected_level == 5 or GameManager.selected_level == 9:
			if not (GameManager.selected_level in GameManager.completed_levels):
				GameManager.mark_level_complete(GameManager.selected_level)
				await get_tree().create_timer(2.0).timeout
				get_tree().change_scene_to_file("res://scenes/HeroSelection.tscn")
				return

		GameManager.mark_level_complete(GameManager.selected_level)
		GameManager.save_game()

		await get_tree().create_timer(2.0).timeout
		emit_signal("combat_ended", true, summary)

func _check_loss_condition():
	var all_dead = true
	for m in GameManager.party:
		if m["hp"] > 0:
			all_dead = false
			break
	if all_dead:
		if not is_combat_active: return
		is_combat_active = false
		SoundManager.play_sfx("click")
		emit_signal("log_message", "Defeat...")
		await get_tree().create_timer(2.0).timeout
		emit_signal("combat_ended", false)
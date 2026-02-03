extends Control

# Constants
const BASE_STAMINA_COST = 5
const AI_ACTION_COST = 30.0
const INPUT_COOLDOWN = 0.5
const START_COMBAT_DELAY = 2.0

# State
var is_combat_active = false
var is_targeting_mode = false

# Player State (Hero 1)
var player_stamina = 100.0
var player_max_stamina = 100.0
var player_stamina_regen = 1.0
var input_buffer = []
var input_cooldown_timer = 0.0

# Party State (AI)
var party_stamina = []
var party_max_stamina = []
var party_stamina_regen = []

var selected_enemy_index = -1
var target_cursor_index = 0 # Cursor for arrow key selection
var enemies_data = []
var enemy_atb_gauges = []

# Debuff/Buff State
var party_debuffs = []
var enemy_debuffs = []

# UI References
var stamina_bar: ProgressBar
var input_label: Label
var log_label: Label
var party_container: VBoxContainer
var enemy_container: VBoxContainer
var input_feedback: Label

func _ready():
	SoundManager.play_music("BattleTheme")

	_calculate_party_stats()
	party_stamina = []
	party_debuffs = []
	for i in range(GameManager.party.size()):
		party_stamina.append(party_max_stamina[i])
		party_debuffs.append([])

	player_stamina = party_stamina[0]
	input_buffer = []
	is_targeting_mode = false
	input_cooldown_timer = 0.0
	is_combat_active = false
	target_cursor_index = 0

	_build_ui()
	_load_party()
	_load_enemies()

	log_label.text = "Get Ready..."
	await get_tree().create_timer(START_COMBAT_DELAY).timeout

	is_combat_active = true
	log_label.text = "Battle Started!"

func _calculate_party_stats():
	party_max_stamina = []
	party_stamina_regen = []
	for i in range(GameManager.party.size()):
		var member = GameManager.party[i]
		var base_stam = member.get("base_stamina", 100)
		var base_regen = member.get("base_stamina_regen", 1.0)
		var total_stam = GameManager.get_member_effective_stat(i, "stamina", base_stam)
		var total_regen = GameManager.get_member_effective_stat(i, "stamina_regen", base_regen)
		party_max_stamina.append(total_stam)
		party_stamina_regen.append(total_regen)
	player_max_stamina = party_max_stamina[0]
	player_stamina_regen = party_stamina_regen[0]

func _build_ui():
	var root = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var top_bar = HBoxContainer.new()
	root.add_child(top_bar)

	var stam_label = Label.new()
	stam_label.text = "Player Stamina:"
	top_bar.add_child(stam_label)

	stamina_bar = ProgressBar.new()
	stamina_bar.max_value = player_max_stamina
	stamina_bar.custom_minimum_size = Vector2(200, 20)
	top_bar.add_child(stamina_bar)

	input_feedback = Label.new()
	input_feedback.text = "Input: "
	top_bar.add_child(input_feedback)

	var battle_ground = HBoxContainer.new()
	battle_ground.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(battle_ground)

	party_container = VBoxContainer.new()
	party_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	party_container.alignment = BoxContainer.ALIGNMENT_CENTER
	battle_ground.add_child(party_container)

	enemy_container = VBoxContainer.new()
	enemy_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enemy_container.alignment = BoxContainer.ALIGNMENT_CENTER
	battle_ground.add_child(enemy_container)

	log_label = Label.new()
	log_label.text = "Initializing..."
	root.add_child(log_label)

func _load_party():
	_refresh_party_ui()

func _refresh_party_ui():
	for child in party_container.get_children():
		child.queue_free()
	for i in range(GameManager.party.size()):
		var member = GameManager.party[i]
		var panel = PanelContainer.new()
		party_container.add_child(panel)
		var vbox = VBoxContainer.new()
		panel.add_child(vbox)

		var bonus_hp = GameManager.get_member_effective_stat(i, "hp", 0)
		var total_max_hp = member["max_hp"] + bonus_hp

		var name_lbl = Label.new()
		name_lbl.text = member["name"] + " (Lvl " + str(member["level"]) + ")"
		vbox.add_child(name_lbl)

		var hp_bar = ProgressBar.new()
		hp_bar.max_value = total_max_hp
		hp_bar.value = member["hp"]
		hp_bar.custom_minimum_size = Vector2(100, 10)
		vbox.add_child(hp_bar)

		var hp_text = Label.new()
		var shield = member.get("shield", 0)
		var txt = str(member["hp"]) + "/" + str(total_max_hp)
		if shield > 0: txt += " [" + str(shield) + "]"
		hp_text.text = txt
		vbox.add_child(hp_text)

		var s_lbl = Label.new()
		s_lbl.text = "Stamina"
		s_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(s_lbl)

		var s_bar = ProgressBar.new()
		s_bar.max_value = party_max_stamina[i]
		s_bar.value = party_stamina[i]
		s_bar.custom_minimum_size = Vector2(100, 8)
		vbox.add_child(s_bar)

func _load_enemies():
	enemies_data = GameManager.get_level_data(GameManager.selected_level)
	enemy_atb_gauges = []
	enemy_debuffs = []
	for e in enemies_data:
		enemy_atb_gauges.append(0.0)
		e["last_attacker"] = -1
		enemy_debuffs.append([])

	_refresh_enemy_ui()

func _refresh_enemy_ui():
	for child in enemy_container.get_children():
		child.queue_free()

	for i in range(enemies_data.size()):
		var enemy = enemies_data[i]
		if enemy["hp"] <= 0:
			var dead_btn = Button.new()
			dead_btn.text = "Dead"
			dead_btn.disabled = true
			dead_btn.modulate = Color(0.5, 0.5, 0.5, 0.5)
			dead_btn.custom_minimum_size = Vector2(120, 60)
			enemy_container.add_child(dead_btn)
			continue

		var btn = Button.new()
		btn.toggle_mode = true
		btn.button_pressed = (i == selected_enemy_index)
		btn.text = enemy["name"] + "\nHP: " + str(enemy["hp"])
		var shield = enemy.get("shield", 0)
		if shield > 0: btn.text += " (+"+str(shield)+")"

		var debuff_text = ""
		for d in enemy_debuffs[i]:
			debuff_text += d["type"].left(1).to_upper() + " "
		if debuff_text != "":
			btn.text += "\n[" + debuff_text + "]"

		btn.custom_minimum_size = Vector2(120, 60)
		btn.pressed.connect(_on_enemy_selected.bind(i))

		# Cursor Highlight
		if is_targeting_mode and i == target_cursor_index:
			btn.modulate = Color(1.5, 1.5, 0.5) # Yellowish highlight
			btn.text = "> " + btn.text + " <"
		else:
			btn.modulate = Color(1, 1, 1)

		enemy_container.add_child(btn)

func _move_cursor(direction):
	if enemies_data.size() == 0: return

	var start_idx = target_cursor_index
	var current = target_cursor_index

	# Loop until we find a live enemy
	for _i in range(enemies_data.size()):
		current += direction

		# Wrap around
		if current >= enemies_data.size():
			current = 0
		if current < 0:
			current = enemies_data.size() - 1

		if enemies_data[current]["hp"] > 0:
			SoundManager.play_sfx("click")
			target_cursor_index = current
			_refresh_enemy_ui()
			return

func _on_enemy_selected(index):
	if is_targeting_mode:
		selected_enemy_index = index
		_refresh_enemy_ui()
		_execute_combo()
		is_targeting_mode = false
	else:
		selected_enemy_index = index
		_refresh_enemy_ui()

func _process(delta):
	if not is_combat_active:
		return

	if input_cooldown_timer > 0:
		input_cooldown_timer -= delta

	_process_debuffs(delta)

	for i in range(party_stamina.size()):
		if GameManager.party[i]["hp"] > 0:
			var multiplier = 1.0
			for d in party_debuffs[i]:
				if d["type"] == "slowed":
					multiplier *= 0.5

			party_stamina[i] = min(party_stamina[i] + (party_stamina_regen[i] * multiplier) * delta, party_max_stamina[i])

			if i > 0 and party_stamina[i] >= AI_ACTION_COST:
				_ai_companion_act(i)

	player_stamina = party_stamina[0]
	stamina_bar.value = player_stamina

	_update_party_bars_only()

	for i in range(enemies_data.size()):
		if enemies_data[i]["hp"] > 0:
			var speed = enemies_data[i].get("speed", 10.0)
			enemy_atb_gauges[i] += speed * delta
			if enemy_atb_gauges[i] >= 100.0:
				enemy_atb_gauges[i] = 0.0
				_enemy_attack(i)

func _process_debuffs(delta):
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
					log_label.text = GameManager.party[i]["name"] + " bleeds for " + str(dmg)
					_check_loss_condition()

			if d["duration"] > 0:
				active_list.append(d)
		party_debuffs[i] = active_list

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
					enemies_data[i]["hp"] -= dmg
					log_label.text = enemies_data[i]["name"] + " bleeds for " + str(dmg)
					_refresh_enemy_ui()
					_check_win_condition()

			if d["duration"] > 0:
				active_list.append(d)
		enemy_debuffs[i] = active_list

func apply_debuff(is_party, index, type, duration):
	var list_ref = null
	if is_party:
		if index >= 0 and index < party_debuffs.size():
			list_ref = party_debuffs[index]
	else:
		if index >= 0 and index < enemy_debuffs.size():
			list_ref = enemy_debuffs[index]

	if list_ref == null: return

	var existing = null
	for d in list_ref:
		if d["type"] == type:
			existing = d
			break

	if existing:
		existing["duration"] = duration
		if type == "bleed":
			existing["stacks"] += 1
	else:
		var new_debuff = { "type": type, "duration": duration }
		if type == "bleed":
			new_debuff["stacks"] = 1
			new_debuff["tick_timer"] = 1.0

		list_ref.append(new_debuff)

	if not is_party:
		_refresh_enemy_ui()

func _update_party_bars_only():
	var children = party_container.get_children()
	for i in range(children.size()):
		if i >= party_stamina.size(): break
		var panel = children[i]
		var vbox = panel.get_child(0)
		if vbox.get_child_count() >= 5:
			var hp_bar = vbox.get_child(1)
			var hp_text = vbox.get_child(2)
			var s_bar = vbox.get_child(4)

			var member = GameManager.party[i]
			var bonus_hp = GameManager.get_member_effective_stat(i, "hp", 0)
			var max_hp = member["max_hp"] + bonus_hp

			hp_bar.max_value = max_hp
			hp_bar.value = member["hp"]
			var shield = member.get("shield", 0)
			var txt = str(member["hp"]) + "/" + str(max_hp)
			if shield > 0: txt += " [" + str(shield) + "]"
			hp_text.text = txt

			s_bar.max_value = party_max_stamina[i]
			s_bar.value = party_stamina[i]

func _ai_companion_act(member_idx):
	party_stamina[member_idx] -= AI_ACTION_COST

	var needs_heal = false
	for m in GameManager.party:
		if m["hp"] > 0 and m["hp"] < (m["max_hp"] * 0.5):
			needs_heal = true
			break

	var action = "attack"
	if needs_heal and randf() < 0.3:
		action = "heal"

	if action == "heal":
		var heal_amt = 5
		GameManager.heal_party(heal_amt)
		SoundManager.play_sfx("click")
		log_label.text = GameManager.party[member_idx]["name"] + " heals party for " + str(heal_amt)
	else:
		# Attack
		var base_dmg = GameManager.party[member_idx].get("base_damage", 2)
		var total_dmg = GameManager.get_member_effective_stat(member_idx, "damage", base_dmg)

		var targets = []
		for e_idx in range(enemies_data.size()):
			if enemies_data[e_idx]["hp"] > 0:
				targets.append(e_idx)

		if targets.size() > 0:
			var t = targets.pick_random()
			GameManager.deal_damage_to_enemy_data(enemies_data[t], total_dmg)
			enemies_data[t]["last_attacker"] = member_idx

			SoundManager.play_sfx("hit")
			log_label.text = GameManager.party[member_idx]["name"] + " hits " + enemies_data[t]["name"] + " for " + str(total_dmg)
			_refresh_enemy_ui()
			_check_win_condition()

func _enemy_attack(enemy_idx):
	var ai_type = enemies_data[enemy_idx].get("ai_type", "random")
	var target_idx = -1

	var alive_indices = []
	for i in range(GameManager.party.size()):
		if GameManager.party[i]["hp"] > 0:
			alive_indices.append(i)

	if alive_indices.size() == 0:
		return

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
		var dmg = enemies_data[enemy_idx].get("damage", 2)
		GameManager.damage_party_member(target_idx, dmg)
		SoundManager.play_sfx("hit")

		if enemies_data[enemy_idx]["name"] == "Skeleton":
			if randf() < 0.5:
				apply_debuff(true, target_idx, "bleed", 4.0)
				log_label.text += " Applied Bleed!"

		log_label.text = enemies_data[enemy_idx]["name"] + " hits " + GameManager.party[target_idx]["name"] + " for " + str(dmg)
		_check_loss_condition()

func _input(event):
	if not is_combat_active:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		if is_targeting_mode:
			if event.keycode == KEY_RIGHT:
				_move_cursor(1)
			elif event.keycode == KEY_LEFT:
				_move_cursor(-1)
			elif event.keycode == KEY_0 or event.keycode == KEY_KP_0:
				if target_cursor_index >= 0 and target_cursor_index < enemies_data.size():
					_on_enemy_selected(target_cursor_index)
			return

		var key = ""
		if event.keycode == KEY_Q:
			key = "Q"
		elif event.keycode == KEY_W:
			key = "W"
		elif event.keycode == KEY_E:
			key = "E"

		if key != "":
			if input_cooldown_timer > 0:
				return

			if party_stamina[0] >= BASE_STAMINA_COST:
				party_stamina[0] -= BASE_STAMINA_COST
				input_buffer.append(key)
				input_cooldown_timer = INPUT_COOLDOWN
				_update_input_label()
				SoundManager.play_sfx("click")

				if input_buffer.size() >= 3:
					is_targeting_mode = true
					input_feedback.text = "Combo Ready! Select with Arrows, Confirm with 0"
					# Auto-select first available target for cursor
					_move_cursor(0)
			else:
				log_label.text = "Not enough stamina!"

func _update_input_label():
	if not is_targeting_mode:
		var text = "Input: "
		for k in input_buffer:
			text += k + " "
		input_feedback.text = text

func _execute_combo():
	var q = input_buffer.count("Q")
	var w = input_buffer.count("W")
	var e = input_buffer.count("E")

	var log_text = "Player Combo: "

	# Heal (And Buff)
	if w > 0:
		var heal_base = w * 1
		GameManager.heal_party(heal_base)
		log_text += "Heal party " + str(heal_base) + ". "

		# W also applies Attack Boost Buff (Positive effect)
		apply_debuff(true, 0, "attack_boost", 10.0)
		log_text += " Applied Attack Boost."
		SoundManager.play_sfx("click")

	# Damage
	var base_dmg_stat = GameManager.party[0].get("base_damage", 2)
	var dmg_bonus = GameManager.get_member_effective_stat(0, "damage", base_dmg_stat)

	var combo_dmg = (q * 1) + (e * 2)
	var total_dmg = combo_dmg + dmg_bonus

	# Check Attack Boost Buff
	# Iterate party_debuffs[0] (Player effects)
	var dmg_multiplier = 1.0
	for d in party_debuffs[0]:
		if d["type"] == "attack_boost":
			dmg_multiplier += 0.20 # +20%

	total_dmg *= dmg_multiplier

	if combo_dmg > 0:
		if selected_enemy_index != -1 and selected_enemy_index < enemies_data.size() and enemies_data[selected_enemy_index]["hp"] > 0:
			GameManager.deal_damage_to_enemy_data(enemies_data[selected_enemy_index], total_dmg)
			enemies_data[selected_enemy_index]["last_attacker"] = 0

			SoundManager.play_sfx("hit")
			log_text += "Hit enemy for " + str(total_dmg) + "."

			if q > 0:
				apply_debuff(false, selected_enemy_index, "bleed", 4.0)
				log_text += " Applied Bleed."
			if e > 0:
				apply_debuff(false, selected_enemy_index, "slowed", 5.0)
				log_text += " Applied Slowed."

			_refresh_enemy_ui()
			_check_win_condition()
		else:
			log_text += "Attack missed (no target)!"

	log_label.text = log_text
	input_buffer.clear()
	_update_input_label()

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
		is_combat_active = false
		SoundManager.play_sfx("victory")
		log_label.text = "Victory! gained " + str(total_xp) + " XP and " + str(total_gold) + " Gold."
		GameManager.gain_rewards(total_xp, total_gold)
		GameManager.mark_level_complete(GameManager.selected_level)

		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file("res://scenes/LevelSelector.tscn")

func _check_loss_condition():
	var all_dead = true
	for m in GameManager.party:
		if m["hp"] > 0:
			all_dead = false
			break

	if all_dead:
		is_combat_active = false
		SoundManager.play_sfx("click") # Sad sound?
		log_label.text = "Defeat..."
		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
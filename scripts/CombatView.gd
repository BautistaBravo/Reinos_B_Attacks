extends Control

var combat_manager = null

# UI References
var stamina_bar: ProgressBar
var input_feedback: Label
var log_label: Label
var party_container: VBoxContainer
var enemy_container: VBoxContainer

func _ready():
	_build_ui()

	combat_manager = load("res://scripts/CombatManager.gd").new()
	add_child(combat_manager)

	combat_manager.log_message.connect(func(t): log_label.text = t)
	combat_manager.party_updated.connect(_on_party_updated)
	combat_manager.enemy_updated.connect(_on_enemy_updated)
	combat_manager.combat_frame_update.connect(_on_combat_frame_update)
	combat_manager.targeting_mode_changed.connect(_on_targeting_mode_changed)
	combat_manager.player_stamina_updated.connect(func(c, m):
		stamina_bar.max_value = m
		stamina_bar.value = c
	)
	combat_manager.combat_ended.connect(_on_combat_ended)

	combat_manager.init_combat()

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
	stamina_bar.max_value = 100
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

func _input(event):
	if combat_manager:
		combat_manager.handle_input(event)

func _on_party_updated(party_data, party_stamina, party_max_stamina):
	for child in party_container.get_children():
		child.queue_free()

	for i in range(party_data.size()):
		var member = party_data[i]
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

		var m_lbl = Label.new()
		m_lbl.text = "Mana"
		m_lbl.add_theme_font_size_override("font_size", 10)
		vbox.add_child(m_lbl)

		var m_bar = ProgressBar.new()
		m_bar.max_value = member.get("max_mp", 20)
		m_bar.value = member.get("mp", 20)
		m_bar.custom_minimum_size = Vector2(100, 8)
		m_bar.modulate = Color(0.2, 0.2, 1.0)
		vbox.add_child(m_bar)

func _on_enemy_updated(enemies_data, atb_gauges, selected_idx):
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
		btn.button_pressed = (i == selected_idx)

		var txt = enemy["name"] + "\nHP: " + str(enemy["hp"])
		var shield = enemy.get("shield", 0)
		if shield > 0: txt += " (+"+str(shield)+")"
		btn.text = txt

		# We don't have debuff list passed in signal easily, wait.
		# enemy_updated signal in CombatManager:
		# signal enemy_updated(enemies_data, atb_gauges, selected_idx)
		# CombatManager stores debuffs internally.
		# But we can access CombatManager since we hold a ref.

		var debuffs = combat_manager.enemy_debuffs[i] if i < combat_manager.enemy_debuffs.size() else []
		var debuff_text = ""
		for d in debuffs:
			debuff_text += d["type"].left(1).to_upper() + " "
		if debuff_text != "":
			btn.text += "\n[" + debuff_text + "]"

		btn.custom_minimum_size = Vector2(120, 60)
		# Buttons don't need to do anything as input is handled by keys,
		# but visualization of selection is key.

		# Highlighting logic was:
		# if is_targeting_mode and i == target_cursor_index: ...
		# But targeting mode state is in CombatManager.
		# We can check combat_manager.is_targeting_mode and combat_manager.target_cursor_index

		if combat_manager.is_targeting_mode and i == combat_manager.target_cursor_index:
			btn.modulate = Color(1.5, 1.5, 0.5)
			btn.text = "> " + btn.text + " <"
		else:
			btn.modulate = Color(1, 1, 1)

		enemy_container.add_child(btn)

func _on_combat_frame_update(party_stamina, enemy_atb):
	# Update bars without full rebuild
	var children = party_container.get_children()
	for i in range(children.size()):
		if i >= party_stamina.size(): break
		var vbox = children[i].get_child(0)
		# Index 4 is Stamina Bar (0=Name, 1=HPBar, 2=HPText, 3=StamLabel, 4=StamBar, 5=ManaLabel, 6=ManaBar)
		if vbox.get_child_count() >= 7:
			var s_bar = vbox.get_child(4)
			s_bar.value = party_stamina[i]

			# Mana update? Mana doesn't change on frame usually, but we can sync it.
			# But party_stamina arg only has stamina.
			# We can assume Mana updates come via party_updated signal.
			pass

func _on_targeting_mode_changed(is_targeting, text):
	input_feedback.text = text
	# Trigger enemy update to refresh highlights
	_on_enemy_updated(combat_manager.enemies_data, combat_manager.enemy_atb_gauges, combat_manager.selected_enemy_index)

func _on_combat_ended(victory, summary):
	if victory:
		log_label.text = "Victory!"
		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file("res://scenes/LevelSelector.tscn")
	else:
		log_label.text = "Defeat..."
		await get_tree().create_timer(2.0).timeout
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

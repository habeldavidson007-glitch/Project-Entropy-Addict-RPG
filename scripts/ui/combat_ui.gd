extends Control

## CombatUI — the battle screen
## Displays combatants, action buttons, HP bars, AI narration, turn indicator

@onready var player_name_label: Label = %PlayerNameLabel
@onready var player_hp_bar: ProgressBar = %PlayerHPBar
@onready var player_hp_label: Label = %PlayerHPLabel
@onready var player_mp_label: Label = %PlayerMPLabel
@onready var player_entropy_bar: ProgressBar = %PlayerEntropyBar
@onready var enemy_container: VBoxContainer = %EnemyContainer
@onready var skill_container: HBoxContainer = %SkillContainer
@onready var narration_label: RichTextLabel = %NarrationLabel
@onready var turn_label: Label = %TurnLabel
@onready var round_label: Label = %RoundLabel
@onready var result_overlay: Panel = %ResultOverlay
@onready var result_label: Label = %ResultLabel
@onready var result_btn: Button = %ResultButton
@onready var waiting_label: Label = %WaitingLabel

var _enemy_hp_bars: Dictionary = {}     # unit name → ProgressBar
var _selected_target_index: int = 0
var _living_enemies: Array = []


func _ready() -> void:
	result_overlay.hide()
	waiting_label.hide()
	# Connect CombatManager signals
	CombatManager.combat_started.connect(_on_combat_started)
	CombatManager.combat_ended.connect(_on_combat_ended)
	CombatManager.turn_started.connect(_on_turn_started)
	CombatManager.damage_dealt.connect(_on_damage_dealt)
	CombatManager.unit_died.connect(_on_unit_died)
	CombatManager.narration_ready.connect(_show_narration)
	result_btn.pressed.connect(_on_result_dismissed)


func _on_combat_started(enemies: Array) -> void:
	_build_enemy_display(enemies)
	_build_skill_buttons()
	_refresh_player_display()
	narration_label.text = "[i]Combat begins.[/i]"
	round_label.text = "Round 1"


func _build_enemy_display(enemies: Array) -> void:
	for child in enemy_container.get_children():
		child.queue_free()
	_enemy_hp_bars.clear()
	_living_enemies.clear()
	for i in enemies.size():
		var enemy := enemies[i]
		_living_enemies.append(enemy)
		var row := VBoxContainer.new()
		var name_lbl := Label.new()
		name_lbl.text = "%s  Lv.%d  [%s]" % [enemy["name"], enemy.get("level", 1), enemy.get("faction", "")]
		name_lbl.add_theme_font_size_override("font_size", 13)
		row.add_child(name_lbl)
		var hp_bar := ProgressBar.new()
		hp_bar.max_value = 100
		hp_bar.value = 100
		hp_bar.custom_minimum_size = Vector2(200, 14)
		row.add_child(hp_bar)
		_enemy_hp_bars[enemy["name"]] = hp_bar
		# Description (async AI)
		var desc_lbl := Label.new()
		desc_lbl.text = "..."
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(desc_lbl)
		var req_id := AIManager.describe_enemy(
			enemy["name"],
			enemy.get("level", 1),
			enemy.get("faction", "Unknown"),
			GameState.world.get("current_area", "Unknown Region")
		)
		AIManager.ai_response_received.connect(
			func(rid: String, text: String):
				if rid == req_id:
					desc_lbl.text = text,
			CONNECT_ONE_SHOT
		)
		# Target selector button
		var target_btn := Button.new()
		target_btn.text = "Target"
		target_btn.pressed.connect(func(): _set_target(i))
		row.add_child(target_btn)
		enemy_container.add_child(row)


func _build_skill_buttons() -> void:
	for child in skill_container.get_children():
		child.queue_free()
	var known_skills: Array = ["strike"] + GameState.player.get("skills", [])
	for skill_key in known_skills:
		if not CombatManager.SKILLS.has(skill_key):
			continue
		var skill := CombatManager.SKILLS[skill_key]
		var btn := Button.new()
		var cost_str := "(%d MP)" % skill["mp_cost"] if skill["mp_cost"] > 0 else "(Free)"
		btn.text = "%s\n%s" % [skill["name"], cost_str]
		btn.custom_minimum_size = Vector2(90, 60)
		btn.pressed.connect(func(): _execute_skill(skill_key))
		skill_container.add_child(btn)
	# End turn button
	var end_btn := Button.new()
	end_btn.text = "End\nTurn"
	end_btn.custom_minimum_size = Vector2(70, 60)
	end_btn.pressed.connect(CombatManager.end_player_turn)
	skill_container.add_child(end_btn)


func _refresh_player_display() -> void:
	var p := GameState.player
	player_name_label.text = "%s  Lv.%d" % [p["name"], p["level"]]
	player_hp_bar.value = float(p["hp"]) / float(p["hp_max"]) * 100.0
	player_hp_label.text = "%d/%d HP" % [p["hp"], p["hp_max"]]
	player_mp_label.text = "%d/%d MP" % [p["mp"], p["mp_max"]]
	var entropy_ratio: float = float(p["entropy"]) / float(p["entropy_max"])
	player_entropy_bar.value = entropy_ratio * 100.0


func _set_target(index: int) -> void:
	_selected_target_index = index
	turn_label.text = "Target: %s" % _living_enemies[index]["name"]


func _execute_skill(skill_key: String) -> void:
	if CombatManager.state != CombatManager.CombatState.PLAYER_TURN:
		return
	if _living_enemies.is_empty():
		return
	# Auto-target first living enemy if none selected
	var target: Dictionary = _living_enemies[_selected_target_index]
	var player_unit := _get_player_from_combatants()
	if player_unit.is_empty():
		return
	_set_buttons_disabled(true)
	CombatManager.execute_action(player_unit, target, skill_key)


func _get_player_from_combatants() -> Dictionary:
	for unit in CombatManager.combatants:
		if unit.get("is_player", false):
			return unit
	return {}


func _on_turn_started(unit: Dictionary) -> void:
	round_label.text = "Round %d" % CombatManager.round_number
	_refresh_player_display()
	if unit.get("is_player", false):
		turn_label.text = "Your turn"
		_set_buttons_disabled(false)
		waiting_label.hide()
	else:
		turn_label.text = "%s's turn" % unit["name"]
		_set_buttons_disabled(true)
		waiting_label.show()
		waiting_label.text = "Enemy acting..."


func _on_damage_dealt(attacker: Dictionary, target: Dictionary, amount: int, _skill: String) -> void:
	# Update enemy HP bar
	if target.get("team", "") == "enemy":
		var bar: ProgressBar = _enemy_hp_bars.get(target["name"])
		if bar:
			bar.value = float(target.get("hp", 0)) / float(target.get("hp_max", 1)) * 100.0
	_refresh_player_display()
	# Sync player HP back to GameState
	if target.get("is_player", false):
		GameState.player["hp"] = target.get("hp", GameState.player["hp"])


func _on_unit_died(unit: Dictionary) -> void:
	if unit.get("team", "") == "enemy":
		_living_enemies = _living_enemies.filter(func(u): return u["name"] != unit["name"])
		if _selected_target_index >= _living_enemies.size():
			_selected_target_index = max(0, _living_enemies.size() - 1)


func _show_narration(text: String) -> void:
	narration_label.text = "[i]%s[/i]" % text


func _on_combat_ended(victory: bool) -> void:
	result_overlay.show()
	_set_buttons_disabled(true)
	if victory:
		result_label.text = "SURVIVED\n+%d XP" % _calculate_xp()
		result_btn.text = "Continue"
	else:
		result_label.text = "DEAD\n\nEntropy wins."
		result_btn.text = "Back to Menu"


func _calculate_xp() -> int:
	var total := 0
	for unit in CombatManager.combatants:
		if unit.get("team", "") == "enemy":
			total += unit.get("xp_reward", 10)
	return total


func _on_result_dismissed() -> void:
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _set_buttons_disabled(disabled: bool) -> void:
	for child in skill_container.get_children():
		if child is Button:
			child.disabled = disabled

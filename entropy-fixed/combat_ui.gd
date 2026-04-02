extends Control

## CombatUI — battle screen controller
## All @onready refs use unique names (%). Scene must have matching nodes.

@onready var player_name_label  : Label         = %PlayerNameLabel
@onready var player_hp_bar      : ProgressBar   = %PlayerHPBar
@onready var player_hp_label    : Label         = %PlayerHPLabel
@onready var player_mp_label    : Label         = %PlayerMPLabel
@onready var player_entropy_bar : ProgressBar   = %PlayerEntropyBar
@onready var enemy_container    : VBoxContainer = %EnemyContainer
@onready var skill_container    : HBoxContainer = %SkillContainer
@onready var narration_label    : RichTextLabel = %NarrationLabel
@onready var turn_label         : Label         = %TurnLabel
@onready var round_label        : Label         = %RoundLabel
@onready var result_overlay     : Panel         = %ResultOverlay
@onready var result_label       : Label         = %ResultLabel
@onready var result_btn         : Button        = %ResultButton
@onready var waiting_label      : Label         = %WaitingLabel

var _enemy_bars   : Dictionary = {}   # name → ProgressBar
var _living       : Array      = []
var _target_idx   : int        = 0


func _ready() -> void:
	result_overlay.hide()
	waiting_label.hide()
	CombatManager.combat_started.connect(_on_combat_started)
	CombatManager.combat_ended.connect(_on_combat_ended)
	CombatManager.turn_started.connect(_on_turn_started)
	CombatManager.damage_dealt.connect(_on_damage_dealt)
	CombatManager.unit_died.connect(_on_unit_died)
	CombatManager.narration_ready.connect(_show_narration)
	result_btn.pressed.connect(_on_result)


func _on_combat_started(enemies: Array) -> void:
	_living.clear()
	_enemy_bars.clear()
	_build_enemy_display(enemies)
	_build_skill_buttons()
	_refresh_player()
	narration_label.text = "[i]Combat begins.[/i]"
	round_label.text     = "Round 1"
	turn_label.text      = "Your turn"


func _build_enemy_display(enemies: Array) -> void:
	for c in enemy_container.get_children():
		c.queue_free()
	for i in enemies.size():
		var e := enemies[i]
		_living.append(e)
		var vbox := VBoxContainer.new()

		var name_lbl := Label.new()
		name_lbl.text = "%s  Lv.%d" % [e.get("name","?"), e.get("level",1)]
		name_lbl.add_theme_font_size_override("font_size", 13)
		vbox.add_child(name_lbl)

		var bar := ProgressBar.new()
		bar.max_value = 100
		bar.value     = 100
		bar.custom_minimum_size = Vector2(200, 14)
		vbox.add_child(bar)
		_enemy_bars[e.get("name","?")] = bar

		var desc_lbl := Label.new()
		desc_lbl.text = "..."
		desc_lbl.add_theme_font_size_override("font_size", 11)
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(0, 32)
		vbox.add_child(desc_lbl)

		var req_id := AIManager.describe_enemy(
			e.get("name","?"), e.get("level",1),
			e.get("faction","Unknown"),
			GameState.world.get("current_area","Unknown")
		)
		var d_cap := desc_lbl
		AIManager.ai_response_received.connect(
			func(rid: String, text: String):
				if rid == req_id and is_instance_valid(d_cap):
					d_cap.text = text,
			CONNECT_ONE_SHOT
		)

		var target_btn := Button.new()
		var i_cap      := i
		target_btn.text = "▶ Target"
		target_btn.pressed.connect(func(): _set_target(i_cap))
		vbox.add_child(target_btn)

		enemy_container.add_child(vbox)


func _build_skill_buttons() -> void:
	for c in skill_container.get_children():
		c.queue_free()
	var known : Array = ["strike"] + GameState.player.get("skills", [])
	for sk_key in known:
		if not CombatManager.SKILLS.has(sk_key):
			continue
		var sk  := CombatManager.SKILLS[sk_key]
		var btn := Button.new()
		var k   := sk_key
		btn.text = "%s\n%s" % [sk["name"], ("(%dMP)" % sk["mp_cost"]) if sk["mp_cost"] > 0 else "(Free)"]
		btn.custom_minimum_size = Vector2(90, 60)
		btn.pressed.connect(func(): _use_skill(k))
		skill_container.add_child(btn)

	var end_btn := Button.new()
	end_btn.text                = "End\nTurn"
	end_btn.custom_minimum_size = Vector2(70, 60)
	end_btn.pressed.connect(CombatManager.end_player_turn)
	skill_container.add_child(end_btn)


func _refresh_player() -> void:
	var p := GameState.player
	player_name_label.text  = "%s  Lv.%d" % [p.get("name","?"), p.get("level",1)]
	var hp_r := float(p.get("hp",0)) / float(max(1, p.get("hp_max",100)))
	var mp_r := float(p.get("mp",0)) / float(max(1, p.get("mp_max",50)))
	var en_r := float(p.get("entropy",0)) / float(max(1, p.get("entropy_max",100)))
	player_hp_bar.value      = hp_r * 100.0
	player_hp_label.text     = "%d/%d HP" % [p.get("hp",0), p.get("hp_max",100)]
	player_mp_label.text     = "%d/%d MP" % [p.get("mp",0), p.get("mp_max",50)]
	player_entropy_bar.value = en_r * 100.0


func _set_target(idx: int) -> void:
	_target_idx = clamp(idx, 0, max(0, _living.size() - 1))
	if _living.size() > _target_idx:
		turn_label.text = "Target: %s" % _living[_target_idx].get("name","?")


func _use_skill(skill_key: String) -> void:
	if CombatManager.state != CombatManager.CombatState.PLAYER_TURN:
		return
	if _living.is_empty():
		return
	_target_idx = clamp(_target_idx, 0, _living.size() - 1)
	var target := _living[_target_idx]
	# Find player unit in combatants
	var player_unit := Dictionary()
	for u in CombatManager.combatants:
		if u.get("is_player", false):
			player_unit = u
			break
	if player_unit.is_empty():
		return
	_set_buttons_disabled(true)
	CombatManager.execute_action(player_unit, target, skill_key)


func _on_turn_started(unit: Dictionary) -> void:
	round_label.text = "Round %d" % CombatManager.round_number
	_refresh_player()
	if unit.get("is_player", false):
		turn_label.text = "Your turn"
		_set_buttons_disabled(false)
		waiting_label.hide()
	else:
		turn_label.text = "%s is acting..." % unit.get("name","Enemy")
		_set_buttons_disabled(true)
		waiting_label.show()


func _on_damage_dealt(_att: Dictionary, target: Dictionary, amount: int, _sk: String) -> void:
	# Update enemy bar
	if target.get("team","") == "enemy":
		var bar : ProgressBar = _enemy_bars.get(target.get("name",""), null)
		if bar:
			var r := float(target.get("hp",0)) / float(max(1, target.get("hp_max",1)))
			bar.value = r * 100.0
	# Sync player HP back to GameState
	if target.get("is_player", false):
		GameState.player["hp"] = target.get("hp", GameState.player["hp"])
	_refresh_player()


func _on_unit_died(unit: Dictionary) -> void:
	if unit.get("team","") == "enemy":
		_living = _living.filter(func(u): return u.get("name","") != unit.get("name",""))
		_target_idx = clamp(_target_idx, 0, max(0, _living.size() - 1))


func _show_narration(text: String) -> void:
	narration_label.text = "[i]%s[/i]" % text


func _on_combat_ended(victory: bool) -> void:
	result_overlay.show()
	_set_buttons_disabled(true)
	if victory:
		var xp := 0
		for u in CombatManager.combatants:
			if u.get("team","") == "enemy":
				xp += u.get("xp_reward", 10)
		result_label.text = "SURVIVED\n+%d XP" % xp
		result_btn.text   = "Continue →"
	else:
		result_label.text = "DEAD.\n\nEntropy wins."
		result_btn.text   = "Back to Menu"


func _on_result() -> void:
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _set_buttons_disabled(val: bool) -> void:
	for c in skill_container.get_children():
		if c is Button:
			c.disabled = val

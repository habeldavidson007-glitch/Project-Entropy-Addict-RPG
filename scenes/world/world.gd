extends Node2D

## World — main exploration scene
## Handles area travel, random encounters, NPC interaction, day/night cycle

signal area_changed(area_key: String)
signal encounter_triggered(enemies: Array)

@onready var area_name_label: Label = %AreaNameLabel
@onready var area_desc_label: RichTextLabel = %AreaDescLabel
@onready var action_container: VBoxContainer = %ActionContainer
@onready var day_label: Label = %DayLabel
@onready var time_label: Label = %TimeLabel
@onready var encounter_panel: Panel = %EncounterPanel
@onready var travel_animation: AnimationPlayer = $TravelAnimation

const TIME_SLOTS := ["dawn", "morning", "afternoon", "dusk", "night"]
const ENCOUNTER_CHANCE := {
	"ashveld_flats": 0.45,
	"iron_ridge": 0.60,
	"collapsed_quarter": 0.55,
	"wanderer_camp": 0.15,
	"old_relay": 0.70,
}

# Area definitions
const AREAS := {
	"ashveld_flats": {
		"name": "Ashveld Flats",
		"danger": "Medium",
		"connections": ["iron_ridge", "wanderer_camp"],
		"enemies": ["rot_crawler", "scavenger_runner"],
		"npcs": ["Old Kael"],
	},
	"iron_ridge": {
		"name": "Iron Ridge",
		"danger": "High",
		"connections": ["ashveld_flats", "old_relay"],
		"enemies": ["ridge_warden", "iron_hound", "rot_crawler"],
		"npcs": [],
	},
	"wanderer_camp": {
		"name": "Wanderer Camp",
		"danger": "Low",
		"connections": ["ashveld_flats"],
		"enemies": [],
		"npcs": ["Mira", "The Trader"],
	},
	"collapsed_quarter": {
		"name": "Collapsed Quarter",
		"danger": "High",
		"connections": ["ashveld_flats", "old_relay"],
		"enemies": ["fractured_construct", "scavenger_runner", "ridge_warden"],
		"npcs": [],
	},
	"old_relay": {
		"name": "Old Relay Station",
		"danger": "Very High",
		"connections": ["iron_ridge", "collapsed_quarter"],
		"enemies": ["relay_sentinel", "fractured_construct"],
		"npcs": ["Signal Ghost"],
	},
}

# Enemy base stats per type
const ENEMY_TEMPLATES := {
	"rot_crawler": {"name": "Rot Crawler", "level": 1, "faction": "Unaffiliated",
		"hp": 30, "str": 4, "agi": 3, "def": 1, "xp_reward": 12, "type": "melee"},
	"scavenger_runner": {"name": "Scavenger Runner", "level": 2, "faction": "Ashveld Scavengers",
		"hp": 25, "str": 5, "agi": 6, "def": 1, "xp_reward": 15, "type": "melee"},
	"ridge_warden": {"name": "Ridge Warden", "level": 3, "faction": "Iron Ridge Remnants",
		"hp": 55, "str": 7, "agi": 4, "def": 4, "xp_reward": 25, "type": "melee"},
	"iron_hound": {"name": "Iron Hound", "level": 3, "faction": "Iron Ridge Remnants",
		"hp": 35, "str": 8, "agi": 7, "def": 2, "xp_reward": 20, "type": "melee"},
	"fractured_construct": {"name": "Fractured Construct", "level": 4, "faction": "Pre-Collapse",
		"hp": 70, "str": 9, "agi": 3, "def": 6, "xp_reward": 35, "type": "melee"},
	"relay_sentinel": {"name": "Relay Sentinel", "level": 5, "faction": "Old Guard",
		"hp": 60, "str": 8, "agi": 5, "def": 4, "xp_reward": 40, "type": "caster"},
}

var current_area_key: String = "ashveld_flats"
var time_index: int = 1    # morning
var _ai_desc_request: String = ""


func _ready() -> void:
	CombatManager.combat_ended.connect(_on_combat_ended)
	encounter_panel.hide()
	_enter_area(GameState.world.get("current_area", "ashveld_flats"))


func _enter_area(area_key: String) -> void:
	if not AREAS.has(area_key):
		push_error("[World] Unknown area: %s" % area_key)
		return
	current_area_key = area_key
	GameState.world["current_area"] = area_key
	var area := AREAS[area_key]
	area_name_label.text = area["name"]
	area_desc_label.text = "..."
	_build_action_buttons(area)
	_update_time_display()
	# Track discovered areas
	if not GameState.world["discovered_areas"].has(area_key):
		GameState.world["discovered_areas"].append(area_key)
	# Fetch AI area description
	var cache_key := "area_desc_%s_%s" % [area_key, TIME_SLOTS[time_index]]
	if GameState.has_flag(cache_key):
		area_desc_label.text = GameState.get_flag(cache_key)
	else:
		_ai_desc_request = AIManager.describe_area(area["name"], area["danger"], TIME_SLOTS[time_index])
		AIManager.ai_response_received.connect(_on_area_desc, CONNECT_ONE_SHOT)
	area_changed.emit(area_key)
	# Check for encounter on arrival
	if area["enemies"].size() > 0:
		await get_tree().create_timer(0.6).timeout
		_roll_encounter(area)


func _on_area_desc(req_id: String, text: String) -> void:
	if req_id != _ai_desc_request:
		return
	area_desc_label.text = text
	var cache_key := "area_desc_%s_%s" % [current_area_key, TIME_SLOTS[time_index]]
	GameState.set_flag(cache_key, text)


func _build_action_buttons(area: Dictionary) -> void:
	for child in action_container.get_children():
		child.queue_free()
	# Travel buttons
	for connected_key in area["connections"]:
		if not AREAS.has(connected_key):
			continue
		var dest := AREAS[connected_key]
		var btn := Button.new()
		btn.text = "→ %s  [%s]" % [dest["name"], dest["danger"]]
		btn.pressed.connect(func(): _travel_to(connected_key))
		action_container.add_child(btn)
	# Rest button
	var rest_btn := Button.new()
	rest_btn.text = "Rest  (-10 Entropy, advance time)"
	rest_btn.pressed.connect(_on_rest)
	action_container.add_child(rest_btn)
	# NPC talk buttons
	for npc_name in area["npcs"]:
		var npc_btn := Button.new()
		npc_btn.text = "Talk: %s" % npc_name
		npc_btn.pressed.connect(func(): _talk_to_npc(npc_name, area))
		action_container.add_child(npc_btn)
	# Save
	var save_btn := Button.new()
	save_btn.text = "Save game"
	save_btn.pressed.connect(func(): GameState.save())
	action_container.add_child(save_btn)


func _travel_to(area_key: String) -> void:
	_advance_time()
	GameState.add_entropy(2)
	_enter_area(area_key)


func _on_rest() -> void:
	GameState.reduce_entropy(10)
	GameState.heal(int(GameState.player["hp_max"] * 0.25))
	_advance_time()
	_advance_time()
	_update_time_display()


func _advance_time() -> void:
	time_index = (time_index + 1) % TIME_SLOTS.size()
	if time_index == 0:
		GameState.world["day"] += 1
		GameState.add_entropy(3)    # new day costs entropy
	GameState.world["time_of_day"] = TIME_SLOTS[time_index]


func _update_time_display() -> void:
	day_label.text = "Day %d" % GameState.world["day"]
	time_label.text = TIME_SLOTS[time_index].capitalize()


func _roll_encounter(area: Dictionary) -> void:
	var chance: float = ENCOUNTER_CHANCE.get(current_area_key, 0.3)
	if randf() > chance:
		return
	# Pick 1–3 random enemies from this area's pool
	var pool: Array = area["enemies"].duplicate()
	pool.shuffle()
	var count: int = randi_range(1, min(3, pool.size()))
	var enemies: Array = []
	for i in count:
		var template := ENEMY_TEMPLATES.get(pool[i], {})
		if not template.is_empty():
			enemies.append(template.duplicate())
	if enemies.is_empty():
		return
	_show_encounter(enemies)


func _show_encounter(enemies: Array) -> void:
	encounter_panel.show()
	encounter_triggered.emit(enemies)
	# Transition to combat scene
	await get_tree().create_timer(1.0).timeout
	encounter_panel.hide()
	CombatManager.start_combat(enemies)
	get_tree().change_scene_to_file("res://scenes/ui/combat_ui.tscn")


func _on_combat_ended(victory: bool) -> void:
	if victory:
		GameState.save()
	else:
		# On death — return to menu, save is preserved for retry
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


func _talk_to_npc(npc_name: String, area: Dictionary) -> void:
	var faction := _infer_npc_faction(npc_name)
	var mood := _infer_npc_mood(npc_name)
	var context := "Player arrived at %s. Day %d." % [area["name"], GameState.world["day"]]
	var req_id := AIManager.npc_speak(npc_name, faction, mood, context)
	AIManager.ai_response_received.connect(
		func(rid: String, text: String):
			if rid != req_id:
				return
			_show_npc_dialogue(npc_name, text),
		CONNECT_ONE_SHOT
	)


func _show_npc_dialogue(npc_name: String, text: String) -> void:
	area_desc_label.text = "[%s]\n\"%s\"" % [npc_name, text]


func _infer_npc_faction(npc_name: String) -> String:
	match npc_name:
		"Old Kael": return "Wanderers"
		"Mira": return "Wanderers"
		"The Trader": return "Independent"
		"Signal Ghost": return "Old Guard"
		_: return "Unknown"


func _infer_npc_mood(npc_name: String) -> String:
	var rep: int = GameState.get_faction_rep(_infer_npc_faction(npc_name))
	if rep > 30: return "cautiously friendly"
	if rep < -30: return "hostile"
	return "guarded"

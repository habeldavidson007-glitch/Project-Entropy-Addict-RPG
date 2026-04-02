extends Node2D

## World — main exploration scene
## All @onready refs null-checked. Scene paths corrected. No crash on missing nodes.

signal area_changed(area_key: String)
signal encounter_triggered(enemies: Array)

# ── UI node refs — all null-safe ──────────────────────────────────────────────
@onready var area_name_label   : Label          = _find_node("AreaNameLabel")
@onready var area_desc_label   : RichTextLabel  = _find_node("AreaDescLabel")
@onready var action_container  : VBoxContainer  = _find_node("ActionContainer")
@onready var day_label         : Label          = _find_node("DayLabel")
@onready var time_label        : Label          = _find_node("TimeLabel")
@onready var encounter_panel   : Panel          = _find_node("EncounterPanel")

const TIME_SLOTS : Array[String] = ["dawn", "morning", "afternoon", "dusk", "night"]

const ENCOUNTER_CHANCE : Dictionary = {
	"ashveld_flats"    : 0.45,
	"iron_ridge"       : 0.60,
	"collapsed_quarter": 0.55,
	"wanderer_camp"    : 0.15,
	"old_relay"        : 0.70,
}

const AREAS : Dictionary = {
	"ashveld_flats": {
		"name": "Ashveld Flats", "danger": "Medium",
		"connections": ["iron_ridge", "wanderer_camp"],
		"enemies": ["rot_crawler", "scavenger_runner"],
		"npcs": ["Old Kael"],
	},
	"iron_ridge": {
		"name": "Iron Ridge", "danger": "High",
		"connections": ["ashveld_flats", "old_relay"],
		"enemies": ["ridge_warden", "iron_hound", "rot_crawler"],
		"npcs": [],
	},
	"wanderer_camp": {
		"name": "Wanderer Camp", "danger": "Low",
		"connections": ["ashveld_flats"],
		"enemies": [],
		"npcs": ["Mira", "The Trader"],
	},
	"collapsed_quarter": {
		"name": "Collapsed Quarter", "danger": "High",
		"connections": ["ashveld_flats", "old_relay"],
		"enemies": ["fractured_construct", "scavenger_runner", "ridge_warden"],
		"npcs": [],
	},
	"old_relay": {
		"name": "Old Relay Station", "danger": "Very High",
		"connections": ["iron_ridge", "collapsed_quarter"],
		"enemies": ["relay_sentinel", "fractured_construct"],
		"npcs": ["Signal Ghost"],
	},
}

const ENEMY_TEMPLATES : Dictionary = {
	"rot_crawler"       : {"name": "Rot Crawler",        "level": 1, "faction": "Unaffiliated",
		"hp": 30, "hp_max": 30, "str": 4, "agi": 3, "def": 1, "xp_reward": 12, "type": "melee"},
	"scavenger_runner"  : {"name": "Scavenger Runner",   "level": 2, "faction": "Ashveld Scavengers",
		"hp": 25, "hp_max": 25, "str": 5, "agi": 6, "def": 1, "xp_reward": 15, "type": "melee"},
	"ridge_warden"      : {"name": "Ridge Warden",       "level": 3, "faction": "Iron Ridge Remnants",
		"hp": 55, "hp_max": 55, "str": 7, "agi": 4, "def": 4, "xp_reward": 25, "type": "melee"},
	"iron_hound"        : {"name": "Iron Hound",         "level": 3, "faction": "Iron Ridge Remnants",
		"hp": 35, "hp_max": 35, "str": 8, "agi": 7, "def": 2, "xp_reward": 20, "type": "melee"},
	"fractured_construct": {"name": "Fractured Construct","level": 4, "faction": "Pre-Collapse",
		"hp": 70, "hp_max": 70, "str": 9, "agi": 3, "def": 6, "xp_reward": 35, "type": "melee"},
	"relay_sentinel"    : {"name": "Relay Sentinel",     "level": 5, "faction": "Old Guard",
		"hp": 60, "hp_max": 60, "str": 8, "agi": 5, "def": 4, "xp_reward": 40, "type": "caster",
		"mp": 30, "mp_max": 30},
}

var current_area_key : String = "ashveld_flats"
var time_index       : int    = 1
var _area_req_id     : String = ""
var _in_combat       : bool   = false


func _ready() -> void:
	CombatManager.combat_ended.connect(_on_combat_ended)
	if encounter_panel:
		encounter_panel.hide()
	var start_area : String = GameState.world.get("current_area", "ashveld_flats")
	_enter_area(start_area)


# ── Area Navigation ───────────────────────────────────────────────────────────

func _enter_area(area_key: String) -> void:
	if not AREAS.has(area_key):
		push_error("[World] Unknown area key: " + area_key)
		return
	_in_combat      = false
	current_area_key = area_key
	GameState.world["current_area"] = area_key

	var area : Dictionary = AREAS[area_key]
	_set_label(area_name_label, area["name"])
	_set_rich(area_desc_label,  "...")
	_build_buttons(area)
	_update_time()

	if not GameState.world["discovered_areas"].has(area_key):
		GameState.world["discovered_areas"].append(area_key)

	# AI area description
	var cache_key := "area_desc_%s_%s" % [area_key, TIME_SLOTS[time_index]]
	if GameState.has_flag(cache_key):
		_set_rich(area_desc_label, GameState.get_flag(cache_key))
	else:
		_area_req_id = AIManager.describe_area(area["name"], area["danger"], TIME_SLOTS[time_index])
		AIManager.ai_response_received.connect(_on_area_desc, CONNECT_ONE_SHOT)

	area_changed.emit(area_key)

	if area["enemies"].size() > 0 and not _in_combat:
		await get_tree().create_timer(0.8).timeout
		if not _in_combat:
			_roll_encounter(area)


func _on_area_desc(req_id: String, text: String) -> void:
	if req_id != _area_req_id:
		return
	_set_rich(area_desc_label, text)
	var cache_key := "area_desc_%s_%s" % [current_area_key, TIME_SLOTS[time_index]]
	GameState.set_flag(cache_key, text)


# ── Buttons ───────────────────────────────────────────────────────────────────

func _build_buttons(area: Dictionary) -> void:
	if not action_container:
		return
	for child in action_container.get_children():
		child.queue_free()

	for key in area["connections"]:
		if not AREAS.has(key):
			continue
		var dest  : Dictionary = AREAS[key]
		var btn   := Button.new()
		var k_cap := key   # capture loop var correctly
		btn.text = "→ %s  [%s]" % [dest["name"], dest["danger"]]
		btn.pressed.connect(func(): _travel_to(k_cap))
		action_container.add_child(btn)

	var rest_btn := Button.new()
	rest_btn.text = "Rest  (heal 25%% HP, -10 Entropy)"
	rest_btn.pressed.connect(_on_rest)
	action_container.add_child(rest_btn)

	for npc_name in area["npcs"]:
		var npc_btn  := Button.new()
		var n_cap    := npc_name
		npc_btn.text  = "Talk: %s" % npc_name
		npc_btn.pressed.connect(func(): _talk_to_npc(n_cap, area))
		action_container.add_child(npc_btn)

	var inv_btn := Button.new()
	inv_btn.text = "Inventory"
	inv_btn.pressed.connect(_on_open_inventory)
	action_container.add_child(inv_btn)

	var save_btn := Button.new()
	save_btn.text = "Save game"
	save_btn.pressed.connect(func(): GameState.save())
	action_container.add_child(save_btn)


# ── Time / Rest ───────────────────────────────────────────────────────────────

func _travel_to(area_key: String) -> void:
	_advance_time()
	GameState.add_entropy(2)
	_enter_area(area_key)


func _on_rest() -> void:
	GameState.reduce_entropy(10)
	GameState.heal(int(GameState.player["hp_max"] * 0.25))
	_advance_time()
	_advance_time()
	_update_time()


func _advance_time() -> void:
	time_index = (time_index + 1) % TIME_SLOTS.size()
	if time_index == 0:
		GameState.world["day"] += 1
		GameState.add_entropy(3)
	GameState.world["time_of_day"] = TIME_SLOTS[time_index]


func _update_time() -> void:
	_set_label(day_label,  "Day %d" % GameState.world["day"])
	_set_label(time_label, TIME_SLOTS[time_index].capitalize())


# ── Encounters ────────────────────────────────────────────────────────────────

func _roll_encounter(area: Dictionary) -> void:
	var chance : float = ENCOUNTER_CHANCE.get(current_area_key, 0.3)
	if randf() > chance:
		return
	var pool  : Array = area["enemies"].duplicate()
	pool.shuffle()
	var count : int   = randi_range(1, min(3, pool.size()))
	var enemies : Array = []
	for i in count:
		if i >= pool.size():
			break
		var tmpl : Dictionary = ENEMY_TEMPLATES.get(pool[i], {})
		if not tmpl.is_empty():
			enemies.append(tmpl.duplicate(true))
	if enemies.is_empty():
		return
	_show_encounter(enemies)


func _show_encounter(enemies: Array) -> void:
	_in_combat = true
	if encounter_panel:
		encounter_panel.show()
	encounter_triggered.emit(enemies)
	await get_tree().create_timer(1.0).timeout
	if encounter_panel:
		encounter_panel.hide()
	CombatManager.start_combat(enemies)
	get_tree().change_scene_to_file("res://scenes/ui/combat_ui.tscn")


func _on_combat_ended(victory: bool) -> void:
	_in_combat = false
	if victory:
		GameState.save()
	else:
		get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


# ── NPC Dialogue ──────────────────────────────────────────────────────────────

func _talk_to_npc(npc_name: String, area: Dictionary) -> void:
	var faction : String = _npc_faction(npc_name)
	var mood    : String = _npc_mood(faction)
	var context : String = "Player at %s. Day %d." % [area["name"], GameState.world["day"]]
	var req_id  : String = AIManager.npc_speak(npc_name, faction, mood, context)
	var n_cap   := npc_name
	AIManager.ai_response_received.connect(
		func(rid: String, text: String):
			if rid == req_id:
				_set_rich(area_desc_label, "[b]%s[/b]\n\"%s\"" % [n_cap, text]),
		CONNECT_ONE_SHOT
	)


func _npc_faction(n: String) -> String:
	match n:
		"Old Kael": return "Wanderers"
		"Mira":     return "Wanderers"
		"The Trader": return "Independent"
		"Signal Ghost": return "Old Guard"
		_: return "Unknown"


func _npc_mood(faction: String) -> String:
	var rep : int = GameState.get_faction_rep(faction)
	if rep > 30:  return "cautiously friendly"
	if rep < -30: return "hostile"
	return "guarded"


# ── Inventory placeholder ─────────────────────────────────────────────────────

func _on_open_inventory() -> void:
	# When InventoryUI scene exists, uncomment:
	# get_tree().change_scene_to_file("res://scenes/ui/inventory_ui.tscn")
	_set_rich(area_desc_label, "[Inventory system coming soon]")


# ── Null-safe Helpers ─────────────────────────────────────────────────────────

func _find_node(node_name: String) -> Node:
	# Searches by unique name (%) or regular name
	var found : Node = find_child(node_name, true, false)
	return found


func _set_label(lbl: Label, text: String) -> void:
	if lbl:
		lbl.text = text


func _set_rich(rtl: RichTextLabel, text: String) -> void:
	if rtl:
		rtl.text = text

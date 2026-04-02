extends Node2D
class_name EnemyEntity

## EnemyEntity — base class for all enemies
## AI description fetched once, cached in GameState flags permanently.

signal description_loaded(text: String)

@export var enemy_name  : String = "Unknown Enemy"
@export var level       : int    = 1
@export var faction     : String = "Unaffiliated"
@export var region      : String = "Unknown Region"
@export var base_hp     : int    = 40
@export var base_str    : int    = 4
@export var base_agi    : int    = 3
@export var base_def    : int    = 2
@export var xp_reward   : int    = 15
@export var gold_reward : int    = 5
@export var enemy_type  : String = "melee"
@export var loot_table  : Array[Dictionary] = []

var sprite        : Sprite2D     = null
var hp_bar        : ProgressBar  = null
var combat_data   : Dictionary   = {}
var _description  : String       = ""
var _desc_ready   : bool         = false


func _ready() -> void:
	sprite = get_node_or_null("Sprite2D")
	hp_bar = get_node_or_null("HPBar")
	_build_combat_data()
	_fetch_description()


func _build_combat_data() -> void:
	var m : float = 1.0 + (level - 1) * 0.18
	var hp  : int = int(base_hp  * m)
	combat_data = {
		"name"          : enemy_name,
		"level"         : level,
		"faction"       : faction,
		"hp"            : hp,
		"hp_max"        : hp,   # FIXED: hp_max now always set
		"str"           : int(base_str * m),
		"agi"           : int(base_agi * m),
		"def"           : int(base_def * m),
		"mp"            : 30 if enemy_type == "caster" else 0,
		"mp_max"        : 30 if enemy_type == "caster" else 0,
		"xp_reward"     : xp_reward + level * 5,
		"gold_reward"   : gold_reward,
		"type"          : enemy_type,
		"is_player"     : false,
		"team"          : "enemy",
		"status_effects": [],
	}


func _fetch_description() -> void:
	var cache_key := "edesc_%s_%d" % [enemy_name.to_lower().replace(" ", "_"), level]
	if GameState.has_flag(cache_key):
		_description = GameState.get_flag(cache_key)
		_desc_ready  = true
		description_loaded.emit(_description)
		return
	var req_id := AIManager.describe_enemy(enemy_name, level, faction, region)
	# Use a local variable to avoid closure over mutable state
	var key_cap := cache_key
	AIManager.ai_response_received.connect(
		func(rid: String, text: String) -> void:
			if rid != req_id:
				return
			_description = text
			_desc_ready  = true
			GameState.set_flag(key_cap, text)
			description_loaded.emit(text),
		CONNECT_ONE_SHOT
	)


func get_description() -> String:
	return _description if _desc_ready else "An unknown hostile presence."


func get_combat_data() -> Dictionary:
	return combat_data.duplicate(true)


func update_hp_bar(current_hp: int) -> void:
	if hp_bar:
		hp_bar.value = float(current_hp) / float(combat_data.get("hp_max", 1)) * 100.0


func roll_loot() -> Array:
	var drops : Array = []
	for entry in loot_table:
		if randf() <= entry.get("chance", 0.1):
			drops.append(entry.get("item", {}).duplicate())
	return drops

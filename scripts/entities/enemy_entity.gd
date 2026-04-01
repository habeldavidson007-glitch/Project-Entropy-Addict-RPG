extends Node2D
class_name EnemyEntity

## EnemyEntity — base class for all enemies in Entropy Addict RPG
## AI description is fetched on first encounter and cached in GameState flags

signal description_loaded(text: String)

@export var enemy_name: String = "Unknown"
@export var level: int = 1
@export var faction: String = "Unaffiliated"
@export var region: String = "Unknown Region"
@export var base_hp: int = 40
@export var base_str: int = 4
@export var base_agi: int = 3
@export var base_def: int = 2
@export var xp_reward: int = 15
@export var gold_reward: int = 5
@export var enemy_type: String = "melee"   # melee / caster / ranged
@export var loot_table: Array[Dictionary] = []

@onready var sprite: Sprite2D = $Sprite2D
@onready var hp_bar: ProgressBar = $HPBar

var combat_data: Dictionary = {}
var _description: String = ""
var _description_loaded: bool = false


func _ready() -> void:
	_build_combat_data()
	_load_or_fetch_description()


func _build_combat_data() -> void:
	var scaled := _scale_to_level(level)
	combat_data = {
		"name": enemy_name,
		"level": level,
		"faction": faction,
		"hp": scaled["hp"],
		"hp_max": scaled["hp"],
		"str": scaled["str"],
		"agi": scaled["agi"],
		"def": scaled["def"],
		"mp": 30 if enemy_type == "caster" else 0,
		"mp_max": 30 if enemy_type == "caster" else 0,
		"xp_reward": xp_reward + (level * 5),
		"gold_reward": gold_reward,
		"type": enemy_type,
		"is_player": false,
		"team": "enemy",
		"status_effects": [],
	}


func _scale_to_level(lv: int) -> Dictionary:
	var mult: float = 1.0 + (lv - 1) * 0.18
	return {
		"hp": int(base_hp * mult),
		"str": int(base_str * mult),
		"agi": int(base_agi * mult),
		"def": int(base_def * mult),
	}


func _load_or_fetch_description() -> void:
	var cache_key := "enemy_desc_%s_lv%d" % [enemy_name.to_lower().replace(" ", "_"), level]
	if GameState.has_flag(cache_key):
		_description = GameState.get_flag(cache_key)
		_description_loaded = true
		description_loaded.emit(_description)
		return
	# Fetch from AI
	var req_id := AIManager.describe_enemy(enemy_name, level, faction, region)
	AIManager.ai_response_received.connect(
		func(rid: String, text: String):
			if rid != req_id:
				return
			_description = text
			_description_loaded = true
			GameState.set_flag(cache_key, text)
			description_loaded.emit(text),
		CONNECT_ONE_SHOT
	)


func get_description() -> String:
	return _description if _description_loaded else "A hostile presence."


func get_combat_data() -> Dictionary:
	return combat_data.duplicate(true)


func update_hp_bar() -> void:
	if hp_bar:
		hp_bar.value = float(combat_data["hp"]) / float(combat_data["hp_max"]) * 100.0


func roll_loot() -> Array:
	var drops: Array = []
	for entry in loot_table:
		if randf() <= entry.get("chance", 0.1):
			drops.append(entry.get("item", {}))
	return drops

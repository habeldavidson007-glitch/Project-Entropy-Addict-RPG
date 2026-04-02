extends Node

## GameState — Autoload singleton
## Single source of truth for all game data. Add to AutoLoad as "GameState".

signal player_level_changed(old_level: int, new_level: int)
signal player_died
signal game_saved
signal game_loaded
signal flag_set(key: String, value: Variant)

const SAVE_PATH := "user://entropy_save.json"
const VERSION   := "1.0.0"

# ── Player ────────────────────────────────────────────────────────────────────

var player : Dictionary = {
	"name"          : "Survivor",
	"level"         : 1,
	"xp"            : 0,
	"xp_to_next"    : 100,
	"hp"            : 100,
	"hp_max"        : 100,
	"mp"            : 50,
	"mp_max"        : 50,
	"str"           : 5,
	"agi"           : 5,
	"int"           : 5,
	"vit"           : 5,
	"def"           : 3,
	"entropy"       : 0,       # starts at 0 — builds as world decays
	"entropy_max"   : 100,
	"gold"          : 0,
	"inventory"     : [],
	"equipped"      : {},
	"skills"        : [],
	"status_effects": [],
	"is_player"     : true,
	"team"          : "player",
	"total_kills"   : 0,
	"total_deaths"  : 0,
}

# ── World ─────────────────────────────────────────────────────────────────────

var world : Dictionary = {
	"current_area"     : "ashveld_flats",
	"day"              : 1,
	"time_of_day"      : "morning",
	"faction_rep"      : {},
	"discovered_areas" : [],
	"defeated_bosses"  : [],
}

# ── Flags ─────────────────────────────────────────────────────────────────────

var flags : Dictionary = {}


# ── Flag API ──────────────────────────────────────────────────────────────────

func set_flag(key: String, value: Variant) -> void:
	flags[key] = value
	flag_set.emit(key, value)


func get_flag(key: String, default: Variant = null) -> Variant:
	return flags.get(key, default)


func has_flag(key: String) -> bool:
	return flags.has(key)


# ── Player API ────────────────────────────────────────────────────────────────

func add_xp(amount: int) -> void:
	player["xp"] += amount
	while player["xp"] >= player["xp_to_next"]:
		_level_up()


func _level_up() -> void:
	var old : int = player["level"]
	player["xp"]       -= player["xp_to_next"]
	player["level"]    += 1
	player["xp_to_next"] = int(player["xp_to_next"] * 1.4)
	player["hp_max"]   += 10 + player["vit"]
	player["hp"]        = player["hp_max"]
	player["mp_max"]   += 5 + player["int"]
	player["mp"]        = player["mp_max"]
	player_level_changed.emit(old, player["level"])


func take_damage(amount: int) -> void:
	player["hp"] = max(0, player["hp"] - amount)
	if player["hp"] <= 0:
		player["total_deaths"] += 1
		player_died.emit()


func heal(amount: int) -> void:
	player["hp"] = min(player["hp_max"], player["hp"] + amount)


func add_entropy(amount: int) -> void:
	player["entropy"] = min(player["entropy_max"], player["entropy"] + amount)


func reduce_entropy(amount: int) -> void:
	player["entropy"] = max(0, player["entropy"] - amount)


func add_item(item: Dictionary) -> void:
	player["inventory"].append(item)


func remove_item(item_id: String) -> bool:
	for i in player["inventory"].size():
		if player["inventory"][i].get("id", "") == item_id:
			player["inventory"].remove_at(i)
			return true
	return false


# ── Faction API ───────────────────────────────────────────────────────────────

func set_faction_rep(faction: String, delta: int) -> void:
	var cur : int = world["faction_rep"].get(faction, 0)
	world["faction_rep"][faction] = clamp(cur + delta, -100, 100)


func get_faction_rep(faction: String) -> int:
	return world["faction_rep"].get(faction, 0)


# ── Save / Load ───────────────────────────────────────────────────────────────

func save() -> void:
	var data := {"version": VERSION, "player": player, "world": world, "flags": flags}
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data, "\t"))
		file.close()
		game_saved.emit()
		print("[GameState] Saved.")
	else:
		push_error("[GameState] Cannot open save file for writing.")


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return false
	var json := JSON.new()
	var err  := json.parse(file.file_get_as_string())
	file.close()
	if err != OK:
		push_error("[GameState] Save file corrupted.")
		return false
	var d : Dictionary = json.get_data()
	# Merge loaded data so new keys added to defaults still exist
	_merge_into(player, d.get("player", {}))
	_merge_into(world,  d.get("world",  {}))
	flags = d.get("flags", {})
	game_loaded.emit()
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(SAVE_PATH)


func reset() -> void:
	# Reinitialise to defaults without reloading the scene
	player = {
		"name": "Survivor", "level": 1, "xp": 0, "xp_to_next": 100,
		"hp": 100, "hp_max": 100, "mp": 50, "mp_max": 50,
		"str": 5, "agi": 5, "int": 5, "vit": 5, "def": 3,
		"entropy": 0, "entropy_max": 100, "gold": 0,
		"inventory": [], "equipped": {}, "skills": [], "status_effects": [],
		"is_player": true, "team": "player", "total_kills": 0, "total_deaths": 0,
	}
	world = {
		"current_area": "ashveld_flats", "day": 1, "time_of_day": "morning",
		"faction_rep": {}, "discovered_areas": [], "defeated_bosses": [],
	}
	flags = {}


# ── Helper ────────────────────────────────────────────────────────────────────

func _merge_into(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		target[key] = source[key]

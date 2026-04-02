extends Node

## GameState — Autoload singleton
## Holds all persistent game data: player, world state, flags, progress
## Saves/loads to disk automatically with optimized serialization

signal player_level_changed(old_level: int, new_level: int)
signal player_died
signal game_saved
signal game_loaded
signal flag_set(flag_name: String, value: Variant)

const SAVE_PATH: String = "user://save_data.json"
const VERSION: String = "1.0.0"

# ─── Player Data ──────────────────────────────────────────────────────────────

var player: Dictionary = {
	"name": "Survivor",
	"level": 1,
	"xp": 0,
	"xp_to_next": 100,
	"hp": 100,
	"hp_max": 100,
	"mp": 50,
	"mp_max": 50,
	"str": 5,
	"agi": 5,
	"int": 5,
	"vit": 5,
	"entropy": 0,
	"entropy_max": 100,
	"gold": 0,
	"inventory": [],
	"equipped": {},
	"skills": [],
	"status_effects": [],
	"location": "prologue",
	"total_kills": 0,
	"total_deaths": 0,
}

# ─── World State ──────────────────────────────────────────────────────────────

var world: Dictionary = {
	"current_area": "prologue",
	"day": 1,
	"time_of_day": "morning",
	"faction_rep": {},
	"discovered_areas": [],
	"defeated_bosses": [],
}

# ─── Story Flags ──────────────────────────────────────────────────────────────

var flags: Dictionary = {}


# ─── Public API ───────────────────────────────────────────────────────────────

func set_flag(key: String, value: Variant) -> void:
	flags[key] = value
	flag_set.emit(key, value)


func get_flag(key: String, default: Variant = null) -> Variant:
	return flags.get(key, default)


func has_flag(key: String) -> bool:
	return flags.has(key)


func add_xp(amount: int) -> void:
	player.xp += amount
	while player.xp >= player.xp_to_next:
		_level_up()


func _level_up() -> void:
	var old_level: int = player.level
	player.xp -= player.xp_to_next
	player.level += 1
	player.xp_to_next = int(player.xp_to_next * 1.4)
	player.hp_max += 10 + player.vit
	player.hp = player.hp_max
	player.mp_max += 5 + player.int
	player_level_changed.emit(old_level, player.level)


func take_damage(amount: int) -> void:
	player.hp = max(0, player.hp - amount)
	if player.hp <= 0:
		player.total_deaths += 1
		player_died.emit()


func heal(amount: int) -> void:
	player.hp = min(player.hp_max, player.hp + amount)


func add_entropy(amount: int) -> void:
	player.entropy = min(player.entropy_max, player.entropy + amount)


func reduce_entropy(amount: int) -> void:
	player.entropy = max(0, player.entropy - amount)


func add_item(item: Dictionary) -> void:
	player.inventory.append(item)


func remove_item(item_id: String) -> bool:
	for i in range(player.inventory.size() - 1, -1, -1):
		if player.inventory[i].get("id") == item_id:
			player.inventory.remove_at(i)
			return true
	return false


func set_faction_rep(faction: String, delta: int) -> void:
	var current: int = world.faction_rep.get(faction, 0)
	world.faction_rep[faction] = clamp(current + delta, -100, 100)


func get_faction_rep(faction: String) -> int:
	return world.faction_rep.get(faction, 0)


# ─── Save / Load ──────────────────────────────────────────────────────────────

func save() -> void:
	var data: Dictionary = {
		"version": VERSION,
		"player": player,
		"world": world,
		"flags": flags,
	}
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()
		game_saved.emit()
	else:
		push_error("[GameState] Could not open save file for writing.")


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		push_error("[GameState] Could not open save file for reading.")
		return false
	var json: JSON = JSON.new()
	var err: Error = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("[GameState] Save file corrupted.")
		return false
	var data: Dictionary = json.get_data() as Dictionary
	if not data.is_empty():
		_merge_player_data(data.get("player", {}))
		_merge_world_data(data.get("world", {}))
		flags = data.get("flags", {})
	game_loaded.emit()
	return true


func _merge_player_data(data: Dictionary) -> void:
	for key in data:
		if player.has(key):
			player[key] = data[key]


func _merge_world_data(data: Dictionary) -> void:
	for key in data:
		if world.has(key):
			if world[key] is Dictionary and data[key] is Dictionary:
				world[key].merge(data[key], true)
			else:
				world[key] = data[key]


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func reset() -> void:
	player = {
		"name": "Survivor",
		"level": 1,
		"xp": 0,
		"xp_to_next": 100,
		"hp": 100,
		"hp_max": 100,
		"mp": 50,
		"mp_max": 50,
		"str": 5,
		"agi": 5,
		"int": 5,
		"vit": 5,
		"entropy": 0,
		"entropy_max": 100,
		"gold": 0,
		"inventory": [],
		"equipped": {},
		"skills": [],
		"status_effects": [],
		"location": "prologue",
		"total_kills": 0,
		"total_deaths": 0,
	}
	world = {
		"current_area": "prologue",
		"day": 1,
		"time_of_day": "morning",
		"faction_rep": {},
		"discovered_areas": [],
		"defeated_bosses": [],
	}
	flags.clear()

extends Node

## LootSystem — Autoload singleton
## Generates tiered item drops after combat. Add to AutoLoad as "LootSystem".

signal loot_generated(items: Array)

const POOL : Dictionary = {
	1: [
		{"id": "bandage",     "name": "Torn Bandage",      "type": "consumable", "slot": "", "tier": 1, "effect": "heal",          "value": 20},
		{"id": "scrap",       "name": "Scrap Metal",        "type": "misc",       "slot": "", "tier": 1},
		{"id": "rust_blade",  "name": "Rust Blade",         "type": "weapon",     "slot": "weapon", "tier": 1, "str_bonus": 2},
	],
	2: [
		{"id": "stimpack",    "name": "Stimpack",           "type": "consumable", "slot": "", "tier": 2, "effect": "heal",          "value": 40},
		{"id": "en_shard",    "name": "Entropy Shard",      "type": "consumable", "slot": "", "tier": 2, "effect": "reduce_entropy","value": 20},
		{"id": "iron_armor",  "name": "Iron Plate",         "type": "armor",      "slot": "armor", "tier": 2, "def_bonus": 3},
		{"id": "cold_blade",  "name": "Cold Iron Blade",    "type": "weapon",     "slot": "weapon","tier": 2, "str_bonus": 4},
	],
	3: [
		{"id": "focus_cap",   "name": "Focus Capsule",      "type": "consumable", "slot": "", "tier": 3, "effect": "restore_mp",   "value": 30},
		{"id": "ridged_legs", "name": "Ridged Greaves",     "type": "armor",      "slot": "legs","tier": 3, "def_bonus": 4},
		{"id": "en_lens",     "name": "Entropy Lens",       "type": "accessory",  "slot": "accessory", "tier": 3},
	],
}


func generate(enemy_level: int) -> Array:
	if randf() > 0.40:
		return []
	var tier  := clamp(ceili(float(enemy_level) / 2.0), 1, 3)
	var pool  := POOL.get(tier, []) as Array
	if pool.is_empty():
		return []
	var item  := (pool[randi() % pool.size()] as Dictionary).duplicate()
	item["id"] = "%s_%d" % [item["id"], Time.get_ticks_msec()]
	var drops := [item]
	if randf() < 0.15 and pool.size() > 1:
		var bonus := (pool[randi() % pool.size()] as Dictionary).duplicate()
		bonus["id"] = "%s_%d" % [bonus["id"], Time.get_ticks_msec() + 1]
		drops.append(bonus)
	loot_generated.emit(drops)
	return drops


func give_to_player(drops: Array) -> void:
	for item in drops:
		GameState.add_item(item)

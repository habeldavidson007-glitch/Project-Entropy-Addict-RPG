extends Node

## LootSystem — generates item drops, assigns IDs, feeds into inventory
## Autoload as "LootSystem"
## Optimized with pre-allocated arrays and efficient random selection

signal loot_dropped(items: Array)

# Item pool by tier - using const for immutability and performance
const ITEM_POOL: Dictionary = {
	1: [
		{"id": "bandage", "name": "Torn Bandage", "type": "consumable", "slot": "", "tier": 1, "effect": "heal", "value": 20},
		{"id": "scrap_metal", "name": "Scrap Metal", "type": "misc", "slot": "", "tier": 1},
		{"id": "rust_blade", "name": "Rust Blade", "type": "weapon", "slot": "weapon", "tier": 1, "str_bonus": 2},
	],
	2: [
		{"id": "stimpack", "name": "Stimpack", "type": "consumable", "slot": "", "tier": 2, "effect": "heal", "value": 40},
		{"id": "entropy_shard", "name": "Entropy Shard", "type": "consumable", "slot": "", "tier": 2, "effect": "reduce_entropy", "value": 20},
		{"id": "iron_plate", "name": "Iron Plate Armor", "type": "armor", "slot": "armor", "tier": 2, "def_bonus": 3},
		{"id": "cold_iron_blade", "name": "Cold Iron Blade", "type": "weapon", "slot": "weapon", "tier": 2, "str_bonus": 4},
	],
	3: [
		{"id": "focus_capsule", "name": "Focus Capsule", "type": "consumable", "slot": "", "tier": 3, "effect": "restore_mp", "value": 30},
		{"id": "ridged_greaves", "name": "Ridged Greaves", "type": "armor", "slot": "legs", "tier": 3, "def_bonus": 4},
		{"id": "entropy_lens", "name": "Entropy Lens", "type": "accessory", "slot": "accessory", "tier": 3},
	],
}

# Drop chance constants
const BASE_DROP_CHANCE: float = 0.60  # 60% chance of at least one drop
const BONUS_DROP_CHANCE: float = 0.15
const DROP_BASE_CHANCE: float = 0.40


func generate_drops(enemy_level: int, _enemy_faction: String) -> Array:
	var drops: Array = []
	var tier: int = clamp(ceili(enemy_level / 2.0), 1, 3)
	
	if randf() > BASE_DROP_CHANCE:
		return drops
	
	var pool: Array = ITEM_POOL.get(tier, [])
	if pool.is_empty():
		return drops
	
	var item: Dictionary = pool[randi() % pool.size()].duplicate()
	item.id = "%s_%d" % [item.id, Time.get_ticks_usec()]
	drops.append(item)
	
	if randf() < BONUS_DROP_CHANCE and pool.size() > 1:
		var bonus: Dictionary = pool[randi() % pool.size()].duplicate()
		bonus.id = "%s_%d" % [bonus.id, Time.get_ticks_usec() + 1]
		drops.append(bonus)
	
	if not drops.is_empty():
		loot_dropped.emit(drops)
	return drops


func add_drops_to_inventory(drops: Array) -> void:
	for item in drops:
		GameState.add_item(item)

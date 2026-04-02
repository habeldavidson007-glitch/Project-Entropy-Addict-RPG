extends Node

## LootSystem — Autoload singleton
## Generates random loot based on region and difficulty.
## Add to Project Settings > Autoload as "LootSystem"

signal loot_generated(item: Dictionary)

# ── Loot Tables ───────────────────────────────────────────────────────────────

const LOOT_TABLES = {
	"ashveld_flats": [
		{"name": "Rusty Dagger", "type": "weapon", "rarity": "common", "value": 5, "min_dmg": 2, "max_dmg": 4},
		{"name": "Tattered Cloth", "type": "material", "rarity": "common", "value": 2},
		{"name": "Small Health Potion", "type": "consumable", "rarity": "uncommon", "value": 10, "heal": 20},
		{"name": "Wolf Pelt", "type": "material", "rarity": "common", "value": 3},
		{"name": "Iron Shard", "type": "material", "rarity": "common", "value": 1}
	],
	"whispering_woods": [
		{"name": "Wooden Bow", "type": "weapon", "rarity": "common", "value": 8, "min_dmg": 3, "max_dmg": 6},
		{"name": "Herb Bundle", "type": "consumable", "rarity": "uncommon", "value": 12, "heal": 35},
		{"name": "Ancient Leaf", "type": "material", "rarity": "rare", "value": 25},
		{"name": "Spider Silk", "type": "material", "rarity": "uncommon", "value": 8}
	],
	"default": [
		{"name": "Scrap Metal", "type": "material", "rarity": "common", "value": 1},
		{"name": "Old Coin", "type": "currency", "rarity": "common", "value": 5},
		{"name": "Mystery Dust", "type": "material", "rarity": "common", "value": 1}
	]
}

const RARITY_WEIGHTS = {
	"common": 70,
	"uncommon": 20,
	"rare": 8,
	"epic": 2
}

# ── Initialization ────────────────────────────────────────────────────────────

func _ready() -> void:
	print("[LootSystem] Ready. Loaded %d regions." % LOOT_TABLES.size())


# ── Public API ────────────────────────────────────────────────────────────────

## Generate a single item based on region and difficulty multiplier
func generate_loot(region: String, difficulty: int = 1) -> Dictionary:
	var table = LOOT_TABLES.get(region, LOOT_TABLES["default"])
	if table.is_empty():
		table = LOOT_TABLES["default"]
	
	# Pick random template
	var template = table[randi() % table.size()]
	
	# Create instance
	var item = template.duplicate()
	item["id"] = "%s_%d_%d" % [item["name"].to_lower().replace(" ", "_"), Time.get_ticks_msec(), randi() % 9999]
	item["quantity"] = max(1, randi_range(1, 1 + difficulty))
	
	# Apply difficulty scaling to value
	if item.has("value"):
		item["value"] = item["value"] * difficulty
	
	loot_generated.emit(item)
	return item


## Generate a stack of items (e.g., for chest rewards)
func generate_loot_batch(region: String, count: int, difficulty: int = 1) -> Array[Dictionary]:
	var batch: Array[Dictionary] = []
	for i in range(count):
		batch.append(generate_loot(region, difficulty))
	return batch


## Generate gold reward based on level
func generate_gold_reward(level: int) -> Dictionary:
	var base := level * 10
	var variance := randi() % 20
	var amount := base + variance
	
	return {
		"name": "Gold",
		"type": "currency",
		"rarity": "common",
		"value": 1,
		"quantity": amount,
		"id": "gold_%d" % Time.get_ticks_msec()
	}


## Get description from AI (if available)
func get_item_description(item: Dictionary) -> String:
	if not AIManager:
		return "A mysterious item."
	
	var template_key = "loot_desc"
	var params = {
		"item_name": item.get("name", "Unknown"),
		"tier": _calculate_tier(item.get("rarity", "common")),
		"type": item.get("type", "misc")
	}
	
	return AIManager.ask_template(template_key, params)


# ── Helpers ───────────────────────────────────────────────────────────────────

func _calculate_tier(rarity: String) -> int:
	match rarity:
		"common": return 1
		"uncommon": return 2
		"rare": return 3
		"epic": return 4
		"legendary": return 5
		_: return 1


func _get_rarity_by_weight() -> String:
	var roll := randi() % 100
	var cumulative := 0
	
	for rarity in ["common", "uncommon", "rare", "epic"]:
		cumulative += RARITY_WEIGHTS[rarity]
		if roll < cumulative:
			return rarity
	
	return "common"
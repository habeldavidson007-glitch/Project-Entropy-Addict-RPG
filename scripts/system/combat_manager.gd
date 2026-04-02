extends Node

## CombatManager — Autoload singleton
## Handles turn-based combat logic, initiative, and resolution.

signal combat_started
signal combat_ended(victory: bool)
signal turn_changed(entity_name: String)
signal damage_dealed(target: String, amount: int)

var _is_in_combat: bool = false
var _combatants: Array[Dictionary] = []
var _turn_order: Array[Dictionary] = []
var _current_turn_index: int = 0

func _ready() -> void:
	print("[CombatManager] Ready.")

func is_in_combat() -> bool:
	return _is_in_combat

func start_combat(enemies: Array[Dictionary]) -> void:
	if _is_in_combat:
		push_warning("[CombatManager] Combat already active.")
		return
	
	_is_in_combat = true
	_combatants.clear()
	_combatants.append(GameState.player.duplicate())
	for enemy in enemies:
		_combatants.append(enemy)
	
	_calculate_initiative()
	combat_started.emit()
	_next_turn()

func _calculate_initiative() -> void:
	_turn_order = _combatants.duplicate()
	# Simple sort by AGI (descending)
	_turn_order.sort_custom(func(a, b): return a.get("agi", 0) > b.get("agi", 0))
	_current_turn_index = 0

func _next_turn() -> void:
	if _turn_order.is_empty():
		end_combat(true)
		return
	
	var current_entity = _turn_order[_current_turn_index]
	turn_changed.emit(current_entity.get("name", "Unknown"))
	
	if current_entity.get("is_player", false):
		# Player turn: wait for input (handled by UI)
		pass
	else:
		# Enemy turn: simple AI delay then attack
		await get_tree().create_timer(1.0).timeout
		_enemy_attack(current_entity)

func player_action(action: String, target_idx: int = 0) -> void:
	if not _is_in_combat: return
	if _current_turn_index >= _turn_order.size(): return
	
	var actor = _turn_order[_current_turn_index]
	if not actor.get("is_player", false):
		push_warning("[CombatManager] Not player's turn.")
		return
	
	if action == "attack":
		var target = _get_first_enemy()
		if target:
			var dmg = max(1, actor.get("str", 5) - target.get("def", 0))
			target["hp"] -= dmg
			damage_dealed.emit(target.get("name", "Enemy"), dmg)
			if target["hp"] <= 0:
				_remove_combatant(target)
	
	_current_turn_index = (_current_turn_index + 1) % _turn_order.size()
	_check_victory_condition()
	if _is_in_combat:
		_next_turn()

func _enemy_attack(enemy: Dictionary) -> void:
	if not _is_in_combat: return
	var player_ref = GameState.player
	var dmg = max(1, enemy.get("str", 3) - player_ref.get("def", 0))
	GameState.take_damage(dmg)
	damage_dealed.emit("Player", dmg)
	
	if GameState.player["hp"] <= 0:
		end_combat(false) # Defeat
	else:
		_current_turn_index = (_current_turn_index + 1) % _turn_order.size()
		_next_turn()

func _get_first_enemy() -> Dictionary:
	for c in _turn_order:
		if not c.get("is_player", false):
			return c
	return {}

func _remove_combatant(entity: Dictionary) -> void:
	_turn_order.erase(entity)
	_combatants.erase(entity)
	if _turn_order.is_empty():
		end_combat(true)

func _check_victory_condition() -> void:
	var enemies_left = 0
	for c in _combatants:
		if not c.get("is_player", false):
			enemies_left += 1
	if enemies_left == 0:
		end_combat(true)

func end_combat(victory: bool) -> void:
	_is_in_combat = false
	_combatants.clear()
	_turn_order.clear()
	combat_ended.emit(victory)
	if victory:
		print("[CombatManager] Victory!")
	else:
		print("[CombatManager] Defeated...")
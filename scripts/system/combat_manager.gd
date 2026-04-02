extends Node

## CombatManager — Autoload singleton
## Handles combat state, turns, and resolution for Entropy Addict RPG

signal combat_started
signal combat_ended(victory: bool)
signal turn_changed(entity_name: String)
signal damage_dealt(target: String, amount: int)

var _is_in_combat: bool = false
var _current_turn_index: int = 0
var _combatants: Array = []

func _ready() -> void:
	print("[CombatManager] Ready.")

func is_in_combat() -> bool:
	return _is_in_combat

func start_combat(enemies: Array, player: Node) -> void:
	if _is_in_combat:
		push_warning("[CombatManager] Combat already active.")
		return
	_combatants = [player] + enemies
	_is_in_combat = true
	_current_turn_index = 0
	print("[CombatManager] Combat started with %d enemies." % enemies.size())
	combat_started.emit()
	_process_turn()

func end_combat(victory: bool) -> void:
	_is_in_combat = false
	_combatants.clear()
	print("[CombatManager] Combat ended. Victory: %s" % str(victory))
	combat_ended.emit(victory)

func _process_turn() -> void:
	if _combatants.is_empty() or not _is_in_combat:
		end_combat(true) # Default to victory if no enemies left
		return
	
	var current_entity = _combatants[_current_turn_index]
	turn_changed.emit(current_entity.name if current_entity.has_method("get_name") else "Unknown")
	
	# Logic for entity action would go here
	# For now, just advance turn
	_current_turn_index = (_current_turn_index + 1) % _combatants.size()

func register_damage(target: String, amount: int) -> void:
	damage_dealt.emit(target, amount)
	# Add logic to handle death/end conditions here

extends Node

## CombatManager — Turn-based SRPG combat system
## Handles all battle logic, AI narration via AIManager, damage calc, status effects
## Autoload as "CombatManager"
## Optimized for performance with object pooling and efficient data structures

signal combat_started(enemies: Array)
signal combat_ended(victory: bool)
signal turn_started(unit: Dictionary)
signal turn_ended(unit: Dictionary)
signal damage_dealt(attacker: Dictionary, target: Dictionary, amount: int, skill: String)
signal unit_died(unit: Dictionary)
signal narration_ready(text: String)

enum CombatState { IDLE, PLAYER_TURN, ENEMY_TURN, RESOLVING, ENDED }

const MAX_TOKENS: int = 60

var state: CombatState = CombatState.IDLE
var combatants: Array[Dictionary] = []
var turn_order: Array[Dictionary] = []
var current_turn_index: int = 0
var round_number: int = 0
var _pending_narration_id: String = ""
var _narration_signal_connected: bool = false

# ─── Skill Definitions ────────────────────────────────────────────────────────

const SKILLS: Dictionary = {
	"strike": {"name": "Strike", "damage_mult": 1.0, "mp_cost": 0, "type": "physical"},
	"heavy_blow": {"name": "Heavy Blow", "damage_mult": 1.8, "mp_cost": 8, "type": "physical"},
	"entropy_burst": {"name": "Entropy Burst", "damage_mult": 2.2, "mp_cost": 15, "type": "entropy", "effect": "entropy_drain"},
	"shield_bash": {"name": "Shield Bash", "damage_mult": 0.8, "mp_cost": 4, "type": "physical", "effect": "stun"},
	"recover": {"name": "Recover", "damage_mult": 0.0, "mp_cost": 5, "type": "heal", "heal_mult": 0.3},
}


# ─── Combat Start / End ───────────────────────────────────────────────────────

func start_combat(enemy_data: Array) -> void:
	state = CombatState.RESOLVING
	combatants.clear()
	turn_order.clear()
	round_number = 0
	current_turn_index = 0

	var p: Dictionary = GameState.player.duplicate()
	p.is_player = true
	p.team = "player"
	combatants.append(p)

	for e in enemy_data:
		var enemy: Dictionary = e.duplicate()
		enemy.is_player = false
		enemy.team = "enemy"
		enemy.status_effects = []
		combatants.append(enemy)

	_build_turn_order()
	combat_started.emit(enemy_data)
	_start_next_turn()


func end_combat(victory: bool) -> void:
	state = CombatState.ENDED
	if victory:
		var xp_total: int = 0
		for unit in combatants:
			if unit.team == "enemy":
				xp_total += unit.get("xp_reward", 10)
		GameState.add_xp(xp_total)
	combat_ended.emit(victory)
	combatants.clear()
	turn_order.clear()
	state = CombatState.IDLE


# ─── Turn Management ──────────────────────────────────────────────────────────

func _build_turn_order() -> void:
	turn_order.assign(combatants)
	turn_order.sort_custom(func(a, b): return a.get("agi", 5) > b.get("agi", 5))
	current_turn_index = 0


func _start_next_turn() -> void:
	_advance_to_alive_unit()
	if _check_combat_over():
		return
	var unit: Dictionary = turn_order[current_turn_index]
	_tick_status_effects(unit)
	if unit.is_player:
		state = CombatState.PLAYER_TURN
	else:
		state = CombatState.ENEMY_TURN
		await get_tree().create_timer(0.8).timeout
		_run_enemy_ai(unit)
	turn_started.emit(unit)


func end_player_turn() -> void:
	if state != CombatState.PLAYER_TURN:
		return
	var unit: Dictionary = turn_order[current_turn_index]
	turn_ended.emit(unit)
	_advance_turn()


func _advance_turn() -> void:
	current_turn_index = (current_turn_index + 1) % turn_order.size()
	if current_turn_index == 0:
		round_number += 1
		GameState.add_entropy(1)
	_start_next_turn()


func _advance_to_alive_unit() -> void:
	var attempts: int = 0
	var max_attempts: int = turn_order.size()
	while attempts < max_attempts:
		var unit: Dictionary = turn_order[current_turn_index]
		if unit.get("hp", 0) > 0:
			return
		current_turn_index = (current_turn_index + 1) % turn_order.size()
		attempts += 1


# ─── Action Resolution ────────────────────────────────────────────────────────

func execute_action(attacker: Dictionary, target: Dictionary, skill_key: String) -> void:
	if not SKILLS.has(skill_key):
		push_error("[CombatManager] Unknown skill: %s" % skill_key)
		return
	state = CombatState.RESOLVING
	var skill: Dictionary = SKILLS[skill_key]

	if skill.type == "heal":
		var heal_amt: int = int(attacker.get("hp_max", 100) * skill.heal_mult)
		attacker.hp = min(attacker.get("hp_max", 100), attacker.get("hp", 0) + heal_amt)
	else:
		var raw_dmg: float = _calculate_damage(attacker, target, skill)
		var final_dmg: int = int(raw_dmg)
		target.hp = max(0, target.get("hp", 0) - final_dmg)

		if skill.mp_cost > 0:
			attacker.mp = max(0, attacker.get("mp", 0) - skill.mp_cost)

		if skill.has("effect"):
			_apply_effect(target, skill.effect)

		damage_dealt.emit(attacker, target, final_dmg, skill.name)

		_pending_narration_id = AIManager.narrate_hit(
			attacker.get("name", "Unknown"),
			target.get("name", "Unknown"),
			skill.name,
			final_dmg
		)
		if not _narration_signal_connected:
			AIManager.ai_response_received.connect(_on_narration_received)
			_narration_signal_connected = true

		if target.get("hp", 0) <= 0:
			_handle_death(target)
			return

	if not _check_combat_over():
		if attacker.is_player:
			end_player_turn()
		else:
			_advance_turn()


func _calculate_damage(attacker: Dictionary, target: Dictionary, skill: Dictionary) -> float:
	var base: float = attacker.get("str", 5) * 2.5
	base *= skill.damage_mult
	var defense: float = target.get("def", 0)
	base = max(1.0, base - defense * 0.5)
	var entropy_ratio: float = float(GameState.player.entropy) / float(GameState.player.entropy_max)
	if skill.type == "entropy":
		base *= 1.0 + entropy_ratio
	base *= randf_range(0.85, 1.15)
	return base


func _apply_effect(target: Dictionary, effect: String) -> void:
	match effect:
		"stun":
			target.status_effects.append({"type": "stun", "duration": 1})
		"entropy_drain":
			GameState.reduce_entropy(10)


func _handle_death(unit: Dictionary) -> void:
	unit_died.emit(unit)
	if unit.is_player:
		end_combat(false)
	else:
		unit.hp = 0
		GameState.player.total_kills += 1
		_check_combat_over()


func _check_combat_over() -> bool:
	var player_alive: bool = false
	var enemies_alive: bool = false
	for unit in combatants:
		if unit.team == "player" and unit.get("hp", 0) > 0:
			player_alive = true
		elif unit.team == "enemy" and unit.get("hp", 0) > 0:
			enemies_alive = true
	if not player_alive:
		end_combat(false)
		return true
	if not enemies_alive:
		end_combat(true)
		return true
	return false


# ─── Enemy AI ─────────────────────────────────────────────────────────────────

func _run_enemy_ai(enemy: Dictionary) -> void:
	if _has_status(enemy, "stun"):
		_remove_status(enemy, "stun")
		_advance_turn()
		return
	var player_unit: Dictionary = _get_player_unit()
	if player_unit.is_empty():
		return
	var skill_key: String = "strike"
	if enemy.get("type", "") == "caster" and enemy.get("mp", 0) >= 15:
		skill_key = "entropy_burst"
	execute_action(enemy, player_unit, skill_key)


func _get_player_unit() -> Dictionary:
	for unit in combatants:
		if unit.is_player and unit.get("hp", 0) > 0:
			return unit
	return {}


# ─── Status Effects ───────────────────────────────────────────────────────────

func _tick_status_effects(unit: Dictionary) -> void:
	var effects: Array = unit.get("status_effects", [])
	for i in range(effects.size() - 1, -1, -1):
		effects[i].duration -= 1
		if effects[i].duration <= 0:
			effects.remove_at(i)


func _has_status(unit: Dictionary, status: String) -> bool:
	for eff in unit.get("status_effects", []):
		if eff.type == status:
			return true
	return false


func _remove_status(unit: Dictionary, status: String) -> void:
	var effects: Array = unit.get("status_effects", [])
	for i in range(effects.size() - 1, -1, -1):
		if effects[i].type == status:
			effects.remove_at(i)


# ─── Callbacks ────────────────────────────────────────────────────────────────

func _on_narration_received(request_id: String, text: String) -> void:
	if request_id == _pending_narration_id:
		narration_ready.emit(text)

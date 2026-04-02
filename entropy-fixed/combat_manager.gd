extends Node

## CombatManager — Autoload singleton
## Turn-based SRPG engine. Add to AutoLoad as "CombatManager".

signal combat_started(enemies: Array)
signal combat_ended(victory: bool)
signal turn_started(unit: Dictionary)
signal turn_ended(unit: Dictionary)
signal damage_dealt(attacker: Dictionary, target: Dictionary, amount: int, skill_name: String)
signal unit_died(unit: Dictionary)
signal narration_ready(text: String)

enum CombatState { IDLE, PLAYER_TURN, ENEMY_TURN, RESOLVING, ENDED }

const SKILLS : Dictionary = {
	"strike"       : {"name": "Strike",        "damage_mult": 1.0, "mp_cost": 0,  "type": "physical"},
	"heavy_blow"   : {"name": "Heavy Blow",     "damage_mult": 1.8, "mp_cost": 8,  "type": "physical"},
	"entropy_burst": {"name": "Entropy Burst",  "damage_mult": 2.2, "mp_cost": 15, "type": "entropy", "effect": "entropy_drain"},
	"shield_bash"  : {"name": "Shield Bash",    "damage_mult": 0.8, "mp_cost": 4,  "type": "physical","effect": "stun"},
	"recover"      : {"name": "Recover",        "damage_mult": 0.0, "mp_cost": 5,  "type": "heal",    "heal_ratio": 0.3},
}

var state               : CombatState  = CombatState.IDLE
var combatants          : Array        = []
var turn_order          : Array        = []
var current_turn_index  : int          = 0
var round_number        : int          = 0
var _narration_req_id   : String       = ""


# ── Start / End ───────────────────────────────────────────────────────────────

func start_combat(enemy_data: Array) -> void:
	state          = CombatState.RESOLVING
	combatants.clear()
	round_number   = 0

	# Player unit from GameState
	var p          := GameState.player.duplicate(true)
	p["is_player"]  = true
	p["team"]       = "player"
	combatants.append(p)

	for e in enemy_data:
		var en             := e.duplicate(true)
		en["is_player"]     = false
		en["team"]          = "enemy"
		en["status_effects"] = []
		en.get_or_add("hp_max", en.get("hp", 30))
		en.get_or_add("mp",     0)
		en.get_or_add("mp_max", 0)
		combatants.append(en)

	_build_turn_order()
	combat_started.emit(enemy_data)
	_next_turn()


func end_combat(victory: bool) -> void:
	state = CombatState.ENDED
	if victory:
		var xp := 0
		for u in combatants:
			if u["team"] == "enemy":
				xp += u.get("xp_reward", 10)
				# Generate loot per enemy
				var drops := LootSystem.generate(u.get("level", 1))
				LootSystem.give_to_player(drops)
		GameState.add_xp(xp)
		# Sync player HP/MP back
		var pu := _get_player_unit()
		if not pu.is_empty():
			GameState.player["hp"] = pu.get("hp", GameState.player["hp"])
			GameState.player["mp"] = pu.get("mp", GameState.player["mp"])
	combat_ended.emit(victory)
	combatants.clear()
	turn_order.clear()
	state = CombatState.IDLE


# ── Turn Management ───────────────────────────────────────────────────────────

func _build_turn_order() -> void:
	turn_order = combatants.duplicate()
	turn_order.sort_custom(func(a, b): return a.get("agi", 5) > b.get("agi", 5))
	current_turn_index = 0


func _next_turn() -> void:
	_skip_dead()
	if _check_over():
		return
	round_number += 1 if current_turn_index == 0 else 0
	var unit : Dictionary = turn_order[current_turn_index]
	_tick_status(unit)
	if unit["is_player"]:
		state = CombatState.PLAYER_TURN
	else:
		state = CombatState.ENEMY_TURN
		get_tree().create_timer(0.7).timeout.connect(func(): _enemy_ai(unit), CONNECT_ONE_SHOT)
	turn_started.emit(unit)


func _advance() -> void:
	var prev := turn_order[current_turn_index]
	turn_ended.emit(prev)
	current_turn_index = (current_turn_index + 1) % turn_order.size()
	if current_turn_index == 0:
		round_number += 1
		GameState.add_entropy(1)
	_next_turn()


func end_player_turn() -> void:
	if state != CombatState.PLAYER_TURN:
		return
	_advance()


func _skip_dead() -> void:
	var checked := 0
	while checked < turn_order.size():
		if turn_order[current_turn_index].get("hp", 0) > 0:
			return
		current_turn_index = (current_turn_index + 1) % turn_order.size()
		checked += 1


# ── Action Execution ──────────────────────────────────────────────────────────

func execute_action(attacker: Dictionary, target: Dictionary, skill_key: String) -> void:
	if not SKILLS.has(skill_key):
		push_error("[CombatManager] Unknown skill: " + skill_key)
		return
	state = CombatState.RESOLVING
	var skill : Dictionary = SKILLS[skill_key]

	if skill["type"] == "heal":
		var amt := int(attacker.get("hp_max", 100) * skill.get("heal_ratio", 0.3))
		attacker["hp"] = min(attacker.get("hp_max", 100), attacker.get("hp", 0) + amt)
		if attacker.get("mp", 0) >= skill["mp_cost"]:
			attacker["mp"] -= skill["mp_cost"]
	else:
		if attacker.get("mp", 99) < skill["mp_cost"]:
			# Not enough MP — fall back to strike
			skill = SKILLS["strike"]
		var dmg := _calc_damage(attacker, target, skill)
		target["hp"] = max(0, target.get("hp", 0) - dmg)
		attacker["mp"] = max(0, attacker.get("mp", 0) - skill["mp_cost"])
		if skill.has("effect"):
			_apply_effect(target, skill["effect"])
		damage_dealt.emit(attacker, target, dmg, skill["name"])
		# AI narration — non-blocking
		_narration_req_id = AIManager.narrate_hit(
			attacker.get("name","?"), target.get("name","?"), skill["name"], dmg
		)
		AIManager.ai_response_received.connect(_on_narration, CONNECT_ONE_SHOT)
		if target.get("hp", 0) <= 0:
			_handle_death(target)
			return

	if not _check_over():
		if attacker.get("is_player", false):
			_advance()
		else:
			_advance()


func _calc_damage(att: Dictionary, tgt: Dictionary, skill: Dictionary) -> int:
	var base  : float = att.get("str", 5) * 2.5 * skill["damage_mult"]
	var def   : float = tgt.get("def", 0) * 0.5
	base = max(1.0, base - def)
	if skill["type"] == "entropy":
		var ratio : float = float(GameState.player["entropy"]) / float(GameState.player["entropy_max"])
		base *= 1.0 + ratio * 0.5
	base *= randf_range(0.85, 1.15)
	return int(base)


func _apply_effect(target: Dictionary, effect: String) -> void:
	match effect:
		"stun":
			target.get_or_add("status_effects", []).append({"type": "stun", "duration": 1})
		"entropy_drain":
			GameState.reduce_entropy(8)


func _handle_death(unit: Dictionary) -> void:
	unit_died.emit(unit)
	if unit.get("is_player", false):
		end_combat(false)
	else:
		unit["hp"] = 0
		GameState.player["total_kills"] += 1
		_check_over()


func _check_over() -> bool:
	var player_alive := false
	var enemy_alive  := false
	for u in combatants:
		if u["team"] == "player" and u.get("hp", 0) > 0:
			player_alive = true
		elif u["team"] == "enemy" and u.get("hp", 0) > 0:
			enemy_alive = true
	if not player_alive:
		end_combat(false)
		return true
	if not enemy_alive:
		end_combat(true)
		return true
	return false


# ── Enemy AI ──────────────────────────────────────────────────────────────────

func _enemy_ai(enemy: Dictionary) -> void:
	if state == CombatState.ENDED:
		return
	# Stunned — skip turn
	if _has_effect(enemy, "stun"):
		_remove_effect(enemy, "stun")
		_advance()
		return
	var player_unit := _get_player_unit()
	if player_unit.is_empty():
		return
	var sk := "entropy_burst" if (enemy.get("type","") == "caster" and enemy.get("mp",0) >= 15) else "strike"
	execute_action(enemy, player_unit, sk)


func _get_player_unit() -> Dictionary:
	for u in combatants:
		if u.get("is_player", false) and u.get("hp", 0) > 0:
			return u
	return {}


# ── Status Effects ────────────────────────────────────────────────────────────

func _tick_status(unit: Dictionary) -> void:
	var effs : Array = unit.get("status_effects", [])
	for i in range(effs.size() - 1, -1, -1):
		effs[i]["duration"] -= 1
		if effs[i]["duration"] <= 0:
			effs.remove_at(i)


func _has_effect(unit: Dictionary, eff: String) -> bool:
	for e in unit.get("status_effects", []):
		if e["type"] == eff:
			return true
	return false


func _remove_effect(unit: Dictionary, eff: String) -> void:
	var effs : Array = unit.get("status_effects", [])
	for i in range(effs.size() - 1, -1, -1):
		if effs[i]["type"] == eff:
			effs.remove_at(i)


# ── Callbacks ─────────────────────────────────────────────────────────────────

func _on_narration(req_id: String, text: String) -> void:
	if req_id == _narration_req_id:
		narration_ready.emit(text)

extends CharacterBody2D
class_name PlayerCharacter

## PlayerCharacter — world exploration entity
## All child node refs are optional — works even in a minimal scene.

signal interact_requested(target: Node2D)
signal interaction_started(target: Node2D)
signal interaction_finished(target: Node2D)

@export var move_speed         : float = 180.0
@export var sprint_multiplier  : float = 1.6
@export var interaction_range  : float = 48.0

# Optional child nodes — won't crash if absent in the scene
var sprite             : Sprite2D        = null
var collision_shape    : CollisionShape2D = null
var interaction_area   : Area2D          = null
var animation_player   : AnimationPlayer  = null

var is_interacting              : bool      = false
var current_interaction_target  : Node2D    = null
var _sprinting                  : bool      = false
var player_data                 : Dictionary = {}


func _ready() -> void:
	# Grab optional children safely
	sprite           = get_node_or_null("Sprite2D")
	collision_shape  = get_node_or_null("CollisionShape2D")
	interaction_area = get_node_or_null("InteractionArea")
	animation_player = get_node_or_null("AnimationPlayer")

	_sync_with_game_state()
	_play_anim("idle")


func _physics_process(_delta: float) -> void:
	if is_interacting:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_handle_movement()
	move_and_slide()
	if interaction_area:
		_check_interactions()


func _handle_movement() -> void:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_sprinting = Input.is_action_pressed("ui_sprint") if InputMap.has_action("ui_sprint") else false

	var speed := move_speed * (sprint_multiplier if _sprinting else 1.0)
	velocity  = input_dir.normalized() * speed

	if sprite and input_dir.x != 0.0:
		sprite.flip_h = input_dir.x < 0.0

	if input_dir.length() > 0.1:
		_play_anim("run" if _sprinting else "walk")
	else:
		_play_anim("idle")


func _check_interactions() -> void:
	if is_interacting or not interaction_area:
		return
	current_interaction_target = null
	# Use Node (not CharacterBody2D) to avoid type mismatch crash
	for node in interaction_area.get_overlapping_bodies():
		if node.is_in_group("interactables") or node.has_method("interact"):
			current_interaction_target = node
			return
	for area in interaction_area.get_overlapping_areas():
		if area.is_in_group("interactables") or area.has_method("interact"):
			current_interaction_target = area
			return


func _input(event: InputEvent) -> void:
	if event.is_action_just_pressed("ui_accept"):
		interact()


func interact() -> void:
	if not current_interaction_target or is_interacting:
		return
	is_interacting = true
	interaction_started.emit(current_interaction_target)

	if current_interaction_target.has_method("interact"):
		current_interaction_target.interact(self)
	elif current_interaction_target.is_in_group("npcs"):
		_talk_to_npc(current_interaction_target)
	elif current_interaction_target.is_in_group("items"):
		_pickup_item(current_interaction_target)

	await get_tree().create_timer(0.4).timeout
	is_interacting = false
	interaction_finished.emit(current_interaction_target)
	current_interaction_target = null


func _talk_to_npc(npc: Node2D) -> void:
	if npc.has_method("start_dialogue"):
		npc.start_dialogue(self)


func _pickup_item(item: Node2D) -> void:
	if item.has_method("collect"):
		item.collect(self)
	elif item.has_method("pick_up"):
		item.pick_up(self)
	else:
		item.queue_free()


# ── GameState sync ────────────────────────────────────────────────────────────

func _sync_with_game_state() -> void:
	if GameState.player.is_empty():
		_init_player_data()
	player_data = GameState.player

	# Restore world position if saved — FIXED Vector2 from Array
	if GameState.world.has("player_position"):
		var pos_data = GameState.world["player_position"]
		if pos_data is Array and pos_data.size() >= 2:
			position = Vector2(float(pos_data[0]), float(pos_data[1]))
		elif pos_data is Vector2:
			position = pos_data


func _init_player_data() -> void:
	GameState.player["name"]           = "Survivor"
	GameState.player["level"]          = 1
	GameState.player["hp"]             = 100
	GameState.player["hp_max"]         = 100
	GameState.player["mp"]             = 50
	GameState.player["mp_max"]         = 50
	GameState.player["str"]            = 5
	GameState.player["agi"]            = 5
	GameState.player["int"]            = 5
	GameState.player["vit"]            = 5
	GameState.player["def"]            = 3
	GameState.player["entropy"]        = 0      # FIXED: was 100, should start at 0
	GameState.player["entropy_max"]    = 100
	GameState.player["gold"]           = 0
	GameState.player["xp"]             = 0
	GameState.player["xp_to_next"]     = 100
	GameState.player["inventory"]      = []
	GameState.player["equipped"]       = {}
	GameState.player["skills"]         = []
	GameState.player["status_effects"] = []
	GameState.player["is_player"]      = true
	GameState.player["team"]           = "player"
	GameState.player["total_kills"]    = 0
	GameState.player["total_deaths"]   = 0


func save_position() -> void:
	GameState.world["player_position"] = [position.x, position.y]


# ── Combat interface ──────────────────────────────────────────────────────────

func take_damage(amount: int) -> int:
	var mit    := max(0, player_data.get("def", 0) - 2)
	var actual := max(1, amount - mit)
	player_data["hp"] = max(0, player_data.get("hp", 0) - actual)
	GameState.player["hp"] = player_data["hp"]
	if player_data["hp"] <= 0:
		_die()
	return actual


func heal(amount: int) -> void:
	player_data["hp"] = min(player_data.get("hp_max", 100), player_data.get("hp", 0) + amount)
	GameState.player["hp"] = player_data["hp"]


func get_combat_data() -> Dictionary:
	return player_data.duplicate(true)


func apply_status_effect(effect: Dictionary) -> void:
	var effs : Array = player_data.get("status_effects", [])
	if not effs.has(effect):
		effs.append(effect)
		player_data["status_effects"] = effs


func remove_status_effect(effect_name: String) -> void:
	player_data["status_effects"] = player_data.get("status_effects", []).filter(
		func(e): return e.get("name", "") != effect_name
	)


func clear_status_effects() -> void:
	player_data["status_effects"] = []


func _die() -> void:
	GameState.set_flag("player_dead", true)
	GameState.save()
	get_tree().change_scene_to_file("res://scenes/main/main_menu.tscn")


# ── Animation helper ──────────────────────────────────────────────────────────

func _play_anim(anim: String) -> void:
	if animation_player and animation_player.has_animation(anim):
		if animation_player.current_animation != anim:
			animation_player.play(anim)

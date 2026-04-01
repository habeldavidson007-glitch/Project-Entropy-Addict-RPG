extends CharacterBody2D
class_name PlayerCharacter

## PlayerCharacter — main player entity for world exploration and combat
## Handles movement, interactions, and player stats synchronization with GameState

signal interact_requested(target: Node2D)
signal interaction_started(target: Node2D)
signal interaction_finished(target: Node2D)

@export var move_speed: float = 180.0
@export var sprint_multiplier: float = 1.6
@export var interaction_range: float = 48.0

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var interaction_area: Area2D = $InteractionArea
@onready var animation_player: AnimationPlayer = $AnimationPlayer

var is_interacting: bool = false
var current_interaction_target: Node2D = null
var _sprinting: bool = false

var player_data: Dictionary = {}


func _ready() -> void:
	_sync_with_game_state()
	if animation_player:
		animation_player.play("idle")


func _physics_process(_delta: float) -> void:
	if is_interacting:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	
	_handle_movement()
	move_and_slide()
	_check_interactions()


func _handle_movement() -> void:
	var input_dir := Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	_sprinting = Input.is_action_pressed("ui_sprint") if InputMap.has_action("ui_sprint") else false
	
	var speed := move_speed * (sprint_multiplier if _sprinting else 1.0)
	velocity = input_dir.normalized() * speed
	
	# Flip sprite based on direction
	if sprite and input_dir.x != 0:
		sprite.flip_h = input_dir.x < 0
	
	# Animation handling
	if animation_player:
		if input_dir.length() > 0.1:
			if _sprinting:
				animation_player.play("run")
			else:
				animation_player.play("walk")
		else:
			animation_player.play("idle")


func _check_interactions() -> void:
	if is_interacting:
		return
	
	for body in interaction_area.get_overlapping_bodies():
		if body.is_in_group("interactables") or body.has_method("interact"):
			current_interaction_target = body
			return
	
	for area in interaction_area.get_overlapping_areas():
		if area.is_in_group("interactables") or area.has_method("interact"):
			current_interaction_target = area
			return
	
	current_interaction_target = null


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
	
	await get_tree().create_timer(0.5).timeout
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


func _sync_with_game_state() -> void:
	player_data = GameState.player.duplicate(true)
	if player_data.is_empty():
		_initialize_player_data()
	
	# Update position from game state if available
	if GameState.world.has("player_position"):
		position = Vector2(GameState.world["player_position"])


func _initialize_player_data() -> void:
	player_data = {
		"name": "Traveler",
		"level": 1,
		"hp": 100,
		"hp_max": 100,
		"str": 5,
		"agi": 5,
		"def": 3,
		"mp": 20,
		"mp_max": 20,
		"xp": 0,
		"xp_to_next": 100,
		"gold": 50,
		"entropy": 100,
		"inventory": [],
		"equipment": {
			"weapon": null,
			"armor": null,
			"accessory": null,
		},
		"skills": [],
		"is_player": true,
		"team": "player",
		"status_effects": [],
	}
	GameState.player = player_data


func take_damage(amount: int) -> int:
	var mitigation := max(0, player_data["def"] - 2)
	var actual_damage := max(1, amount - mitigation)
	player_data["hp"] = max(0, player_data["hp"] - actual_damage)
	GameState.player["hp"] = player_data["hp"]
	
	if animation_player and has_node("DamageFlash"):
		animation_player.play("damage")
	
	if player_data["hp"] <= 0:
		die()
	
	return actual_damage


func heal(amount: int) -> void:
	player_data["hp"] = min(player_data["hp_max"], player_data["hp"] + amount)
	GameState.player["hp"] = player_data["hp"]


func die() -> void:
	GameState.set_flag("player_dead", true)
	GameState.save()
	get_tree().change_scene_to_file("res://scripts/ui/main_menu.tscn")


func save_position() -> void:
	GameState.world["player_position"] = [position.x, position.y]


func get_combat_data() -> Dictionary:
	return player_data.duplicate(true)


func apply_status_effect(effect: Dictionary) -> void:
	if not player_data["status_effects"].has(effect):
		player_data["status_effects"].append(effect)


func remove_status_effect(effect_name: String) -> void:
	player_data["status_effects"] = player_data["status_effects"].filter(
		func(e): return e.get("name") != effect_name
	)


func clear_status_effects() -> void:
	player_data["status_effects"].clear()

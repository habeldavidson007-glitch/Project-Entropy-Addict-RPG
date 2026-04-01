extends CanvasLayer

## LevelUpUI — shown when player levels up
## Displays stat gains, skill choices, and AI-generated flavour line

signal level_up_closed

@onready var level_label: Label = %LevelLabel
@onready var flavour_label: Label = %FlavourLabel
@onready var stat_gains_label: Label = %StatGainsLabel
@onready var skill_container: VBoxContainer = %SkillContainer
@onready var close_btn: Button = %CloseButton
@onready var loading_label: Label = %LoadingLabel

const SKILL_POOL := [
	{"key": "heavy_blow", "name": "Heavy Blow", "desc": "1.8x damage. Costs 8 MP."},
	{"key": "entropy_burst", "name": "Entropy Burst", "desc": "2.2x entropy damage. Drains entropy on hit."},
	{"key": "shield_bash", "name": "Shield Bash", "desc": "Stuns target for 1 turn."},
	{"key": "recover", "name": "Recover", "desc": "Restore 30% max HP. Costs 5 MP."},
]


func _ready() -> void:
	close_btn.pressed.connect(_on_close)
	hide()
	GameState.player_level_changed.connect(_on_level_changed)


func _on_level_changed(old_level: int, new_level: int) -> void:
	_show_level_up(old_level, new_level)


func _show_level_up(old_level: int, new_level: int) -> void:
	level_label.text = "LEVEL %d" % new_level
	var hp_gain: int = 10 + GameState.player["vit"]
	var mp_gain: int = 5 + GameState.player["int"]
	stat_gains_label.text = "+%d HP  ·  +%d MP" % [hp_gain, mp_gain]
	flavour_label.text = ""
	loading_label.show()
	loading_label.text = "..."
	# Fetch AI flavour
	var req_id := AIManager.level_up_flavour(new_level)
	AIManager.ai_response_received.connect(
		func(rid: String, text: String):
			if rid != req_id:
				return
			loading_label.hide()
			flavour_label.text = text,
		CONNECT_ONE_SHOT
	)
	AIManager.ai_request_failed.connect(
		func(_rid: String, _err: String): loading_label.hide(),
		CONNECT_ONE_SHOT
	)
	# Offer 2 random skill choices if player doesn't have them
	_populate_skill_choices()
	show()


func _populate_skill_choices() -> void:
	for child in skill_container.get_children():
		child.queue_free()
	var known: Array = GameState.player.get("skills", [])
	var available: Array = SKILL_POOL.filter(func(s): return not known.has(s["key"]))
	available.shuffle()
	var choices: Array = available.slice(0, min(2, available.size()))
	for skill in choices:
		var btn := Button.new()
		btn.text = "%s — %s" % [skill["name"], skill["desc"]]
		btn.pressed.connect(func(): _learn_skill(skill["key"]))
		skill_container.add_child(btn)


func _learn_skill(skill_key: String) -> void:
	var skills: Array = GameState.player.get("skills", [])
	if not skills.has(skill_key):
		skills.append(skill_key)
		GameState.player["skills"] = skills
	_clear_skill_buttons()


func _clear_skill_buttons() -> void:
	for child in skill_container.get_children():
		child.queue_free()


func _on_close() -> void:
	hide()
	level_up_closed.emit()

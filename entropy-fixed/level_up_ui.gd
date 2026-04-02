extends CanvasLayer

## LevelUpUI — appears when player levels up
## Autoload-safe: connects to GameState.player_level_changed signal

signal closed

@onready var level_label  : Label         = %LevelLabel
@onready var gains_label  : Label         = %GainsLabel
@onready var flavour_label: Label         = %FlavourLabel
@onready var skill_box    : VBoxContainer = %SkillBox
@onready var close_btn    : Button        = %CloseButton
@onready var loading_lbl  : Label         = %LoadingLabel

const SKILL_POOL := [
	{"key": "heavy_blow",    "name": "Heavy Blow",    "desc": "1.8x dmg · 8 MP"},
	{"key": "entropy_burst", "name": "Entropy Burst", "desc": "2.2x entropy dmg · 15 MP"},
	{"key": "shield_bash",   "name": "Shield Bash",   "desc": "Stuns 1 turn · 4 MP"},
	{"key": "recover",       "name": "Recover",       "desc": "Heal 30% HP · 5 MP"},
]

var _ai_id : String = ""


func _ready() -> void:
	hide()
	close_btn.pressed.connect(_on_close)
	GameState.player_level_changed.connect(_on_level_up)


func _on_level_up(old_level: int, new_level: int) -> void:
	level_label.text  = "LEVEL %d" % new_level
	gains_label.text  = "+%d HP max  ·  +%d MP max" % [
		10 + GameState.player.get("vit", 5),
		5  + GameState.player.get("int", 5)
	]
	flavour_label.text = ""
	loading_lbl.show()
	_populate_skills()
	show()

	_ai_id = AIManager.level_up_flavour(new_level)
	AIManager.ai_response_received.connect(
		func(rid: String, text: String):
			if rid == _ai_id:
				loading_lbl.hide()
				flavour_label.text = text,
		CONNECT_ONE_SHOT
	)
	AIManager.ai_request_failed.connect(
		func(rid: String, _e: String):
			if rid == _ai_id:
				loading_lbl.hide(),
		CONNECT_ONE_SHOT
	)


func _populate_skills() -> void:
	for c in skill_box.get_children():
		c.queue_free()
	var known   : Array = GameState.player.get("skills", [])
	var options : Array = SKILL_POOL.filter(func(s): return not known.has(s["key"]))
	options.shuffle()
	for i in min(2, options.size()):
		var s   := options[i]
		var btn := Button.new()
		var k   := s["key"]
		btn.text = "%s — %s" % [s["name"], s["desc"]]
		btn.pressed.connect(func(): _learn(k))
		skill_box.add_child(btn)


func _learn(skill_key: String) -> void:
	var skills : Array = GameState.player.get("skills", [])
	if not skills.has(skill_key):
		skills.append(skill_key)
		GameState.player["skills"] = skills
	for c in skill_box.get_children():
		c.queue_free()
	var done := Label.new()
	done.text = "Skill acquired."
	skill_box.add_child(done)


func _on_close() -> void:
	hide()
	closed.emit()

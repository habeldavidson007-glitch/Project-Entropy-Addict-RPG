extends Control

## CharacterCreation — improved with stat allocation, AI-generated intro flavour
## Signals GameState to set up player data, then transitions to prologue

signal creation_complete

const MAX_STAT_POINTS := 15
const BASE_STATS := {"str": 3, "agi": 3, "int": 3, "vit": 3}
const STAT_LABELS := {"str": "Strength", "agi": "Agility", "int": "Intellect", "vit": "Vitality"}
const STAT_DESC := {
	"str": "Raw damage and carry weight. You hit harder.",
	"agi": "Turn order and dodge. You move before they do.",
	"int": "Skill potency and entropy resistance. You outlast the decay.",
	"vit": "HP per level and passive regen. You survive longer.",
}

@onready var name_input: LineEdit = %NameInput
@onready var stat_labels: Dictionary = {
	"str": %StrValue, "agi": %AgiValue, "int": %IntValue, "vit": %VitValue
}
@onready var points_label: Label = %PointsRemaining
@onready var confirm_btn: Button = %ConfirmButton
@onready var flavour_label: Label = %FlavourLabel
@onready var loading_indicator: Label = %LoadingIndicator

var current_stats: Dictionary = {}
var points_remaining: int = MAX_STAT_POINTS
var _ai_request_id: String = ""
var _ai_flavour: String = ""


func _ready() -> void:
	current_stats = BASE_STATS.duplicate()
	_refresh_ui()
	confirm_btn.pressed.connect(_on_confirm)
	name_input.text_changed.connect(_on_name_changed)
	AIManager.ai_response_received.connect(_on_ai_response)
	AIManager.ai_request_failed.connect(_on_ai_failed)
	flavour_label.hide()
	loading_indicator.hide()


func _on_name_changed(_new_text: String) -> void:
	_request_flavour()


func _request_flavour() -> void:
	var name_val := name_input.text.strip_edges()
	if name_val.length() < 2:
		return
	loading_indicator.show()
	loading_indicator.text = "..."
	flavour_label.hide()
	var dominant_stat := _get_dominant_stat()
	var prompt := """You are a grim narrator for a dark survival RPG called Entropy Addict.
The player just named their character "%s" and their dominant stat is %s.
Write ONE cold, honest sentence about what kind of survivor this person might be.
No hope. No heroism. Just observation. Max 18 words.""" % [name_val, STAT_LABELS[dominant_stat]]
	_ai_request_id = AIManager.ask(prompt, "char_flavour")


func _on_ai_response(request_id: String, text: String) -> void:
	if request_id != _ai_request_id:
		return
	_ai_flavour = text
	loading_indicator.hide()
	flavour_label.text = text
	flavour_label.show()


func _on_ai_failed(request_id: String, _error: String) -> void:
	if request_id != _ai_request_id:
		return
	loading_indicator.hide()


# ─── Stat Buttons ─────────────────────────────────────────────────────────────

func increment_stat(stat: String) -> void:
	if points_remaining <= 0:
		return
	current_stats[stat] += 1
	points_remaining -= 1
	_refresh_ui()


func decrement_stat(stat: String) -> void:
	if current_stats[stat] <= BASE_STATS[stat]:
		return
	current_stats[stat] -= 1
	points_remaining += 1
	_refresh_ui()


func _refresh_ui() -> void:
	for stat in stat_labels:
		stat_labels[stat].text = str(current_stats[stat])
	points_label.text = "Points remaining: %d" % points_remaining
	confirm_btn.disabled = name_input.text.strip_edges().length() < 2


# ─── Confirm ──────────────────────────────────────────────────────────────────

func _on_confirm() -> void:
	var player_name := name_input.text.strip_edges()
	if player_name.is_empty():
		return
	GameState.player["name"] = player_name
	for stat in current_stats:
		GameState.player[stat] = current_stats[stat]
	GameState.player["hp_max"] = 80 + current_stats["vit"] * 10
	GameState.player["hp"] = GameState.player["hp_max"]
	GameState.player["mp_max"] = 30 + current_stats["int"] * 8
	GameState.player["mp"] = GameState.player["mp_max"]
	if not _ai_flavour.is_empty():
		GameState.set_flag("character_intro_flavour", _ai_flavour)
	GameState.save()
	creation_complete.emit()


func _get_dominant_stat() -> String:
	var best_stat := "str"
	var best_val := 0
	for s in current_stats:
		if current_stats[s] > best_val:
			best_val = current_stats[s]
			best_stat = s
	return best_stat

extends Control

## CharacterCreation — player name + stat allocation + AI-generated intro flavour

signal creation_complete

const MAX_POINTS  : int = 15
const BASE_STATS  : Dictionary = {"str": 3, "agi": 3, "int": 3, "vit": 3}
const STAT_LABELS : Dictionary = {
	"str": "Strength", "agi": "Agility", "int": "Intellect", "vit": "Vitality"
}
const STAT_DESCS : Dictionary = {
	"str": "Raw damage output. You hit harder.",
	"agi": "Turn order and dodge. You move first.",
	"int": "Skill potency and entropy resistance.",
	"vit": "HP per level and regen. You last longer.",
}

@onready var name_input      : LineEdit    = %NameInput
@onready var points_label    : Label       = %PointsLabel
@onready var confirm_btn     : Button      = %ConfirmButton
@onready var flavour_label   : Label       = %FlavourLabel
@onready var loading_label   : Label       = %LoadingLabel
@onready var str_val         : Label       = %StrValue
@onready var agi_val         : Label       = %AgiValue
@onready var int_val         : Label       = %IntValue
@onready var vit_val         : Label       = %VitValue
@onready var str_inc         : Button      = %StrInc
@onready var str_dec         : Button      = %StrDec
@onready var agi_inc         : Button      = %AgiInc
@onready var agi_dec         : Button      = %AgiDec
@onready var int_inc         : Button      = %IntInc
@onready var int_dec         : Button      = %IntDec
@onready var vit_inc         : Button      = %VitInc
@onready var vit_dec         : Button      = %VitDec

var stats     : Dictionary = {}
var points    : int        = MAX_POINTS
var _ai_id    : String     = ""
var _ai_text  : String     = ""


func _ready() -> void:
	stats = BASE_STATS.duplicate()
	_connect_buttons()
	name_input.text_changed.connect(_on_name_changed)
	confirm_btn.pressed.connect(_on_confirm)
	AIManager.ai_response_received.connect(_on_ai_response)
	AIManager.ai_request_failed.connect(_on_ai_failed)
	loading_label.hide()
	flavour_label.text = ""
	_refresh()


func _connect_buttons() -> void:
	str_inc.pressed.connect(func(): _inc("str"))
	str_dec.pressed.connect(func(): _dec("str"))
	agi_inc.pressed.connect(func(): _inc("agi"))
	agi_dec.pressed.connect(func(): _dec("agi"))
	int_inc.pressed.connect(func(): _inc("int"))
	int_dec.pressed.connect(func(): _dec("int"))
	vit_inc.pressed.connect(func(): _inc("vit"))
	vit_dec.pressed.connect(func(): _dec("vit"))


func _inc(stat: String) -> void:
	if points <= 0:
		return
	stats[stat] += 1
	points -= 1
	_refresh()


func _dec(stat: String) -> void:
	if stats[stat] <= BASE_STATS[stat]:
		return
	stats[stat] -= 1
	points += 1
	_refresh()


func _refresh() -> void:
	str_val.text = str(stats["str"])
	agi_val.text = str(stats["agi"])
	int_val.text = str(stats["int"])
	vit_val.text = str(stats["vit"])
	points_label.text   = "Points: %d" % points
	confirm_btn.disabled = name_input.text.strip_edges().length() < 2


func _on_name_changed(new_text: String) -> void:
	confirm_btn.disabled = new_text.strip_edges().length() < 2
	if new_text.strip_edges().length() >= 2:
		_request_flavour(new_text.strip_edges())


func _request_flavour(player_name: String) -> void:
	loading_label.show()
	flavour_label.text = ""
	var dominant := _dominant_stat()
	var prompt := (
		"Dark survival RPG. Character named '%s', dominant stat: %s.\n"
		+ "Write ONE cold, honest sentence about what kind of survivor this person is.\n"
		+ "No hope. No heroism. Dry observation. Max 16 words. Output only the sentence."
	) % [player_name, STAT_LABELS[dominant]]
	_ai_id = AIManager.ask(prompt, "char_flavour_%s" % player_name.to_lower().replace(" ", "_"))


func _on_ai_response(req_id: String, text: String) -> void:
	if req_id != _ai_id:
		return
	_ai_text = text
	loading_label.hide()
	flavour_label.text = text


func _on_ai_failed(req_id: String, _err: String) -> void:
	if req_id != _ai_id:
		return
	loading_label.hide()


func _dominant_stat() -> String:
	var best := "str"
	var best_val := 0
	for s in stats:
		if stats[s] > best_val:
			best_val = stats[s]
			best = s
	return best


func _on_confirm() -> void:
	var pname := name_input.text.strip_edges()
	if pname.length() < 2:
		return
	GameState.reset()
	GameState.player["name"]    = pname
	GameState.player["str"]     = stats["str"]
	GameState.player["agi"]     = stats["agi"]
	GameState.player["int"]     = stats["int"]
	GameState.player["vit"]     = stats["vit"]
	GameState.player["def"]     = max(1, stats["vit"] / 2)
	GameState.player["hp_max"]  = 80 + stats["vit"] * 10
	GameState.player["hp"]      = GameState.player["hp_max"]
	GameState.player["mp_max"]  = 30 + stats["int"] * 8
	GameState.player["mp"]      = GameState.player["mp_max"]
	if not _ai_text.is_empty():
		GameState.set_flag("intro_flavour", _ai_text)
	GameState.save()
	get_tree().change_scene_to_file("res://scenes/ui/prologue.tscn")

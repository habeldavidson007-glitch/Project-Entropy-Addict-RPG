extends Control

## MainMenu — entry point of Entropy Addict RPG

@onready var new_game_btn: Button = %NewGameButton
@onready var continue_btn: Button = %ContinueButton
@onready var quit_btn: Button = %QuitButton
@onready var version_label: Label = %VersionLabel
@onready var tagline_label: Label = %TaglineLabel

const TAGLINES := [
	"The world didn't end with fire.",
	"Meta-knowledge is your only weapon.",
	"Everything decays. You just decay slower.",
	"You know how it ends. You just don't know if you can stop it.",
	"Survival is not a skill. It is a refusal.",
]


func _ready() -> void:
	new_game_btn.pressed.connect(_on_new_game)
	continue_btn.pressed.connect(_on_continue)
	quit_btn.pressed.connect(_on_quit)
	version_label.text = "v1.0.0"
	tagline_label.text = TAGLINES[randi() % TAGLINES.size()]
	continue_btn.disabled = not GameState.has_save()


func _on_new_game() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/character_creation.tscn")


func _on_continue() -> void:
	if GameState.load_game():
		get_tree().change_scene_to_file("res://scenes/world/world.tscn")
	else:
		continue_btn.disabled = true


func _on_quit() -> void:
	get_tree().quit()

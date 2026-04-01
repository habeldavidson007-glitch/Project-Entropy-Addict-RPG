extends Node2D

## Prologue — the opening scene of Entropy Addict RPG
## Displays AI-generated area description, intro flavour, first encounter

@onready var dialogue_box: RichTextLabel = %DialogueBox
@onready var area_desc_label: Label = %AreaDescLabel
@onready var continue_btn: Button = %ContinueButton
@onready var loading_indicator: Label = %LoadingIndicator

var _intro_lines: Array[String] = [
	"The world didn't end with fire.",
	"It ended with accumulation.",
	"Every system pushed past its limit.",
	"Every resource harvested until nothing remained.",
	"They called it the Entropy.",
	"You woke up in what's left.",
]
var _current_line: int = 0
var _typing: bool = false
var _area_req_id: String = ""


func _ready() -> void:
	continue_btn.pressed.connect(_on_continue)
	continue_btn.hide()
	loading_indicator.hide()
	area_desc_label.text = ""
	dialogue_box.text = ""
	# Show character intro flavour if created
	var flavour: String = GameState.get_flag("character_intro_flavour", "")
	if not flavour.is_empty():
		_intro_lines.insert(2, flavour)
	# Fetch AI area description
	_request_area_description()
	# Start intro text after a brief pause
	await get_tree().create_timer(0.5).timeout
	_show_next_line()


func _request_area_description() -> void:
	loading_indicator.show()
	_area_req_id = AIManager.describe_area("The Ashveld Flats", "High", "dawn")
	AIManager.ai_response_received.connect(_on_area_desc_received, CONNECT_ONE_SHOT)


func _on_area_desc_received(request_id: String, text: String) -> void:
	if request_id != _area_req_id:
		return
	loading_indicator.hide()
	area_desc_label.text = text


func _show_next_line() -> void:
	if _current_line >= _intro_lines.size():
		continue_btn.show()
		continue_btn.text = "Begin →"
		return
	_typing = true
	var line := _intro_lines[_current_line]
	_current_line += 1
	await _type_text(line)
	_typing = false
	await get_tree().create_timer(1.2).timeout
	_show_next_line()


func _type_text(text: String) -> void:
	dialogue_box.text = ""
	for i in text.length():
		dialogue_box.text += text[i]
		await get_tree().create_timer(0.04).timeout


func _on_continue() -> void:
	get_tree().change_scene_to_file("res://scenes/world/world.tscn")


func _input(event: InputEvent) -> void:
	if event.is_action_just_pressed("ui_accept") and _typing:
		# Skip typing animation
		pass

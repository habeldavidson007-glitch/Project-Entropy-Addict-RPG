extends CanvasLayer

## DialogueSystem — NPC conversation UI with AI-generated responses
## Handles scripted dialogue trees + live AI fallback

signal dialogue_finished

@onready var portrait_label: Label = %PortraitLabel   # placeholder until art
@onready var speaker_label: Label = %SpeakerLabel
@onready var text_box: RichTextLabel = %TextBox
@onready var choices_container: VBoxContainer = %ChoicesContainer
@onready var continue_btn: Button = %ContinueButton
@onready var loading_label: Label = %LoadingLabel

const SCRIPTED := {
	"Old Kael": [
		{"text": "You move like someone who knows what's out there.", "choices": [
			{"label": "I do.", "next": "kael_2"},
			{"label": "Just passing through.", "next": "kael_end"},
		]},
		"kael_2": {"text": "Then you know resting here costs you nothing. Moving costs everything.", "choices": [
			{"label": "What do you want?", "next": "kael_3"},
			{"label": "Good advice.", "next": "kael_end"},
		]},
		"kael_3": {"text": "Nothing from you. I'm watching to see how long you last.", "choices": [
			{"label": "Fair enough.", "next": "kael_end"},
		]},
		"kael_end": {"text": "...", "choices": []},
	],
	"Mira": [
		{"text": "We don't take strangers at camp. You're not a stranger anymore. Make of that what you will.", "choices": [
			{"label": "I'll keep my head down.", "next": "mira_2"},
			{"label": "What do you need?", "next": "mira_trade"},
		]},
		"mira_2": {"text": "That's the right answer.", "choices": []},
		"mira_trade": {"text": "Scrap. Stimpacks. A reason to trust you. In that order.", "choices": []},
	],
}

var _current_npc: String = ""
var _current_node: Variant = null
var _ai_mode: bool = false
var _ai_req_id: String = ""


func _ready() -> void:
	continue_btn.pressed.connect(_on_continue)
	AIManager.ai_response_received.connect(_on_ai_response)
	hide()


func start_dialogue(npc_name: String, faction: String, mood: String, context: String) -> void:
	_current_npc = npc_name
	_ai_mode = false
	show()
	speaker_label.text = npc_name
	portrait_label.text = npc_name[0].to_upper()
	if SCRIPTED.has(npc_name) and not SCRIPTED[npc_name].is_empty():
		_show_node(SCRIPTED[npc_name][0])
	else:
		# Fall back to AI generation
		_ai_mode = true
		_show_loading()
		_ai_req_id = AIManager.npc_speak(npc_name, faction, mood, context)


func _show_node(node: Variant) -> void:
	_current_node = node
	for child in choices_container.get_children():
		child.queue_free()
	if node is Dictionary:
		_type_text(node.get("text", "..."))
		var choices: Array = node.get("choices", [])
		if choices.is_empty():
			continue_btn.show()
			continue_btn.text = "End conversation"
		else:
			continue_btn.hide()
			for choice in choices:
				var btn := Button.new()
				btn.text = choice["label"]
				var next_key: String = choice["next"]
				btn.pressed.connect(func(): _follow_choice(next_key))
				choices_container.add_child(btn)


func _follow_choice(next_key: String) -> void:
	for child in choices_container.get_children():
		child.queue_free()
	var scripted_tree: Array = SCRIPTED.get(_current_npc, [])
	for node in scripted_tree:
		if node is Dictionary and node.get("key", "") == next_key:
			_show_node(node)
			return
	# Try by string key directly in array
	if SCRIPTED.has(_current_npc) and SCRIPTED[_current_npc].has(next_key):
		_show_node(SCRIPTED[_current_npc][next_key])
		return
	_end_dialogue()


func _on_ai_response(req_id: String, text: String) -> void:
	if req_id != _ai_req_id or not _ai_mode:
		return
	loading_label.hide()
	_type_text(text)
	continue_btn.show()
	continue_btn.text = "End conversation"


func _show_loading() -> void:
	text_box.text = ""
	loading_label.show()
	loading_label.text = "..."
	continue_btn.hide()


func _type_text(full_text: String) -> void:
	loading_label.hide()
	text_box.text = ""
	# Instant display — typewriter effect can be added later
	text_box.text = full_text
	continue_btn.show()
	continue_btn.text = "Continue"


func _on_continue() -> void:
	_end_dialogue()


func _end_dialogue() -> void:
	hide()
	dialogue_finished.emit()

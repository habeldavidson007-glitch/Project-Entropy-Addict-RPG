extends CanvasLayer

## PauseMenu — in-game pause, settings, save

signal resumed
signal quit_to_menu

@onready var resume_btn: Button = %ResumeButton
@onready var inventory_btn: Button = %InventoryButton
@onready var save_btn: Button = %SaveButton
@onready var quit_btn: Button = %QuitButton
@onready var ai_status_label: Label = %AIStatusLabel
@onready var player_info_label: Label = %PlayerInfoLabel

var _visible: bool = false


func _ready() -> void:
	hide()
	resume_btn.pressed.connect(_on_resume)
	inventory_btn.pressed.connect(_on_inventory)
	save_btn.pressed.connect(_on_save)
	quit_btn.pressed.connect(_on_quit)
	AIManager.ai_busy_changed.connect(_on_ai_busy)


func _input(event: InputEvent) -> void:
	if event.is_action_just_pressed("open_menu"):
		if _visible:
			_on_resume()
		else:
			_open()


func _open() -> void:
	_visible = true
	show()
	get_tree().paused = true
	_refresh_info()


func _refresh_info() -> void:
	var p := GameState.player
	player_info_label.text = "%s  ·  Lv.%d  ·  Day %d\nHP %d/%d  ·  Entropy %d%%" % [
		p["name"], p["level"], GameState.world["day"],
		p["hp"], p["hp_max"],
		int(float(p["entropy"]) / float(p["entropy_max"]) * 100)
	]
	ai_status_label.text = "AI: %s" % ("Busy" if AIManager.is_busy() else "Ready")


func _on_resume() -> void:
	_visible = false
	hide()
	get_tree().paused = false
	resumed.emit()


func _on_inventory() -> void:
	# Signal world to open inventory
	get_tree().call_group("inventory_ui", "show")


func _on_save() -> void:
	GameState.save()
	save_btn.text = "Saved."
	await get_tree().create_timer(1.5).timeout
	save_btn.text = "Save game"


func _on_quit() -> void:
	GameState.save()
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scripts/ui/main_menu.tscn")
	quit_to_menu.emit()


func _on_ai_busy(busy: bool) -> void:
	ai_status_label.text = "AI: %s" % ("Busy..." if busy else "Ready")

extends Control

## InventoryUI — item management, equip/use/drop
## Connects to GameState.player.inventory

signal inventory_closed

@onready var item_list: VBoxContainer = %ItemList
@onready var item_name_label: Label = %ItemNameLabel
@onready var item_desc_label: RichTextLabel = %ItemDescLabel
@onready var equip_btn: Button = %EquipButton
@onready var use_btn: Button = %UseButton
@onready var drop_btn: Button = %DropButton
@onready var close_btn: Button = %CloseButton
@onready var loading_label: Label = %LoadingLabel

var _selected_item: Dictionary = {}
var _selected_index: int = -1
var _ai_req_id: String = ""


func _ready() -> void:
	close_btn.pressed.connect(_on_close)
	equip_btn.pressed.connect(_on_equip)
	use_btn.pressed.connect(_on_use)
	drop_btn.pressed.connect(_on_drop)
	AIManager.ai_response_received.connect(_on_ai_desc)
	_clear_detail()
	_refresh_list()


func _refresh_list() -> void:
	for child in item_list.get_children():
		child.queue_free()
	var inventory: Array = GameState.player.get("inventory", [])
	if inventory.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "Nothing."
		empty_lbl.add_theme_font_size_override("font_size", 12)
		item_list.add_child(empty_lbl)
		return
	for i in inventory.size():
		var item: Dictionary = inventory[i]
		var btn := Button.new()
		var equipped := GameState.player["equipped"].get(item.get("slot", ""), {}).get("id") == item.get("id")
		btn.text = "%s%s" % [item.get("name", "?"), "  [E]" if equipped else ""]
		btn.pressed.connect(func(): _select_item(i))
		item_list.add_child(btn)


func _select_item(index: int) -> void:
	_selected_index = index
	var inventory: Array = GameState.player.get("inventory", [])
	if index >= inventory.size():
		return
	_selected_item = inventory[index]
	item_name_label.text = _selected_item.get("name", "Unknown")
	item_desc_label.text = "..."
	loading_label.show()
	# Fetch AI description
	var cache_key := "item_desc_%s" % _selected_item.get("id", "unknown")
	if GameState.has_flag(cache_key):
		item_desc_label.text = GameState.get_flag(cache_key)
		loading_label.hide()
		return
	_ai_req_id = AIManager.ask_template("loot_desc", {
		"item_name": _selected_item.get("name", "Unknown"),
		"tier": _selected_item.get("tier", 1),
		"type": _selected_item.get("type", "misc"),
	}, cache_key)
	# Update action buttons
	var item_type: String = _selected_item.get("type", "misc")
	equip_btn.visible = item_type in ["weapon", "armor", "accessory"]
	use_btn.visible = item_type == "consumable"
	drop_btn.visible = true


func _on_ai_desc(req_id: String, text: String) -> void:
	if req_id != _ai_req_id:
		return
	loading_label.hide()
	item_desc_label.text = text
	GameState.set_flag(req_id, text)   # cache using req_id which is the cache_key


func _on_equip() -> void:
	if _selected_item.is_empty():
		return
	var slot: String = _selected_item.get("slot", "weapon")
	GameState.player["equipped"][slot] = _selected_item
	_refresh_list()


func _on_use() -> void:
	if _selected_item.is_empty():
		return
	var effect: String = _selected_item.get("effect", "")
	match effect:
		"heal":
			var amount: int = _selected_item.get("value", 20)
			GameState.heal(amount)
		"restore_mp":
			var amount: int = _selected_item.get("value", 15)
			GameState.player["mp"] = min(GameState.player["mp_max"], GameState.player["mp"] + amount)
		"reduce_entropy":
			var amount: int = _selected_item.get("value", 10)
			GameState.reduce_entropy(amount)
	GameState.remove_item(_selected_item.get("id", ""))
	_clear_detail()
	_refresh_list()


func _on_drop() -> void:
	if _selected_item.is_empty():
		return
	GameState.remove_item(_selected_item.get("id", ""))
	_clear_detail()
	_refresh_list()


func _clear_detail() -> void:
	_selected_item = {}
	_selected_index = -1
	item_name_label.text = ""
	item_desc_label.text = ""
	equip_btn.visible = false
	use_btn.visible = false
	drop_btn.visible = false
	loading_label.hide()


func _on_close() -> void:
	inventory_closed.emit()
	hide()

extends CanvasLayer

## HUD — persistent overlay: HP, MP, Entropy, narration
## Add to world.tscn and combat_ui.tscn as a child CanvasLayer

@onready var hp_bar         : ProgressBar = %HPBar
@onready var mp_bar         : ProgressBar = %MPBar
@onready var entropy_bar    : ProgressBar = %EntropyBar
@onready var hp_label       : Label       = %HPLabel
@onready var mp_label       : Label       = %MPLabel
@onready var entropy_label  : Label       = %EntropyLabel
@onready var level_label    : Label       = %LevelLabel
@onready var gold_label     : Label       = %GoldLabel
@onready var narration_label: Label       = %NarrationLabel
@onready var narration_timer: Timer       = %NarrationTimer

var _tween : Tween


func _ready() -> void:
	narration_label.modulate.a = 0.0
	narration_timer.timeout.connect(_fade_narration)
	if has_node("/root/CombatManager"):
		CombatManager.narration_ready.connect(_show_narration)


func _process(_delta: float) -> void:
	var p := GameState.player
	var hp_r := float(p.get("hp", 0)) / float(max(1, p.get("hp_max", 100)))
	var mp_r := float(p.get("mp", 0)) / float(max(1, p.get("mp_max", 50)))
	var en_r := float(p.get("entropy", 0)) / float(max(1, p.get("entropy_max", 100)))

	hp_bar.value      = hp_r * 100.0
	mp_bar.value      = mp_r * 100.0
	entropy_bar.value = en_r * 100.0

	hp_label.text      = "%d/%d" % [p.get("hp",0), p.get("hp_max",100)]
	mp_label.text      = "%d/%d" % [p.get("mp",0), p.get("mp_max",50)]
	entropy_label.text = "ENTROPY %d%%" % int(en_r * 100)
	level_label.text   = "LV %d" % p.get("level", 1)
	gold_label.text    = "%d G" % p.get("gold", 0)

	# Entropy pulse warning
	if en_r >= 0.7:
		var pulse := 0.6 + sin(Time.get_ticks_msec() * 0.005) * 0.4
		entropy_bar.modulate = Color(1.0, pulse * 0.3, pulse * 0.3)
	else:
		entropy_bar.modulate = Color.WHITE


func _show_narration(text: String) -> void:
	narration_label.text = text
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(narration_label, "modulate:a", 1.0, 0.15)
	narration_timer.start(3.5)


func _fade_narration() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(narration_label, "modulate:a", 0.0, 0.7)

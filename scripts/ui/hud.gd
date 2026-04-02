extends CanvasLayer

## HUD — persistent heads-up display
## Shows HP, MP, Entropy, level, gold, and live AI combat narration

@onready var hp_label: Label = %HPLabel
@onready var mp_label: Label = %MPLabel
@onready var hp_bar: ProgressBar = %HPBar
@onready var mp_bar: ProgressBar = %MPBar
@onready var entropy_bar: ProgressBar = %EntropyBar
@onready var entropy_label: Label = %EntropyLabel
@onready var level_label: Label = %LevelLabel
@onready var gold_label: Label = %GoldLabel
@onready var narration_label: Label = %NarrationLabel
@onready var narration_timer: Timer = %NarrationTimer

const ENTROPY_WARN_THRESHOLD := 0.7   # 70% entropy = visual warning
var _narration_tween: Tween


func _ready() -> void:
	narration_label.modulate.a = 0.0
	narration_timer.timeout.connect(_fade_narration)
	CombatManager.narration_ready.connect(_show_narration)
	CombatManager.damage_dealt.connect(_on_damage)
	GameState.player_level_changed.connect(func(_o, _n): refresh())
	refresh()
	set_process(true)


func _process(_delta: float) -> void:
	# Sync live values every frame (HP can change mid-combat)
	var p: Dictionary = GameState.player
	hp_bar.value = float(p["hp"]) / float(p["hp_max"]) * 100.0
	mp_bar.value = float(p["mp"]) / float(p["mp_max"]) * 100.0
	var entropy_ratio: float = float(p["entropy"]) / float(p["entropy_max"])
	entropy_bar.value = entropy_ratio * 100.0
	hp_label.text = "%d / %d" % [p["hp"], p["hp_max"]]
	mp_label.text = "%d / %d" % [p["mp"], p["mp_max"]]
	entropy_label.text = "ENTROPY %d%%" % int(entropy_ratio * 100)
	# Pulse entropy bar red when high
	if entropy_ratio >= ENTROPY_WARN_THRESHOLD:
		entropy_bar.modulate = Color(1.0, 0.2 + sin(Time.get_ticks_msec() * 0.004) * 0.2, 0.2)
	else:
		entropy_bar.modulate = Color.WHITE


func refresh() -> void:
	var p: Dictionary = GameState.player
	level_label.text = "LV %d" % p["level"]
	gold_label.text = "%d G" % p["gold"]


func _show_narration(text: String) -> void:
	narration_label.text = text
	if _narration_tween:
		_narration_tween.kill()
	_narration_tween = create_tween()
	_narration_tween.tween_property(narration_label, "modulate:a", 1.0, 0.2)
	narration_timer.start(3.5)


func _fade_narration() -> void:
	if _narration_tween:
		_narration_tween.kill()
	_narration_tween = create_tween()
	_narration_tween.tween_property(narration_label, "modulate:a", 0.0, 0.8)


func _on_damage(_attacker: Dictionary, _target: Dictionary, amount: int, skill: String) -> void:
	# Flash the HP bar red briefly on player damage
	if _attacker.get("team", "") == "enemy":
		var t: Tween = create_tween()
		t.tween_property(hp_bar, "modulate", Color(1, 0.3, 0.3), 0.1)
		t.tween_property(hp_bar, "modulate", Color.WHITE, 0.3)

extends Node
class_name AIManagerClass

## AIManager — Autoload singleton
## Queued, cached, retry-safe Ollama/Qwen interface for Entropy Addict RPG

signal ai_response_received(request_id: String, text: String)
signal ai_request_failed(request_id: String, error: String)
signal ai_busy_changed(is_busy: bool)

const OLLAMA_URL    : String = "http://127.0.0.1:11434/api/generate"
const MODEL_NAME    : String = "qwen2.5-coder:3b"
const MAX_TOKENS    : int    = 80
const TEMPERATURE   : float  = 0.7
const TOP_P         : float  = 0.9
const REQUEST_TIMEOUT: float = 45.0   # 3b model needs time – was 5.0 (too short)
const MAX_RETRIES   : int    = 2

var _request_queue  : Array[Dictionary] = []
var _active_request : Dictionary        = {}
var _response_cache : Dictionary        = {}
var _prompt_cache   : Dictionary        = {}
var _http_request   : HTTPRequest
var _is_busy        : bool              = false


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = REQUEST_TIMEOUT
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	print("[AIManager] Ready. Model: %s  Timeout: %.0fs" % [MODEL_NAME, REQUEST_TIMEOUT])


func is_busy() -> bool:
	return _is_busy


# ── Public API ────────────────────────────────────────────────────────────────

func ask(prompt: String, req_id: String = "") -> String:
	if req_id.is_empty():
		req_id = "req_%d_%d" % [Time.get_ticks_msec(), randi() % 9999]
	# Cache hit — emit immediately next frame so callers can connect first
	if _response_cache.has(req_id):
		_defer_emit(req_id, _response_cache[req_id])
		return req_id
	_enqueue(req_id, prompt)
	return req_id


func describe_enemy(name: String, level: int, faction: String, region: String) -> String:
	var id := "enemy_%s_%d" % [name.to_lower().replace(" ", "_"), level]
	if _response_cache.has(id):
		_defer_emit(id, _response_cache[id])
		return id
	var prompt := (
		"Dark survival RPG narrator. One sentence, max 20 words, cold and gritty.\n"
		+ "Describe enemy '%s' Level %d, Faction: %s, Region: %s.\n"
		+ "Output ONLY the description. No quotes."
	) % [name, level, faction, region]
	_enqueue(id, prompt)
	return id


func describe_area(area_name: String, danger: String, time_of_day: String) -> String:
	var id := "area_%s_%s" % [area_name.to_lower().replace(" ", "_"), time_of_day]
	if _response_cache.has(id):
		_defer_emit(id, _response_cache[id])
		return id
	var prompt := (
		"Dark survival RPG narrator. Two sentences max, 35 words total, bleak and decayed.\n"
		+ "Describe location '%s'. Danger: %s. Time: %s.\n"
		+ "Output ONLY the description."
	) % [area_name, danger, time_of_day]
	_enqueue(id, prompt)
	return id


func npc_speak(npc_name: String, faction: String, mood: String, context: String, _tone: String = "guarded") -> String:
	var id := "npc_%s_%d" % [npc_name.to_lower().replace(" ", "_"), hash(context) & 0xFFFF]
	if _response_cache.has(id):
		_defer_emit(id, _response_cache[id])
		return id
	var prompt := (
		"NPC dialogue for dark survival RPG. One to two sentences, terse and cold.\n"
		+ "NPC: %s. Faction: %s. Mood: %s. Situation: %s\n"
		+ "Output ONLY the spoken line."
	) % [npc_name, faction, mood, context]
	_enqueue(id, prompt)
	return id


func narrate_hit(attacker: String, target: String, skill: String, damage: int) -> String:
	var id := "hit_%d" % Time.get_ticks_msec()
	var prompt := (
		"One visceral combat line, max 12 words, cold and brutal.\n"
		+ "%s uses %s on %s for %d damage.\n"
		+ "Output ONLY the narration line."
	) % [attacker, skill, target, damage]
	_enqueue(id, prompt)
	return id


func level_up_flavour(level: int) -> String:
	var id := "lvlup_%d" % level
	if _response_cache.has(id):
		_defer_emit(id, _response_cache[id])
		return id
	var prompt := (
		"Dark survival RPG. Player reached Level %d.\n"
		+ "One cold, honest sentence about survival — not hope, not heroism. Max 14 words.\n"
		+ "Output ONLY the sentence."
	) % level
	_enqueue(id, prompt)
	return id


func ask_template(template_key: String, params: Dictionary, req_id: String = "") -> String:
	if req_id.is_empty():
		req_id = "tmpl_%s_%d" % [template_key, Time.get_ticks_msec()]
	if _response_cache.has(req_id):
		_defer_emit(req_id, _response_cache[req_id])
		return req_id
	# Build prompt inline — no file I/O required
	var prompt := _build_inline_template(template_key, params)
	_enqueue(req_id, prompt)
	return req_id


func clear_cache() -> void:
	_response_cache.clear()
	_prompt_cache.clear()
	print("[AIManager] Cache cleared")


func get_cache_size() -> int:
	return _response_cache.size()


# ── Internal Queue ────────────────────────────────────────────────────────────

func _enqueue(req_id: String, prompt: String) -> void:
	_request_queue.append({"id": req_id, "prompt": prompt, "retries": 0})
	if not _is_busy:
		_process_next()


func _process_next() -> void:
	if _request_queue.is_empty():
		_is_busy = false
		ai_busy_changed.emit(false)
		return
	_is_busy = true
	ai_busy_changed.emit(true)
	_active_request = _request_queue.pop_front()
	_send_http(_active_request["prompt"])


func _send_http(prompt: String) -> void:
	var body := JSON.stringify({
		"model": MODEL_NAME,
		"prompt": prompt,
		"stream": false,
		"options": {
			"temperature": TEMPERATURE,
			"num_predict": MAX_TOKENS,
			"top_p": TOP_P,
		}
	})
	var err := _http_request.request(
		OLLAMA_URL,
		["Content-Type: application/json"],
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		_fail("HTTPRequest.request() error: %d" % err)


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_fail("HTTP result error: %d" % result)
		return
	if code != 200:
		_fail("HTTP status %d" % code)
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_fail("JSON parse failed")
		return
	var data : Dictionary = json.get_data()
	var text : String     = str(data.get("response", "")).strip_edges()
	if text.is_empty():
		_fail("Empty response from model")
		return
	_succeed(text)


func _succeed(text: String) -> void:
	var id : String = _active_request.get("id", "")
	_response_cache[id] = text
	ai_response_received.emit(id, text)
	_active_request = {}
	_process_next()


func _fail(reason: String) -> void:
	var retries : int    = _active_request.get("retries", 0)
	var id      : String = _active_request.get("id", "")
	if retries < MAX_RETRIES:
		_active_request["retries"] = retries + 1
		var saved := _active_request.duplicate()
		_active_request = {}
		_request_queue.push_front(saved)   # push AFTER clearing active — fixes double-pop bug
		_is_busy = false
		_process_next()
		return
	push_warning("[AIManager] Failed after %d retries: %s — %s" % [MAX_RETRIES, id, reason])
	ai_request_failed.emit(id, reason)
	_active_request = {}
	_process_next()


func _defer_emit(id: String, text: String) -> void:
	# Deferred so callers have time to connect signals before emit fires
	call_deferred("_do_emit", id, text)


func _do_emit(id: String, text: String) -> void:
	ai_response_received.emit(id, text)


# ── Template Builder ──────────────────────────────────────────────────────────

func _build_inline_template(key: String, p: Dictionary) -> String:
	match key:
		"loot_desc":
			return (
				"Dark RPG item description. One sentence, max 15 words, cold and functional.\n"
				+ "Item: %s. Tier %d. Type: %s.\nOutput ONLY the description."
			) % [p.get("item_name","?"), p.get("tier",1), p.get("type","misc")]
		"level_up_flavour":
			return level_up_flavour(p.get("level", 1))
		_:
			return "Describe: %s" % str(p)

extends Node
class_name AIManagerClass

## AIManager — Centralized AI request handler with caching and queue system
## Optimized for minimal RAM usage and fast response times
## Supports multiple request types with automatic retry and fallback

signal ai_response_received(request_id: String, text: String)
signal ai_request_failed(request_id: String, error: String)
signal ai_busy_changed(is_busy: bool)

# Configuration for Qwen 2.5 Coder 3B
const OLLAMA_URL: String = "http://localhost:11434/api/generate"
const MODEL_NAME: String = "qwen2.5-coder:3b"
const MAX_TOKENS: int = 60
const TEMPERATURE: float = 0.7
const TOP_P: float = 0.9
const REQUEST_TIMEOUT: float = 5.0

# Request queue for managing concurrent requests
var _request_queue: Array[Dictionary] = []
var _active_request: Dictionary = {}
var _response_cache: Dictionary = {}
var _http_request: HTTPRequest
var _is_busy: bool = false

# Prompt templates cache
var _prompt_templates: Dictionary = {}


func _ready() -> void:
	_http_request = HTTPRequest.new()
	_http_request.timeout = REQUEST_TIMEOUT
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	print("[AI Manager] Initialized for %s (max_tokens=%d)" % [MODEL_NAME, MAX_TOKENS])


func is_busy() -> bool:
	return _is_busy or not _request_queue.is_empty()


# ─── Public API ───────────────────────────────────────────────────────────────

## Generic prompt request with caching
func ask(prompt: String, cache_prefix: String = "") -> String:
	var cache_key: String = ""
	if not cache_prefix.is_empty():
		cache_key = "%s_%s" % [cache_prefix, prompt.hash()]
		if _response_cache.has(cache_key):
			_emit_response(cache_key, _response_cache[cache_key])
			return cache_key
	
	var req_id: String = _generate_request_id(cache_prefix)
	_queue_request(req_id, prompt, cache_key)
	return req_id


## Enemy description request
func describe_enemy(enemy_name: String, enemy_level: int, faction: String, region: String) -> String:
	var cache_key: String = "enemy_desc_%s_%d_%s_%s" % [enemy_name.to_lower().replace(" ", "_"), enemy_level, faction.to_lower(), region.to_lower()]
	if _response_cache.has(cache_key):
		_emit_response(cache_key, _response_cache[cache_key])
		return cache_key
	
	var prompt: String = _build_enemy_prompt(enemy_name, enemy_level, faction, region)
	var req_id: String = _generate_request_id("enemy")
	_queue_request(req_id, prompt, cache_key)
	return req_id


## Area description request
func describe_area(area_name: String, danger: String, time_of_day: String) -> String:
	var cache_key: String = "area_desc_%s_%s_%s" % [area_name.to_lower().replace(" ", "_"), danger.to_lower(), time_of_day.to_lower()]
	if _response_cache.has(cache_key):
		_emit_response(cache_key, _response_cache[cache_key])
		return cache_key
	
	var prompt: String = _build_area_prompt(area_name, danger, time_of_day)
	var req_id: String = _generate_request_id("area")
	_queue_request(req_id, prompt, cache_key)
	return req_id


## NPC dialogue request
func npc_speak(npc_name: String, faction: String, mood: String, context: String) -> String:
	var cache_key: String = "npc_speak_%s_%s_%s_%d" % [npc_name.to_lower().replace(" ", "_"), faction.to_lower(), mood.to_lower(), hash(context)]
	if _response_cache.has(cache_key):
		_emit_response(cache_key, _response_cache[cache_key])
		return cache_key
	
	var prompt: String = _build_npc_prompt(npc_name, faction, mood, context)
	var req_id: String = _generate_request_id("npc")
	_queue_request(req_id, prompt, cache_key)
	return req_id


## Combat narration request
func narrate_hit(attacker_name: String, target_name: String, skill_name: String, damage: int) -> String:
	var cache_key: String = "combat_narr_%s_%s_%s_%d" % [attacker_name.to_lower(), target_name.to_lower(), skill_name.to_lower(), damage]
	if _response_cache.has(cache_key):
		_emit_response(cache_key, _response_cache[cache_key])
		return cache_key
	
	var prompt: String = _build_combat_prompt(attacker_name, target_name, skill_name, damage)
	var req_id: String = _generate_request_id("combat")
	_queue_request(req_id, prompt, cache_key)
	return req_id


## Template-based request (for item descriptions, etc.)
func ask_template(template_name: String, params: Dictionary, cache_key: String = "") -> String:
	if cache_key.is_empty():
		cache_key = "template_%s_%s" % [template_name, params.hash()]
	
	if _response_cache.has(cache_key):
		_emit_response(cache_key, _response_cache[cache_key])
		return cache_key
	
	var template: String = _load_prompt_template(template_name + ".txt")
	if template.is_empty():
		# Fallback to generated prompt based on template name
		template = _build_fallback_template(template_name, params)
	
	for key in params:
		template = template.replace("{%s}" % key, str(params[key]))
	
	var req_id: String = _generate_request_id("template")
	_queue_request(req_id, template, cache_key)
	return req_id


## Level up flavour text
func level_up_flavour(level: int) -> String:
	var cache_key: String = "level_flavour_%d" % level
	if _response_cache.has(cache_key):
		_emit_response(cache_key, _response_cache[cache_key])
		return cache_key
	
	var prompt: String = "The player just reached level %d in a dark survival RPG. Write ONE cold, atmospheric sentence about what this milestone means in a world of decay. Max 20 words. No hope, no heroism." % level
	var req_id: String = _generate_request_id("levelup")
	_queue_request(req_id, prompt, cache_key)
	return req_id


# ─── Private Methods ──────────────────────────────────────────────────────────

func _generate_request_id(prefix: String) -> String:
	return "%s_%d_%d" % [prefix, Time.get_ticks_msec(), randi() % 10000]


func _queue_request(req_id: String, prompt: String, cache_key: String) -> void:
	_request_queue.append({
		"id": req_id,
		"prompt": prompt,
		"cache_key": cache_key,
		"retries": 0
	})
	_process_queue()


func _process_queue() -> void:
	if _is_busy or _request_queue.is_empty():
		return
	
	_is_busy = true
	ai_busy_changed.emit(true)
	
	_active_request = _request_queue.pop_front()
	_send_request(_active_request.prompt)


func _send_request(prompt: String) -> void:
	var body_dict: Dictionary = {
		"model": MODEL_NAME,
		"prompt": prompt,
		"stream": false,
		"options": {
			"temperature": TEMPERATURE,
			"num_predict": MAX_TOKENS,
			"top_p": TOP_P
		}
	}
	
	var headers: PackedStringArray = ["Content-Type: application/json"]
	var json_body: String = JSON.stringify(body_dict)
	
	var err: Error = _http_request.request(OLLAMA_URL, headers, HTTPClient.METHOD_POST, json_body)
	if err != OK:
		_handle_failure("Failed to send request: %s" % error_string(err))


func _on_request_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		_handle_failure("HTTP request failed: %s" % result)
		return
	
	if code != 200:
		_handle_failure("AI Error: HTTP %d" % code)
		return
	
	var json: JSON = JSON.new()
	var parse_err: Error = json.parse(body.get_string_from_utf8())
	if parse_err != OK:
		_handle_failure("Invalid JSON response")
		return
	
	var data: Dictionary = json.get_data() as Dictionary
	if data.has("response"):
		var text: String = str(data["response"]).strip_edges()
		_handle_success(text)
	else:
		_handle_failure("No response in AI data")


func _handle_success(text: String) -> void:
	var cache_key: String = _active_request.get("cache_key", "")
	var req_id: String = _active_request.get("id", "")
	
	if not cache_key.is_empty():
		_response_cache[cache_key] = text
	
	_emit_response(req_id, text)
	_clear_active_request()


func _handle_failure(error_msg: String) -> void:
	var req: Dictionary = _active_request
	var req_id: String = req.get("id", "")
	var cache_key: String = req.get("cache_key", "")
	var retries: int = req.get("retries", 0)
	
	# Retry up to 2 times
	if retries < 2:
		req["retries"] = retries + 1
		_request_queue.push_front(req)
		_clear_active_request()
		_process_queue()
		return
	
	if not cache_key.is_empty() and _response_cache.has(cache_key):
		_emit_response(req_id, _response_cache[cache_key])
	else:
		ai_request_failed.emit(req_id, error_msg)
	
	_clear_active_request()
	_process_queue()


func _clear_active_request() -> void:
	_active_request.clear()
	_is_busy = not _request_queue.is_empty()
	ai_busy_changed.emit(_is_busy)


func _emit_response(req_id: String, text: String) -> void:
	ai_response_received.emit(req_id, text)


# ─── Prompt Builders ──────────────────────────────────────────────────────────

func _build_enemy_prompt(name: String, level: int, faction: String, region: String) -> String:
	return """Describe this enemy for a dark survival RPG in exactly one sentence (max 25 words).
Enemy: %s, Level: %d, Faction: %s, Region: %s
Style: Cold, atmospheric, showing decay and danger. No stats, just vibe.""" % [name, level, faction, region]


func _build_area_prompt(area_name: String, danger: String, time_of_day: String) -> String:
	return """Describe this location for a dark survival RPG in exactly 2 sentences (max 40 words).
Location: %s, Danger Level: %s, Time: %s
Style: Bleak, atmospheric, showing entropy and decay. Make it feel lived-in but dying.""" % [area_name, danger, time_of_day]


func _build_npc_prompt(npc_name: String, faction: String, mood: String, context: String) -> String:
	return """Write dialogue for an NPC in a dark survival RPG.
NPC: %s, Faction: %s, Mood: %s
Context: %s
Style: Cold, terse, realistic. Max 25 words. No exposition, no heroism.""" % [npc_name, faction, mood, context]


func _build_combat_prompt(attacker: String, target: String, skill: String, damage: int) -> String:
	return """Write combat narration for a dark survival RPG.
Attacker: %s uses %s on %s for %d damage.
Style: Visceral, brief, cold. Max 15 words.""" % [attacker, skill, target, damage]


func _build_fallback_template(template_name: String, params: Dictionary) -> String:
	match template_name:
		"loot_desc":
			return "A %s item of tier %d. Type: %s. [AI description unavailable]" % [
				params.get("item_name", "unknown"),
				params.get("tier", 1),
				params.get("type", "misc")
			]
	return "Template '%s' not found. Params: %s" % [template_name, params]


# ─── Template Loading ─────────────────────────────────────────────────────────

func _load_prompt_template(filename: String) -> String:
	if _prompt_templates.has(filename):
		return _prompt_templates[filename]
	
	var path: String = "res://data/prompts/%s" % filename
	if not FileAccess.file_exists(path):
		return ""
	
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file:
		var content: String = file.get_as_text().strip_edges()
		_prompt_templates[filename] = content
		return content
	return ""


# ─── Cache Management ─────────────────────────────────────────────────────────

func clear_cache() -> void:
	_response_cache.clear()
	_prompt_templates.clear()
	print("[AI Manager] Cache cleared")


func get_cache_size() -> int:
	return _response_cache.size()

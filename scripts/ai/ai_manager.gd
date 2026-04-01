extends Node
class_name AIManagerClass

signal response_received(text: String)
signal error_occurred(message: String)

# Configuration for Qwen 2.5 Coder 3B
var ollama_url: String = "http://localhost:11434/api/generate"
var model_name: String = "qwen2.5-coder:3b"
var max_tokens: int = 60  # Keep low for speed and RAM
var temperature: float = 0.7

# Simple cache to avoid re-generating same descriptions
var _response_cache: Dictionary = {}

func _ready() -> void:
	print("[AI Manager] Initialized for %s" % model_name)

# Call this to get an enemy description
func request_enemy_description(enemy_name: String, enemy_level: int, faction: String, region: String) -> void:
	# Create a unique key for caching
	var cache_key := "%s_%d_%s_%s" % [enemy_name, enemy_level, faction, region]
	
	if _response_cache.has(cache_key):
		print("[AI Manager] Cache hit!")
		emit_signal("response_received", _response_cache[cache_key])
		return
	
	# Load the prompt template
	var prompt_text := _load_prompt_template("enemy_desc.txt")
	if prompt_text.is_empty():
		emit_signal("error_occurred", "Failed to load prompt template")
		return
	
	# Replace placeholders
	prompt_text = prompt_text.replace("{name}", enemy_name)
	prompt_text = prompt_text.replace("{level}", str(enemy_level))
	prompt_text = prompt_text.replace("{faction}", faction)
	prompt_text = prompt_text.replace("{region}", region)
	
	# Send request
	_send_request(prompt_text, cache_key)

func _load_prompt_template(filename: String) -> String:
	var path := "res://data/prompts/%s" % filename
	if not FileAccess.file_exists(path):
		push_error("Prompt file not found: " + path)
		return ""
	
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text().strip_edges()

func _send_request(prompt: String, cache_key: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_request_completed.bind(http, cache_key))
	
	var body_dict := {
		"model": model_name,
		"prompt": prompt,
		"stream": false,
		"options": {
			"temperature": temperature,
			"num_predict": max_tokens,
			"top_p": 0.9
		}
	}
	
	var headers := ["Content-Type: application/json"]
	var json_body := JSON.stringify(body_dict)
	
	http.request(ollama_url, headers, HTTPClient.METHOD_POST, json_body)

func _on_request_completed(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest, cache_key: String) -> void:
	http.queue_free()
	
	if code != 200:
		emit_signal("error_occurred", "AI Error: HTTP %d" % code)
		return
	
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		emit_signal("error_occurred", "Invalid JSON response")
		return
	
	var data: Dictionary = json.get_data() as Dictionary
	if data.has("response"):
		var text: String = str(data["response"]).strip_edges()
		# Save to cache
		_response_cache[cache_key] = text
		emit_signal("response_received", text)
	else:
		emit_signal("error_occurred", "No response in AI data")

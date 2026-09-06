@tool
class_name LumenOpenAICompatible
extends RefCounted

## Talks to any OpenAI Chat Completions endpoint: Ollama, LM Studio, OpenAI,
## Groq, local llama.cpp server. One client, no vendor account.

signal finished(result: Dictionary)
signal failed(message: String)

var http: HTTPRequest
var log: LumenLogger
var _busy := false


func attach(host: Node, p_log: LumenLogger) -> void:
	log = p_log
	http = HTTPRequest.new()
	http.timeout = 600
	http.use_threads = true
	host.add_child(http)
	http.request_completed.connect(_on_completed)


func chat(base_url: String, api_key: String, payload: Dictionary) -> void:
	if _busy:
		failed.emit("Provider is already running a request.")
		return
	_busy = true
	var url := base_url.trim_suffix("/")
	if not url.ends_with("/chat/completions"):
		url += "/chat/completions"
	var body_payload := payload.duplicate(true)
	if _is_loopback(url):
		var opts: Dictionary = body_payload.get("options", {})
		if typeof(opts) != TYPE_DICTIONARY:
			opts = {}
		if body_payload.has("num_ctx"):
			opts["num_ctx"] = int(body_payload.get("num_ctx"))
			body_payload.erase("num_ctx")
		if body_payload.has("max_tokens") and not opts.has("num_predict"):
			opts["num_predict"] = int(body_payload.get("max_tokens"))
		if not opts.is_empty():
			body_payload["options"] = opts
		if not body_payload.has("keep_alive"):
			body_payload["keep_alive"] = "30m"
	var headers := PackedStringArray([
		"Content-Type: application/json",
	])
	if api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)
	var body := JSON.stringify(body_payload)
	var err := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		_busy = false
		failed.emit("HTTP request failed: %s" % error_string(err))


func list_models(base_url: String, api_key: String) -> void:
	if _busy:
		failed.emit("Provider is already running a request.")
		return
	_busy = true
	var url := base_url.trim_suffix("/")
	if url.ends_with("/v1"):
		url += "/models"
	elif url.ends_with("/v1/chat/completions"):
		url = url.replace("/chat/completions", "/models")
	else:
		url += "/models"
	var headers := PackedStringArray(["Content-Type: application/json"])
	if api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)
	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_busy = false
		failed.emit("Model list failed: %s" % error_string(err))


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit("Network error (%d)." % result)
		return
	var text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	if code < 200 or code >= 300:
		var detail := text
		if typeof(parsed) == TYPE_DICTIONARY:
			detail = str(parsed.get("error", parsed))
		failed.emit("Provider HTTP %d: %s" % [code, LumenJson.clamp_text(str(detail), 800)])
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		failed.emit("Provider returned non-JSON.")
		return
	finished.emit(parsed)


static func _is_loopback(url: String) -> bool:
	var lower := url.to_lower()
	return lower.find("127.0.0.1") >= 0 or lower.find("localhost") >= 0 or lower.find("[::1]") >= 0

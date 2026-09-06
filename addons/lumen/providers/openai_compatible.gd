@tool
class_name LumenOpenAICompatible
extends RefCounted

## OpenAI Chat Completions for cloud / LM Studio / llama.cpp.
## Ollama on loopback uses native /api/chat so num_ctx and keep_alive actually apply.
## Official /v1 compatibility cannot set context size.

signal finished(result: Dictionary)
signal failed(message: String)
signal probed(ok: bool, message: String)

var http: HTTPRequest
var probe: HTTPRequest
var log: LumenLogger
var _busy := false
var _probing := false


func attach(host: Node, p_log: LumenLogger) -> void:
	log = p_log
	http = HTTPRequest.new()
	http.timeout = 900
	http.use_threads = true
	host.add_child(http)
	http.request_completed.connect(_on_completed)
	probe = HTTPRequest.new()
	probe.timeout = 900
	probe.use_threads = true
	host.add_child(probe)
	probe.request_completed.connect(_on_probe)


func chat(base_url: String, api_key: String, payload: Dictionary) -> void:
	if _busy:
		failed.emit("Provider is already running a request.")
		return
	_busy = true
	var native := _ollama_chat_url(base_url)
	var url := native if native != "" else _openai_chat_url(base_url)
	var body_payload := payload.duplicate(true)
	if native != "":
		body_payload = _to_ollama(body_payload)
	else:
		body_payload = _to_openai(body_payload, _is_loopback(url))
	var headers := PackedStringArray(["Content-Type: application/json"])
	if api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)
	elif native != "":
		headers.append("Authorization: Bearer ollama")
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body_payload))
	if err != OK:
		_busy = false
		failed.emit("HTTP request failed: %s" % error_string(err))


func warmup(base_url: String, api_key: String, model: String, keep_alive: String = "-1", num_ctx: int = 65536) -> void:
	if model.strip_edges() == "":
		probed.emit(false, "Model id missing.")
		return
	if _probing:
		probed.emit(false, "A probe is already running.")
		return
	_probing = true
	var native := _ollama_generate_url(base_url)
	var url := native if native != "" else _openai_models_url(base_url)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if api_key != "":
		headers.append("Authorization: Bearer %s" % api_key)
	var err := OK
	if native != "":
		var opts := {"num_predict": 1}
		if num_ctx > 0:
			opts["num_ctx"] = num_ctx
		var body := {
			"model": model,
			"prompt": "ok",
			"stream": false,
			"keep_alive": keep_alive,
			"options": opts,
		}
		err = probe.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	else:
		err = probe.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_probing = false
		probed.emit(false, "Warmup failed: %s" % error_string(err))


func _openai_models_url(base_url: String) -> String:
	var url := base_url.trim_suffix("/")
	if url.ends_with("/v1"):
		return url + "/models"
	if url.ends_with("/v1/chat/completions"):
		return url.replace("/chat/completions", "/models")
	if url.find(":11434") >= 0:
		return _origin(url) + "/api/tags"
	return url + "/models"


func list_models(base_url: String, api_key: String) -> void:
	if _busy:
		failed.emit("Provider is already running a request.")
		return
	_busy = true
	var url := _openai_models_url(base_url)
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
		if result == HTTPRequest.RESULT_TIMEOUT:
			failed.emit("Timed out waiting for the local model. Large models need minutes to load. Keep the model resident (keep_alive -1) and retry.")
		else:
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
	finished.emit(_as_openai(parsed as Dictionary))


func _on_probe(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_probing = false
	if result == HTTPRequest.RESULT_TIMEOUT:
		probed.emit(false, "Timed out loading the model. 32B+ can take several minutes the first time.")
		return
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		var text := body.get_string_from_utf8()
		probed.emit(false, "Probe failed (%d/%d): %s" % [result, code, LumenJson.clamp_text(text, 400)])
		return
	probed.emit(true, "Runtime answered.")


func _to_ollama(payload: Dictionary) -> Dictionary:
	var opts: Dictionary = payload.get("options", {})
	if typeof(opts) != TYPE_DICTIONARY:
		opts = {}
	if payload.has("num_ctx"):
		var ctx := int(payload.get("num_ctx", 0))
		if ctx > 0:
			opts["num_ctx"] = ctx
	if payload.has("max_tokens") and not opts.has("num_predict"):
		opts["num_predict"] = int(payload.get("max_tokens"))
	if payload.has("temperature"):
		opts["temperature"] = payload.get("temperature")
	var out := {
		"model": payload.get("model", ""),
		"messages": _ollama_messages(payload.get("messages", [])),
		"stream": false,
		"think": bool(payload.get("think", false)),
		"keep_alive": payload.get("keep_alive", "-1"),
	}
	if payload.has("tools"):
		out["tools"] = payload.get("tools")
	if not opts.is_empty():
		out["options"] = opts
	return out


func _to_openai(payload: Dictionary, local: bool) -> Dictionary:
	var out := {
		"model": payload.get("model", ""),
		"messages": payload.get("messages", []),
		"temperature": payload.get("temperature", 0.2),
		"max_tokens": payload.get("max_tokens", 4096),
		"stream": false,
	}
	if payload.has("tools"):
		out["tools"] = payload.get("tools")
		if local:
			out["parallel_tool_calls"] = false
	if local:
		out["keep_alive"] = payload.get("keep_alive", "-1")
	return out


func _ollama_messages(raw: Variant) -> Array:
	var out: Array = []
	if typeof(raw) != TYPE_ARRAY:
		return out
	for row in raw:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = (row as Dictionary).duplicate(true)
		var calls: Variant = msg.get("tool_calls", null)
		if typeof(calls) == TYPE_ARRAY:
			var fixed: Array = []
			for call in calls:
				if typeof(call) != TYPE_DICTIONARY:
					continue
				var item: Dictionary = call
				var fn: Dictionary = item.get("function", {})
				if typeof(fn) != TYPE_DICTIONARY:
					continue
				var args: Variant = fn.get("arguments", {})
				if typeof(args) == TYPE_STRING:
					var parsed: Variant = JSON.parse_string(str(args))
					fn["arguments"] = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
				item["function"] = fn
				fixed.append(item)
			msg["tool_calls"] = fixed
		out.append(msg)
	return out


func _as_openai(parsed: Dictionary) -> Dictionary:
	if parsed.has("choices"):
		return parsed
	if parsed.has("message"):
		var message: Dictionary = (parsed.get("message", {}) as Dictionary).duplicate(true)
		message.erase("thinking")
		var calls: Variant = message.get("tool_calls", [])
		if typeof(calls) == TYPE_ARRAY:
			var fixed: Array = []
			var i := 0
			for call in calls:
				if typeof(call) != TYPE_DICTIONARY:
					continue
				var item: Dictionary = call
				var fn: Dictionary = item.get("function", {})
				if typeof(fn) != TYPE_DICTIONARY:
					continue
				var args: Variant = fn.get("arguments", {})
				if typeof(args) == TYPE_DICTIONARY:
					fn["arguments"] = JSON.stringify(args)
				item["id"] = str(item.get("id", "local-%d" % i))
				item["type"] = "function"
				item["function"] = fn
				fixed.append(item)
				i += 1
			message["tool_calls"] = fixed
		var reason := "stop"
		if typeof(message.get("tool_calls", null)) == TYPE_ARRAY and not (message.get("tool_calls") as Array).is_empty():
			reason = "tool_calls"
		elif str(parsed.get("done_reason", "")) == "length":
			reason = "length"
		return {
			"choices": [{
				"message": message,
				"finish_reason": reason,
			}],
			"model": parsed.get("model", ""),
		}
	if parsed.has("models") or parsed.has("data"):
		return parsed
	if parsed.has("response"):
		return {
			"choices": [{
				"message": {"role": "assistant", "content": str(parsed.get("response", ""))},
				"finish_reason": "stop",
			}],
		}
	return parsed


func _openai_chat_url(base_url: String) -> String:
	var url := base_url.trim_suffix("/")
	if not url.ends_with("/chat/completions"):
		url += "/chat/completions"
	return url


func _ollama_chat_url(base_url: String) -> String:
	if not _looks_ollama(base_url):
		return ""
	return _origin(base_url) + "/api/chat"


func _ollama_generate_url(base_url: String) -> String:
	if not _looks_ollama(base_url):
		return ""
	return _origin(base_url) + "/api/generate"


func _looks_ollama(url: String) -> bool:
	var lower := url.to_lower()
	return lower.find(":11434") >= 0 or lower.find("/api/chat") >= 0 or lower.find("ollama") >= 0


func _origin(url: String) -> String:
	var trimmed := url.trim_suffix("/")
	var scheme := trimmed.find("://")
	if scheme < 0:
		return trimmed
	var rest := trimmed.substr(scheme + 3)
	var slash := rest.find("/")
	if slash < 0:
		return trimmed
	return trimmed.substr(0, scheme + 3 + slash)


static func _is_loopback(url: String) -> bool:
	var lower := url.to_lower()
	return lower.find("127.0.0.1") >= 0 or lower.find("localhost") >= 0 or lower.find("[::1]") >= 0

@tool
class_name LumenGemini
extends RefCounted

## Gemini generateContent. Uses a Gemini CLI OAuth token or GEMINI_API_KEY.

signal finished(result: Dictionary)
signal failed(message: String)
signal models_listed(names: PackedStringArray)
signal models_failed(message: String)

var http: HTTPRequest
var log: LumenLogger
var _busy := false
var _listing := false


func attach(host: Node, p_log: LumenLogger) -> void:
	log = p_log
	http = HTTPRequest.new()
	http.timeout = 180
	http.use_threads = true
	host.add_child(http)
	http.request_completed.connect(_on_completed)



func list_models(token: String, api_key: String) -> void:
	if _busy:
		models_failed.emit("Provider is already running a request.")
		return
	if token == "" and api_key == "":
		models_failed.emit("No Gemini CLI session and no GEMINI_API_KEY.")
		return
	_busy = true
	_listing = true
	var url := "https://generativelanguage.googleapis.com/v1beta/models"
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer %s" % token)
	elif api_key != "":
		headers.append("x-goog-api-key: %s" % api_key)
		url += "?key=%s" % api_key.uri_encode()
	var err := http.request(url, headers, HTTPClient.METHOD_GET)
	if err != OK:
		_busy = false
		_listing = false
		models_failed.emit("Model list failed: %s" % error_string(err))


func chat(token: String, api_key: String, model: String, messages: Array, tools: Array, max_tokens: int, temperature: float) -> void:
	if _busy:
		failed.emit("Provider is already running a request.")
		return
	if token == "" and api_key == "":
		failed.emit("No Gemini CLI session and no GEMINI_API_KEY.")
		return
	_busy = true
	_listing = false
	var id := model if model != "" else "gemini-2.5-flash"
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % id
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer %s" % token)
	elif api_key != "":
		headers.append("x-goog-api-key: %s" % api_key)
		url += "?key=%s" % api_key.uri_encode()
	var payload := {
		"contents": _to_contents(messages),
		"generationConfig": {
			"temperature": temperature,
			"maxOutputTokens": max_tokens,
		},
	}
	var system := _system_text(messages)
	if system != "":
		payload["systemInstruction"] = {"parts": [{"text": system}]}
	if not tools.is_empty():
		payload["tools"] = [{"functionDeclarations": _to_decls(tools)}]
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_busy = false
		failed.emit("HTTP request failed: %s" % error_string(err))


func _system_text(messages: Array) -> String:
	var out := ""
	for msg in messages:
		if str(msg.get("role", "")) == "system":
			out += str(msg.get("content", "")) + "\n"
	return out.strip_edges()


func _to_contents(messages: Array) -> Array:
	var out: Array = []
	for msg in messages:
		var role := str(msg.get("role", "user"))
		if role == "system":
			continue
		if role == "tool":
			out.append({
				"role": "user",
				"parts": [{
					"functionResponse": {
						"name": str(msg.get("name", "tool")),
						"response": {"content": str(msg.get("content", ""))},
					},
				}],
			})
			continue
		if role == "assistant" and msg.has("tool_calls"):
			var parts: Array = []
			if str(msg.get("content", "")) != "":
				parts.append({"text": str(msg.get("content", ""))})
			for call in msg.get("tool_calls", []):
				var fn: Dictionary = call.get("function", {})
				var args: Variant = JSON.parse_string(str(fn.get("arguments", "{}")))
				parts.append({
					"functionCall": {
						"name": str(fn.get("name", "")),
						"args": args if typeof(args) == TYPE_DICTIONARY else {},
					},
				})
			out.append({"role": "model", "parts": parts})
			continue
		out.append({
			"role": "model" if role == "assistant" else "user",
			"parts": [{"text": str(msg.get("content", ""))}],
		})
	return out


func _to_decls(tools: Array) -> Array:
	var out: Array = []
	for tool in tools:
		var fn: Dictionary = tool.get("function", {})
		out.append({
			"name": fn.get("name", ""),
			"description": fn.get("description", ""),
			"parameters": fn.get("parameters", {"type": "object", "properties": {}}),
		})
	return out


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var listing := _listing
	_busy = false
	_listing = false
	var text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		if listing:
			models_failed.emit("Network error (%d)." % result)
		else:
			failed.emit("Network error (%d)." % result)
		return
	var parsed: Variant = JSON.parse_string(text)
	if code < 200 or code >= 300:
		var msg := "Gemini HTTP %d: %s" % [code, LumenJson.clamp_text(text, 800)]
		if listing:
			models_failed.emit(msg)
		else:
			failed.emit(msg)
		return
	if listing:
		models_listed.emit(_model_names(parsed))
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		failed.emit("Gemini returned non-JSON.")
		return
	finished.emit(_to_openai_shape(parsed))


func _model_names(parsed: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var rows: Variant = parsed.get("models", parsed.get("data", []))
	if typeof(rows) != TYPE_ARRAY:
		return out
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var methods: Variant = row.get("supportedGenerationMethods", [])
		if typeof(methods) == TYPE_ARRAY and methods.size() > 0:
			var can_gen := false
			for m in methods:
				if str(m) == "generateContent":
					can_gen = true
					break
			if not can_gen:
				continue
		var name := str(row.get("name", row.get("id", ""))).strip_edges()
		# API returns "models/gemini-2.5-flash" — strip prefix for chat ids.
		if name.begins_with("models/"):
			name = name.substr(7)
		if name != "":
			out.append(name)
	return out


func _to_openai_shape(raw: Dictionary) -> Dictionary:
	var content := ""
	var tool_calls: Array = []
	var cands: Array = raw.get("candidates", [])
	if not cands.is_empty() and typeof(cands[0]) == TYPE_DICTIONARY:
		for part in cands[0].get("content", {}).get("parts", []):
			if typeof(part) != TYPE_DICTIONARY:
				continue
			if part.has("text"):
				content += str(part.get("text", ""))
			if part.has("functionCall"):
				var fc: Dictionary = part.get("functionCall", {})
				tool_calls.append({
					"id": "gemini-%s" % str(fc.get("name", "")),
					"type": "function",
					"function": {
						"name": str(fc.get("name", "")),
						"arguments": JSON.stringify(fc.get("args", {})),
					},
				})
	var message := {"role": "assistant", "content": content}
	if not tool_calls.is_empty():
		message["tool_calls"] = tool_calls
	return {
		"choices": [{
			"message": message,
			"finish_reason": "tool_calls" if not tool_calls.is_empty() else "stop",
		}],
		"raw_provider": "gemini",
	}

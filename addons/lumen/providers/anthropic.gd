@tool
class_name LumenAnthropic
extends RefCounted

## Thin Anthropic Messages adapter. Converts to the same internal result shape
## the agent loop uses for OpenAI-compatible providers.

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



func list_models(api_key: String, use_oauth: bool = false) -> void:
	if _busy:
		models_failed.emit("Provider is already running a request.")
		return
	if api_key == "":
		models_failed.emit("Anthropic credential is empty.")
		return
	_busy = true
	_listing = true
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"anthropic-version: 2023-06-01",
	])
	if use_oauth:
		headers.append("Authorization: Bearer %s" % api_key)
		headers.append("anthropic-beta: oauth-2025-04-20")
	else:
		headers.append("x-api-key: %s" % api_key)
	var err := http.request(
		"https://api.anthropic.com/v1/models",
		headers,
		HTTPClient.METHOD_GET
	)
	if err != OK:
		_busy = false
		_listing = false
		models_failed.emit("Model list failed: %s" % error_string(err))


func chat(api_key: String, model: String, system: String, messages: Array, tools: Array, max_tokens: int, temperature: float, use_oauth: bool = false, think: bool = false) -> void:
	if _busy:
		failed.emit("Provider is already running a request.")
		return
	if api_key == "":
		failed.emit("Anthropic credential is empty. Use an API key or a Claude Code CLI session.")
		return
	_busy = true
	_listing = false
	var out_tokens := maxi(max_tokens, 1024)
	var payload := {
		"model": model if model != "" else "claude-sonnet-4-5",
		"max_tokens": out_tokens,
		"temperature": temperature,
		"system": system,
		"messages": _to_anthropic_messages(messages),
	}
	if think:
		# docs.claude.com: thinking.budget_tokens >= 1024 and < max_tokens
		var budget := mini(4096, out_tokens - 1024)
		if budget >= 1024:
			payload["thinking"] = {"type": "enabled", "budget_tokens": budget}
			payload["temperature"] = 1.0
	if not tools.is_empty():
		payload["tools"] = _to_anthropic_tools(tools)
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"anthropic-version: 2023-06-01",
	])
	if use_oauth:
		headers.append("Authorization: Bearer %s" % api_key)
		headers.append("anthropic-beta: oauth-2025-04-20")
	else:
		headers.append("x-api-key: %s" % api_key)
	var err := http.request(
		"https://api.anthropic.com/v1/messages",
		headers,
		HTTPClient.METHOD_POST,
		JSON.stringify(payload)
	)
	if err != OK:
		_busy = false
		failed.emit("HTTP request failed: %s" % error_string(err))


func _to_anthropic_messages(messages: Array) -> Array:
	var out: Array = []
	for msg in messages:
		var role := str(msg.get("role", "user"))
		if role == "system":
			continue
		if role == "tool":
			out.append({
				"role": "user",
				"content": [{
					"type": "tool_result",
					"tool_use_id": str(msg.get("tool_call_id", "")),
					"content": str(msg.get("content", "")),
				}],
			})
			continue
		if role == "assistant" and msg.has("tool_calls"):
			var blocks: Array = []
			if str(msg.get("content", "")) != "":
				blocks.append({"type": "text", "text": str(msg.get("content", ""))})
			for call in msg.get("tool_calls", []):
				var fn: Dictionary = call.get("function", {})
				var args: Variant = JSON.parse_string(str(fn.get("arguments", "{}")))
				blocks.append({
					"type": "tool_use",
					"id": str(call.get("id", "")),
					"name": str(fn.get("name", "")),
					"input": args if typeof(args) == TYPE_DICTIONARY else {},
				})
			out.append({"role": "assistant", "content": blocks})
			continue
		out.append({"role": role, "content": str(msg.get("content", ""))})
	return out


func _to_anthropic_tools(tools: Array) -> Array:
	var out: Array = []
	for tool in tools:
		var fn: Dictionary = tool.get("function", {})
		out.append({
			"name": fn.get("name", ""),
			"description": fn.get("description", ""),
			"input_schema": fn.get("parameters", {"type": "object", "properties": {}}),
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
		var msg := "Anthropic HTTP %d: %s" % [code, LumenJson.clamp_text(text, 800)]
		if listing:
			models_failed.emit(msg)
		else:
			failed.emit(msg)
		return
	if listing:
		models_listed.emit(_model_names(parsed))
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		failed.emit("Anthropic returned non-JSON.")
		return
	finished.emit(_to_openai_shape(parsed))


func _model_names(parsed: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(parsed) != TYPE_DICTIONARY:
		return out
	var rows: Variant = parsed.get("data", parsed.get("models", []))
	if typeof(rows) != TYPE_ARRAY:
		return out
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			var id := str(row.get("id", row.get("name", "")))
			if id != "":
				out.append(id)
		elif str(row) != "":
			out.append(str(row))
	return out


func _to_openai_shape(raw: Dictionary) -> Dictionary:
	var content := ""
	var tool_calls: Array = []
	for block in raw.get("content", []):
		if typeof(block) != TYPE_DICTIONARY:
			continue
		match str(block.get("type", "")):
			"text":
				content += str(block.get("text", ""))
			"tool_use":
				tool_calls.append({
					"id": str(block.get("id", "")),
					"type": "function",
					"function": {
						"name": str(block.get("name", "")),
						"arguments": JSON.stringify(block.get("input", {})),
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
		"raw_provider": "anthropic",
	}

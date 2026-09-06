@tool
class_name LumenGemini
extends RefCounted

signal finished(result: Dictionary)
signal failed(message: String)

var http: HTTPRequest
var log: LumenLogger
var _busy := false

func attach(host: Node, p_log: LumenLogger) -> void:
	log = p_log
	http = HTTPRequest.new()
	http.timeout = 180
	http.use_threads = true
	host.add_child(http)
	http.request_completed.connect(_on_completed)

func chat(token: String, api_key: String, model: String, messages: Array, tools: Array, max_tokens: int, temperature: float) -> void:
	if _busy:
		failed.emit("Provider is already running a request.")
		return
	if token == "" and api_key == "":
		failed.emit("No Gemini CLI session and no GEMINI_API_KEY.")
		return
	_busy = true
	var id := model if model != "" else "gemini-2.5-flash"
	var url := "https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % id
	var headers := PackedStringArray(["Content-Type: application/json"])
	if token != "":
		headers.append("Authorization: Bearer %s" % token)
	elif api_key != "":
		headers.append("x-goog-api-key: %s" % api_key)
	var payload := {
		"contents": _to_contents(messages),
		"generationConfig": {"temperature": temperature, "maxOutputTokens": max_tokens},
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
			out.append({"role": "user", "parts": [{"functionResponse": {"name": str(msg.get("name", "tool")), "response": {"content": str(msg.get("content", ""))}}}]})
			continue
		if role == "assistant" and msg.has("tool_calls"):
			var parts: Array = []
			if str(msg.get("content", "")) != "":
				parts.append({"text": str(msg.get("content", ""))})
			for call in msg.get("tool_calls", []):
				var fn: Dictionary = call.get("function", {})
				var args: Variant = JSON.parse_string(str(fn.get("arguments", "{}")))
				parts.append({"functionCall": {"name": str(fn.get("name", "")), "args": args if typeof(args) == TYPE_DICTIONARY else {}}})
			out.append({"role": "model", "parts": parts})
			continue
		out.append({"role": "model" if role == "assistant" else "user", "parts": [{"text": str(msg.get("content", ""))}]})
	return out

func _to_decls(tools: Array) -> Array:
	var out: Array = []
	for tool in tools:
		var fn: Dictionary = tool.get("function", {})
		out.append({"name": fn.get("name", ""), "description": fn.get("description", ""), "parameters": fn.get("parameters", {"type": "object", "properties": {}})})
	return out

func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_busy = false
	var text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		failed.emit("Network error (%d)." % result)
		return
	var parsed: Variant = JSON.parse_string(text)
	if code < 200 or code >= 300:
		failed.emit("Gemini HTTP %d: %s" % [code, LumenJson.clamp_text(text, 800)])
		return
	if typeof(parsed) != TYPE_DICTIONARY:
		failed.emit("Gemini returned non-JSON.")
		return
	finished.emit(_to_openai_shape(parsed))

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
				tool_calls.append({"id": "gemini-%s" % str(fc.get("name", "")), "type": "function", "function": {"name": str(fc.get("name", "")), "arguments": JSON.stringify(fc.get("args", {}))}})
	var message := {"role": "assistant", "content": content}
	if not tool_calls.is_empty():
		message["tool_calls"] = tool_calls
	return {"choices": [{"message": message, "finish_reason": "tool_calls" if not tool_calls.is_empty() else "stop"}], "raw_provider": "gemini"}

@tool
class_name LumenCodexSubscription
extends RefCounted

## Uses the ChatGPT session created by `codex login`.
## Tokens are read from ~/.codex/auth.json. Nothing is sent to a Lumen server.

signal finished(result: Dictionary)
signal failed(message: String)

const BACKEND := "https://chatgpt.com/backend-api/codex/responses"
const REFRESH := "https://auth.openai.com/oauth/token"
const CLIENT_ID := "app_EMoamEEZ73f0CkXaXp7hrann"

var http: HTTPRequest
var log: LumenLogger
var cli: LumenCliAuth
var _busy := false
var _phase := ""
var _pending: Dictionary = {}


func attach(host: Node, p_log: LumenLogger, p_cli: LumenCliAuth) -> void:
	log = p_log
	cli = p_cli
	http = HTTPRequest.new()
	http.timeout = 180
	http.use_threads = true
	host.add_child(http)
	http.request_completed.connect(_on_completed)


func chat(model: String, messages: Array, tools: Array, max_tokens: int, temperature: float) -> void:
	if _busy:
		failed.emit("Provider is already running a request.")
		return
	var creds := cli.load_codex_tokens()
	if not bool(creds.get("ok", false)):
		failed.emit("No Codex session. Install the Codex CLI and click Login, or run `codex login`.")
		return
	_pending = {
		"model": model if model != "" else "gpt-5.3-codex",
		"messages": messages,
		"tools": tools,
		"max_tokens": max_tokens,
		"temperature": temperature,
		"creds": creds,
	}
	_busy = true
	if str(creds.get("access_token", "")) != "" and cli.jwt_expired(str(creds.get("access_token", ""))):
		_start_refresh(creds)
	else:
		_start_chat(creds)


func _start_refresh(creds: Dictionary) -> void:
	var refresh := str(creds.get("refresh_token", ""))
	if refresh == "":
		_busy = false
		failed.emit("Codex access token expired and no refresh token is stored. Run `codex login`.")
		return
	_phase = "refresh"
	var err := http.request(
		REFRESH,
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify({
			"client_id": CLIENT_ID,
			"grant_type": "refresh_token",
			"refresh_token": refresh,
		})
	)
	if err != OK:
		_busy = false
		failed.emit("Codex refresh request failed: %s" % error_string(err))


func _start_chat(creds: Dictionary) -> void:
	_phase = "chat"
	var access := str(creds.get("access_token", ""))
	var api_key := str(creds.get("api_key", ""))
	var token := access if access != "" else api_key
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Accept: application/json",
		"Authorization: Bearer %s" % token,
		"OpenAI-Beta: responses=experimental",
		"originator: lumen-godot",
	])
	var account := str(creds.get("account_id", ""))
	if account != "":
		headers.append("ChatGPT-Account-ID: %s" % account)
	var payload := {
		"model": _pending.get("model", "gpt-5.3-codex"),
		"instructions": _system_text(_pending.get("messages", [])),
		"input": _to_input(_pending.get("messages", [])),
		"tools": _to_tools(_pending.get("tools", [])),
		"max_output_tokens": int(_pending.get("max_tokens", 4096)),
		"store": false,
	}
	var err := http.request(BACKEND, headers, HTTPClient.METHOD_POST, JSON.stringify(payload))
	if err != OK:
		_busy = false
		failed.emit("Codex request failed: %s" % error_string(err))


func _on_completed(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var text := body.get_string_from_utf8()
	if result != HTTPRequest.RESULT_SUCCESS:
		_busy = false
		failed.emit("Network error (%d)." % result)
		return
	if _phase == "refresh":
		_finish_refresh(code, text)
		return
	if code == 401 and str(_pending.get("creds", {}).get("refresh_token", "")) != "":
		_start_refresh(_pending.get("creds", {}))
		return
	_busy = false
	if code < 200 or code >= 300:
		failed.emit("Codex HTTP %d: %s" % [code, LumenJson.clamp_text(text, 800)])
		return
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		failed.emit("Codex returned non-JSON.")
		return
	finished.emit(_to_openai_shape(parsed))


func _finish_refresh(code: int, text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if code < 200 or code >= 300 or typeof(parsed) != TYPE_DICTIONARY:
		_busy = false
		failed.emit("Codex token refresh failed. Run `codex login` again.")
		return
	var creds: Dictionary = _pending.get("creds", {})
	creds["access_token"] = str(parsed.get("access_token", creds.get("access_token", "")))
	if str(parsed.get("refresh_token", "")) != "":
		creds["refresh_token"] = str(parsed.get("refresh_token", ""))
	if str(parsed.get("id_token", "")) != "":
		creds["id_token"] = str(parsed.get("id_token", ""))
	cli.write_codex_tokens(creds)
	_pending["creds"] = creds
	_start_chat(creds)


func _system_text(messages: Array) -> String:
	var out := ""
	for msg in messages:
		if str(msg.get("role", "")) == "system":
			out += str(msg.get("content", "")) + "\n"
	return out.strip_edges()


func _to_input(messages: Array) -> Array:
	var out: Array = []
	for msg in messages:
		var role := str(msg.get("role", "user"))
		if role == "system":
			continue
		if role == "tool":
			out.append({
				"type": "function_call_output",
				"call_id": str(msg.get("tool_call_id", "")),
				"output": str(msg.get("content", "")),
			})
			continue
		if role == "assistant" and msg.has("tool_calls"):
			if str(msg.get("content", "")) != "":
				out.append({"role": "assistant", "content": str(msg.get("content", ""))})
			for call in msg.get("tool_calls", []):
				var fn: Dictionary = call.get("function", {})
				out.append({
					"type": "function_call",
					"call_id": str(call.get("id", "")),
					"name": str(fn.get("name", "")),
					"arguments": str(fn.get("arguments", "{}")),
				})
			continue
		out.append({"role": role, "content": str(msg.get("content", ""))})
	return out


func _to_tools(tools: Array) -> Array:
	var out: Array = []
	for tool in tools:
		var fn: Dictionary = tool.get("function", {})
		out.append({
			"type": "function",
			"name": fn.get("name", ""),
			"description": fn.get("description", ""),
			"parameters": fn.get("parameters", {"type": "object", "properties": {}}),
		})
	return out


func _to_openai_shape(raw: Dictionary) -> Dictionary:
	var content := ""
	var tool_calls: Array = []
	for item in raw.get("output", []):
		if typeof(item) != TYPE_DICTIONARY:
			continue
		match str(item.get("type", "")):
			"message":
				for block in item.get("content", []):
					if typeof(block) == TYPE_DICTIONARY:
						content += str(block.get("text", block.get("output_text", "")))
			"function_call":
				tool_calls.append({
					"id": str(item.get("call_id", item.get("id", ""))),
					"type": "function",
					"function": {
						"name": str(item.get("name", "")),
						"arguments": str(item.get("arguments", "{}")),
					},
				})
	if content == "":
		content = str(raw.get("output_text", ""))
	var message := {"role": "assistant", "content": content}
	if not tool_calls.is_empty():
		message["tool_calls"] = tool_calls
	return {
		"choices": [{
			"message": message,
			"finish_reason": "tool_calls" if not tool_calls.is_empty() else "stop",
		}],
		"raw_provider": "codex_cli",
	}

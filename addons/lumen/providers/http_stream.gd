@tool
class_name LumenHttpStream
extends Node

## Polls HTTPClient so tokens can land in the dock before the turn ends.

signal delta(text: String)
signal finished(result: Dictionary)
signal failed(message: String)

var client := HTTPClient.new()
var _buf := ""
var _acc := ""
var _calls: Array = []
var _busy := false
var _cancelled := false
var _sse := false
var _status_seen := 0


func start(url: String, headers: PackedStringArray, body: String, sse: bool) -> void:
	cancel()
	_busy = true
	_cancelled = false
	_sse = sse
	_buf = ""
	_acc = ""
	_calls = []
	_status_seen = 0
	var parsed := _split_url(url)
	var tls := bool(parsed["tls"])
	var err := client.connect_to_host(str(parsed["host"]), int(parsed["port"]), TLSOptions.client() if tls else null)
	if err != OK:
		_busy = false
		failed.emit("Stream connect failed: %s" % error_string(err))
		return
	set_process(true)
	_headers = headers
	_path = str(parsed["path"])
	_body = body
	_phase = 0


var _headers := PackedStringArray()
var _path := "/"
var _body := ""
var _phase := 0


func cancel() -> void:
	_cancelled = true
	_busy = false
	set_process(false)
	if client.get_status() != HTTPClient.STATUS_DISCONNECTED:
		client.close()


func _process(_delta: float) -> void:
	if not _busy:
		set_process(false)
		return
	client.poll()
	var st := client.get_status()
	if _cancelled:
		set_process(false)
		return
	if st == HTTPClient.STATUS_CONNECTED and _phase == 0:
		var err := client.request(HTTPClient.METHOD_POST, _path, _headers, _body)
		_phase = 1
		if err != OK:
			_finish_err("Stream request failed: %s" % error_string(err))
		return
	if st == HTTPClient.STATUS_BODY:
		_status_seen = client.get_response_code()
		var chunk := client.read_response_body_chunk()
		if chunk.size() > 0:
			_buf += chunk.get_string_from_utf8()
			_drain()
		return
	if st == HTTPClient.STATUS_CONNECTED and _phase == 1:
		_complete()
		return
	if st == HTTPClient.STATUS_DISCONNECTED and _phase == 1:
		_complete()
		return
	if st == HTTPClient.STATUS_CONNECTION_ERROR or st == HTTPClient.STATUS_CANT_CONNECT or st == HTTPClient.STATUS_TLS_HANDSHAKE_ERROR:
		_finish_err("Stream network error (%d)." % st)


func _drain() -> void:
	while true:
		var nl := _buf.find("\n")
		if nl < 0:
			return
		var line := _buf.substr(0, nl).strip_edges()
		_buf = _buf.substr(nl + 1)
		if line == "" or line.begins_with(":"):
			continue
		if _sse:
			if line.begins_with("data:"):
				line = line.substr(5).strip_edges()
			if line == "[DONE]":
				continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		_ingest(parsed as Dictionary)


func _ingest(row: Dictionary) -> void:
	if row.has("error"):
		_finish_err(str(row.get("error", "stream error")))
		return
	if row.has("choices"):
		var choices: Array = row.get("choices", [])
		if choices.is_empty():
			return
		var delta_row: Dictionary = choices[0].get("delta", choices[0].get("message", {}))
		var piece := str(delta_row.get("content", ""))
		if piece != "":
			_acc += piece
			delta.emit(piece)
		var calls: Variant = delta_row.get("tool_calls", [])
		if typeof(calls) == TYPE_ARRAY:
			_merge_calls(calls)
		return
	if row.has("message"):
		var msg: Dictionary = row.get("message", {})
		var piece := str(msg.get("content", ""))
		if piece != "":
			_acc += piece
			delta.emit(piece)
		var calls: Variant = msg.get("tool_calls", [])
		if typeof(calls) == TYPE_ARRAY and not (calls as Array).is_empty():
			_calls = calls
		if bool(row.get("done", false)):
			_complete()


func _merge_calls(calls: Array) -> void:
	for call in calls:
		if typeof(call) != TYPE_DICTIONARY:
			continue
		var idx := int(call.get("index", _calls.size()))
		while _calls.size() <= idx:
			_calls.append({"function": {"name": "", "arguments": ""}})
		var slot: Dictionary = _calls[idx]
		var fn: Dictionary = slot.get("function", {})
		var incoming: Dictionary = call.get("function", {})
		if str(incoming.get("name", "")) != "":
			fn["name"] = str(incoming.get("name"))
		fn["arguments"] = str(fn.get("arguments", "")) + str(incoming.get("arguments", ""))
		slot["function"] = fn
		if call.has("id"):
			slot["id"] = call.get("id")
		_calls[idx] = slot


func _complete() -> void:
	if not _busy:
		return
	_busy = false
	set_process(false)
	if _status_seen >= 400:
		_finish_err("Provider HTTP %d." % _status_seen)
		return
	var message := {"role": "assistant", "content": _acc}
	if not _calls.is_empty():
		message["tool_calls"] = _calls
	finished.emit({"choices": [{"message": message, "finish_reason": "tool_calls" if not _calls.is_empty() else "stop"}]})
	client.close()


func _finish_err(message: String) -> void:
	_busy = false
	set_process(false)
	client.close()
	failed.emit(message)


func _split_url(url: String) -> Dictionary:
	var tls := url.begins_with("https://")
	var rest := url.trim_prefix("https://").trim_prefix("http://")
	var slash := rest.find("/")
	var hostport := rest if slash < 0 else rest.substr(0, slash)
	var path := "/" if slash < 0 else rest.substr(slash)
	var host := hostport
	var port := 443 if tls else 80
	if ":" in hostport:
		var parts := hostport.split(":")
		host = parts[0]
		port = int(parts[1])
	return {"host": host, "port": port, "path": path, "tls": tls}

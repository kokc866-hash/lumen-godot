@tool
class_name LumenToolParse
extends RefCounted

## Local models (Qwen Coder, llama.cpp) often emit tool JSON in content
## instead of the OpenAI tool_calls array. Recover those so the loop continues.


static func from_content(text: String) -> Array:
	var out: Array = []
	if text.strip_edges() == "":
		return out
	out.append_array(_from_tags(text, "tool_call"))
	if not out.is_empty():
		return out
	out.append_array(_from_tags(text, "tools"))
	if not out.is_empty():
		return out
	out.append_array(_from_fences(text))
	if not out.is_empty():
		return out
	var bare: Variant = JSON.parse_string(text.strip_edges())
	return _normalize(bare)


static func _from_tags(text: String, tag: String) -> Array:
	var out: Array = []
	var open := "<%s>" % tag
	var close := "</%s>" % tag
	var from := 0
	while true:
		var a := text.find(open, from)
		if a < 0:
			break
		var b := text.find(close, a)
		if b < 0:
			break
		var inner := text.substr(a + open.length(), b - a - open.length()).strip_edges()
		out.append_array(_normalize(JSON.parse_string(inner)))
		from = b + close.length()
	return out


static func _from_fences(text: String) -> Array:
	var out: Array = []
	var from := 0
	while true:
		var a := text.find("```", from)
		if a < 0:
			break
		var nl := text.find("\n", a)
		var b := text.find("```", a + 3)
		if nl < 0 or b < 0:
			break
		var inner := text.substr(nl + 1, b - nl - 1).strip_edges()
		out.append_array(_normalize(JSON.parse_string(inner)))
		from = b + 3
	return out


static func _normalize(parsed: Variant) -> Array:
	var out: Array = []
	if typeof(parsed) == TYPE_ARRAY:
		for row in parsed:
			var call := _one(row)
			if not call.is_empty():
				out.append(call)
	elif typeof(parsed) == TYPE_DICTIONARY:
		var call := _one(parsed)
		if not call.is_empty():
			out.append(call)
	return out


static func _one(row: Variant) -> Dictionary:
	if typeof(row) != TYPE_DICTIONARY:
		return {}
	var d: Dictionary = row
	var name := str(d.get("name", d.get("tool", "")))
	if name == "" and typeof(d.get("function", null)) == TYPE_DICTIONARY:
		var fn: Dictionary = d.get("function")
		name = str(fn.get("name", ""))
		if not d.has("arguments"):
			d["arguments"] = fn.get("arguments", {})
	if name == "":
		return {}
	var args: Variant = d.get("arguments", d.get("parameters", {}))
	if typeof(args) == TYPE_STRING:
		var parsed: Variant = JSON.parse_string(str(args))
		args = parsed if typeof(parsed) == TYPE_DICTIONARY else {}
	if typeof(args) != TYPE_DICTIONARY:
		args = {}
	return {
		"id": "local-%s-%d" % [name, Time.get_ticks_msec()],
		"type": "function",
		"function": {
			"name": name,
			"arguments": JSON.stringify(args),
		},
	}

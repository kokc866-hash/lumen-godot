@tool
class_name LumenToolRegistry
extends RefCounted

var _tools: Dictionary = {}


func register_tool(spec: LumenToolSpec) -> void:
	_tools[spec.name] = spec


func get_tool(name: String) -> LumenToolSpec:
	return _tools.get(name, null)


func openai_tools() -> Array:
	var out: Array = []
	var names: Array = _tools.keys()
	names.sort()
	for name in names:
		out.append((_tools[name] as LumenToolSpec).openai_schema())
	return out


func is_readonly(name: String) -> bool:
	var spec: LumenToolSpec = _tools.get(name, null)
	return spec != null and spec.readonly


func has(name: String) -> bool:
	return _tools.has(name)


func names() -> PackedStringArray:
	var out := PackedStringArray()
	for name in _tools.keys():
		out.append(str(name))
	out.sort()
	return out


func run(name: String, args: Dictionary) -> Dictionary:
	var spec: LumenToolSpec = _tools.get(name, null)
	if spec == null:
		return {"ok": false, "error": "Unknown tool: %s" % name}
	var result: Variant = spec.callback.call(args)
	if typeof(result) != TYPE_DICTIONARY:
		return {"ok": true, "result": result}
	return result

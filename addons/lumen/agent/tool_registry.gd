@tool
class_name LumenToolRegistry
extends RefCounted

var _tools: Dictionary = {}
var enabled_extra: Array = []


const EXTRA := [
	"delete_file", "move_path", "reparent_node",
	"get_project_setting", "set_project_setting",
	"run_scene", "stop_scene", "playtest_batch",
	"capture_screenshot", "run_tests",
	"set_tile_cell", "get_tile_state", "fill_tiles", "erase_tiles",
	"generate_image", "search_godot_docs_hint",
]


func mark_extras() -> void:
	for name in EXTRA:
		var spec: LumenToolSpec = _tools.get(name, null)
		if spec:
			spec.group = "extra"


func register_meta() -> void:
	register_tool(LumenToolSpec.new(
		"list_more_tools",
		"List extra editor tools not in the compact local set. Call enable_tools to add some.",
		{"type": "object", "properties": {}},
		true,
		list_more_tools
	))
	register_tool(LumenToolSpec.new(
		"enable_tools",
		"Add named extra tools to this session. Use names from list_more_tools.",
		{
			"type": "object",
			"properties": {"names": {"type": "array", "items": {"type": "string"}}},
			"required": ["names"],
		},
		true,
		enable_tools
	))


func list_more_tools(_args: Dictionary) -> Dictionary:
	return {"ok": true, "tools": extra_catalog()}


func enable_tools(args: Dictionary) -> Dictionary:
	var added: Array = []
	var names: Variant = args.get("names", [])
	if typeof(names) != TYPE_ARRAY:
		return {"ok": false, "error": "names must be an array of tool ids."}
	for name in names:
		var id := str(name)
		if not _tools.has(id):
			continue
		if id not in enabled_extra:
			enabled_extra.append(id)
		added.append(id)
	return {"ok": true, "enabled": added}


func register_tool(spec: LumenToolSpec) -> void:
	_tools[spec.name] = spec


func get_tool(name: String) -> LumenToolSpec:
	return _tools.get(name, null)


const CORE := [
	"get_project_info", "get_scene_tree", "read_file", "list_dir",
	"search_project", "get_errors", "write_file", "edit_file",
	"create_node", "set_node_property", "delete_node",
	"attach_script", "open_scene", "save_scene", "load_skill",
	"list_more_tools", "enable_tools",
]


func openai_tools(compact: bool = false, extra_names: Array = []) -> Array:
	var out: Array = []
	var names: Array = _tools.keys()
	names.sort()
	for name in names:
		var spec: LumenToolSpec = _tools[name]
		if compact and spec.group != "core" and str(name) not in CORE and str(name) not in extra_names and str(name) not in enabled_extra:
			continue
		out.append(spec.openai_schema())
	return out


func extra_catalog() -> Array:
	var out: Array = []
	var names: Array = _tools.keys()
	names.sort()
	for name in names:
		var spec: LumenToolSpec = _tools[name]
		if spec.group == "core" or str(name) in CORE:
			continue
		out.append({"name": spec.name, "description": spec.description, "readonly": spec.readonly})
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

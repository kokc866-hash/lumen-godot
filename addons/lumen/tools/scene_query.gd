@tool
class_name LumenSceneQuery
extends RefCounted

## Replaces get_scene_tree so name/type/group filters work even if
## an older builtin_tools.gd is installed. Also adds find_nodes_in_group.


func register(registry: LumenToolRegistry) -> void:
	registry.register_tool(LumenToolSpec.new(
		"get_scene_tree",
		"Inspect the edited scene. Filter by path, name, type, group, depth, limit.",
		_schema({
			"path": {"type": "string", "description": "Start node from scene root"},
			"name": {"type": "string", "description": "Substring match on node name"},
			"type": {"type": "string", "description": "Class name, e.g. CharacterBody2D"},
			"group": {"type": "string"},
			"depth": {"type": "integer", "description": "Max depth from start, default 12"},
			"limit": {"type": "integer", "description": "Max nodes, default 400"},
		}, ["path", "name", "type", "group", "depth", "limit"]),
		true,
		get_scene_tree
	))
	registry.register_tool(LumenToolSpec.new(
		"find_nodes_in_group",
		"List nodes in a group in the edited scene.",
		_schema({"group": {"type": "string"}}, [], ["group"]),
		true,
		find_nodes_in_group
	))
	registry.register_tool(LumenToolSpec.new(
		"get_errors",
		"Playing state, open scripts, godot.log hits, live debugger capture.",
		_schema({}),
		true,
		get_errors
	))


func get_scene_tree(args: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "No edited scene."}
	var start := root
	var path := str(args.get("path", ""))
	if path != "":
		start = root.get_node_or_null(NodePath(path))
		if start == null:
			return {"ok": false, "error": "Node not found: %s" % path}
	var filt := {
		"name": str(args.get("name", "")).to_lower(),
		"type": str(args.get("type", "")),
		"group": str(args.get("group", "")),
	}
	var max_depth := clampi(int(args.get("depth", 12)), 1, 32)
	var limit := clampi(int(args.get("limit", 400)), 1, 800)
	var filtered: bool = str(filt.get("name", "")) != "" or str(filt.get("type", "")) != "" or str(filt.get("group", "")) != ""
	if filtered:
		var matches: Array = []
		_collect(start, root, filt, 0, max_depth, matches, limit)
		return {"ok": true, "matches": matches, "count": matches.size()}
	return {"ok": true, "tree": _walk(start, root, 0, max_depth, limit)}


func find_nodes_in_group(args: Dictionary) -> Dictionary:
	return get_scene_tree({"group": str(args.get("group", "")), "limit": 400})


func get_errors(_args: Dictionary) -> Dictionary:
	var open_scripts: Array = []
	var se := EditorInterface.get_script_editor()
	if se:
		for script in se.get_open_scripts():
			if script:
				open_scripts.append(script.resource_path)
	var log_hits: Array = []
	for log_path in [
		OS.get_user_data_dir().path_join("logs/godot.log"),
		ProjectSettings.globalize_path("user://logs/godot.log"),
	]:
		if not FileAccess.file_exists(log_path):
			continue
		var lines := FileAccess.get_file_as_string(log_path).split("\n")
		var start := maxi(0, lines.size() - 250)
		for i in range(start, lines.size()):
			var line := lines[i]
			var lower := line.to_lower()
			if "error" in lower or "warning" in lower or "script error" in lower or "parse error" in lower:
				log_hits.append(line.strip_edges())
				if log_hits.size() >= 40:
					break
		break
	return {
		"ok": true,
		"open_scripts": open_scripts,
		"log_hits": log_hits,
		"playing": EditorInterface.is_playing_scene(),
		"playing_scene": EditorInterface.get_playing_scene(),
		"debugger": LumenDebuggerPlugin.snapshot(),
	}


func _walk(node: Node, root: Node, depth: int, max_depth: int, budget: int) -> Dictionary:
	var kids: Array = []
	var used := 1
	if depth < max_depth:
		for child in node.get_children():
			if used >= budget:
				kids.append({"truncated": true})
				break
			var branch := _walk(child, root, depth + 1, max_depth, budget - used)
			used += int(branch.get("_used", 1))
			kids.append(branch)
	var out := {
		"name": node.name,
		"type": node.get_class(),
		"path": str(root.get_path_to(node)),
		"groups": node.get_groups(),
		"children": kids,
	}
	if node is CanvasItem:
		out["visible"] = (node as CanvasItem).visible
	if node is Node3D:
		var n3 := node as Node3D
		out["x"] = n3.position.x
		out["y"] = n3.position.y
		out["z"] = n3.position.z
	out["_used"] = used
	return out


func _collect(node: Node, root: Node, filt: Dictionary, depth: int, max_depth: int, matches: Array, limit: int) -> void:
	if matches.size() >= limit or depth > max_depth:
		return
	var ok := true
	if filt["name"] != "" and str(node.name).to_lower().find(filt["name"]) < 0:
		ok = false
	if ok and filt["type"] != "" and node.get_class() != filt["type"] and not node.is_class(filt["type"]):
		ok = false
	if ok and filt["group"] != "" and not node.is_in_group(filt["group"]):
		ok = false
	if ok:
		matches.append({
			"name": node.name,
			"type": node.get_class(),
			"path": str(root.get_path_to(node)),
			"groups": node.get_groups(),
		})
	for child in node.get_children():
		_collect(child, root, filt, depth + 1, max_depth, matches, limit)


func _schema(properties: Dictionary, optional: Array = [], required: Array = []) -> Dictionary:
	var req: Array = required
	if req.is_empty():
		for key in properties.keys():
			if key not in optional:
				req.append(key)
	return {"type": "object", "properties": properties, "required": req}

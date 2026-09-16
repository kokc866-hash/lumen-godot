@tool
class_name LumenObserve
extends RefCounted

## Anvil-style loop, Lumen-owned: observe, act, observe_diff, validate.


func register(registry: LumenToolRegistry) -> void:
	registry.register_tool(LumenToolSpec.new(
		"observe",
		"Compact editor truth: scene, selection, play, errors, last playtest. Call before a big change.",
		{"type": "object", "properties": {}},
		true,
		obseserve if false else observe
	))
	registry.register_tool(LumenToolSpec.new(
		"observe_diff",
		"What changed since the last observe call.",
		{"type": "object", "properties": {}},
		true,
		obseserve_diff if false else observe_diff
	))
	registry.register_tool(LumenToolSpec.new(
		"capabilities",
		"What this Lumen session can do right now: tools, image/mesh backends, MCP, play.",
		{"type": "object", "properties": {}},
		true,
		capabilities
	))
	registry.register_tool(LumenToolSpec.new(
		"validate_script",
		"Parse a res:// .gd file. Use after write_file / edit_file.",
		{
			"type": "object",
			"properties": {"path": {"type": "string"}},
			"required": ["path"],
		},
		true,
		validate_script
	))


func observe(_args: Dictionary) -> Dictionary:
	var snap := _snap()
	LumenJson.write_file("user://lumen/last_observe.json", snap)
	return {"ok": true, "observe": snap}


func observe_diff(_args: Dictionary) -> Dictionary:
	var prev: Variant = LumenJson.read_file("user://lumen/last_observe.json", {})
	var now := _snap()
	var before: Dictionary = prev if typeof(prev) == TYPE_DICTIONARY else {}
	var changed: Dictionary = {}
	for key in now.keys():
		if str(now[key]) != str(before.get(key, null)):
			changed[key] = {"from": before.get(key, null), "to": now[key]}
	LumenJson.write_file("user://lumen/last_observe.json", now)
	return {"ok": true, "changed": changed, "keys": changed.keys()}


func capabilities(_args: Dictionary) -> Dictionary:
	return {
		"ok": true,
		"godot": Engine.get_version_info(),
		"playing": EditorInterface.is_playing_scene(),
		"mcp_script": "res://addons/lumen/mcp/stdio_bridge.py",
		"loop": ["observe", "tool", "validate_script", "observe_diff", "playtest_record"],
		"image_hint": "retro | openai | fal | local — from Image URL",
		"mesh_hint": "meshy | tripo | fal — from Mesh URL",
	}


func validate_script(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", "")).strip_edges()
	if not path.begins_with("res://") or not path.ends_with(".gd"):
		return {"ok": false, "error": "Path must be res://…gd"}
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Missing file."}
	var script := GDScript.new()
	script.source_code = FileAccess.get_file_as_string(path)
	var err := script.reload()
	if err != OK:
		return {"ok": false, "path": path, "error": error_string(err)}
	return {"ok": true, "path": path, "parsed": true}


func _snap() -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var kids: Array = []
	if root:
		for child in root.get_children():
			kids.append("%s:%s" % [child.name, child.get_class()])
			if kids.size() >= 20:
				break
	var selected: Array = []
	var sel := EditorInterface.get_selection()
	if sel:
		for node in sel.get_selected_nodes():
			selected.append("%s:%s" % [node.name, node.get_class()])
	var errors: Array = []
	var log_path := OS.get_user_data_dir().path_join("logs/godot.log")
	if FileAccess.file_exists(log_path):
		var lines := FileAccess.get_file_as_string(log_path).split("\n")
		var start := maxi(0, lines.size() - 40)
		for i in range(start, lines.size()):
			if "error" in lines[i].to_lower():
				errors.append(lines[i].strip_edges())
				if errors.size() >= 8:
					break
	return {
		"scene": root.scene_file_path if root else "",
		"root": ("%s:%s" % [root.name, root.get_class()]) if root else "",
		"children": kids,
		"selected": selected,
		"playing": EditorInterface.is_playing_scene(),
		"playing_scene": EditorInterface.get_playing_scene(),
		"errors": errors,
		"playtest": FileAccess.file_exists("user://lumen/playtest_report.json"),
		"t": Time.get_unix_time_from_system(),
	}

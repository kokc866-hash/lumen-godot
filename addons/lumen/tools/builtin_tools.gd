@tool
class_name LumenBuiltinTools
extends RefCounted

var plugin: EditorPlugin
var settings: LumenSettings
var skills: LumenSkillLoader
var log: LumenLogger
var openai: LumenOpenAICompatible


func _init(p_plugin: EditorPlugin, p_settings: LumenSettings, p_skills: LumenSkillLoader, p_log: LumenLogger) -> void:
	plugin = p_plugin
	settings = p_settings
	skills = p_skills
	log = p_log


func register(registry: LumenToolRegistry) -> void:
	registry.register_tool(LumenToolSpec.new(
		"get_project_info", "Project name, Godot version, edited scene, open scripts.",
		_object_schema({}), true, get_project_info
	))
	registry.register_tool(LumenToolSpec.new(
		"get_scene_tree", "Inspect the edited scene tree. Optional path limits the walk.",
		_object_schema({"path": {"type": "string", "description": "Node path from scene root"}}, ["path"]),
		true, get_scene_tree
	))
	registry.register_tool(LumenToolSpec.new(
		"read_file", "Read a project text file.",
		_object_schema({"path": {"type": "string"}}, [], ["path"]), true, read_file
	))
	registry.register_tool(LumenToolSpec.new(
		"list_dir", "List a directory under res://.",
		_object_schema({"path": {"type": "string", "description": "res:// path"}}, [], ["path"]),
		true, list_dir
	))
	registry.register_tool(LumenToolSpec.new(
		"search_project", "Case-insensitive substring search across text files.",
		_object_schema({
			"query": {"type": "string"},
			"glob": {"type": "string", "description": "Optional suffix filter, e.g. .gd"},
		}, ["glob"], ["query"]),
		true, search_project
	))
	registry.register_tool(LumenToolSpec.new(
		"get_errors", "Editor debugger / script error summary if available, plus recent output hints.",
		_object_schema({}), true, get_errors
	))
	registry.register_tool(LumenToolSpec.new(
		"write_file", "Create or overwrite a text file inside the project. Paths must stay under res://.",
		_object_schema({
			"path": {"type": "string"},
			"content": {"type": "string"},
		}, [], ["path", "content"]),
		false, write_file
	))
	registry.register_tool(LumenToolSpec.new(
		"edit_file", "Replace one exact occurrence of old_string with new_string in a file.",
		_object_schema({
			"path": {"type": "string"},
			"old_string": {"type": "string"},
			"new_string": {"type": "string"},
			"replace_all": {"type": "boolean"},
		}, ["replace_all"], ["path", "old_string", "new_string"]),
		false, edit_file
	))
	registry.register_tool(LumenToolSpec.new(
		"delete_file", "Delete a file under res://.",
		_object_schema({"path": {"type": "string"}}, [], ["path"]), false, delete_file
	))
	registry.register_tool(LumenToolSpec.new(
		"move_path", "Rename or move a file under res://.",
		_object_schema({
			"from": {"type": "string"},
			"to": {"type": "string"},
		}, [], ["from", "to"]),
		false, move_path
	))
	registry.register_tool(LumenToolSpec.new(
		"create_node", "Add a child node under a parent in the edited scene.",
		_object_schema({
			"parent": {"type": "string", "description": "Node path, empty = scene root"},
			"type": {"type": "string", "description": "Class name, e.g. Node2D"},
			"name": {"type": "string"},
		}, [], ["type", "name"]),
		false, create_node
	))
	registry.register_tool(LumenToolSpec.new(
		"set_node_property", "Set a property on a node in the edited scene.",
		_object_schema({
			"path": {"type": "string"},
			"property": {"type": "string"},
			"value": {"description": "JSON value"},
		}, [], ["path", "property"]),
		false, set_node_property
	))
	registry.register_tool(LumenToolSpec.new(
		"delete_node", "Free a node in the edited scene. Cannot delete the root.",
		_object_schema({"path": {"type": "string"}}, [], ["path"]), false, delete_node
	))
	registry.register_tool(LumenToolSpec.new(
		"reparent_node", "Move a node under a new parent.",
		_object_schema({
			"path": {"type": "string"},
			"new_parent": {"type": "string"},
		}, [], ["path", "new_parent"]),
		false, reparent_node
	))
	registry.register_tool(LumenToolSpec.new(
		"get_project_setting", "Read a ProjectSettings key.",
		_object_schema({"key": {"type": "string"}}, [], ["key"]), true, get_project_setting
	))
	registry.register_tool(LumenToolSpec.new(
		"set_project_setting", "Write a ProjectSettings key. Does not persist editor UI settings.",
		_object_schema({
			"key": {"type": "string"},
			"value": {},
		}, [], ["key"]),
		false, set_project_setting
	))
	registry.register_tool(LumenToolSpec.new(
		"run_scene", "Play the edited or named scene in the editor.",
		_object_schema({"path": {"type": "string", "description": "Optional .tscn path"}}, ["path"]),
		false, run_scene
	))
	registry.register_tool(LumenToolSpec.new(
		"stop_scene", "Stop the running play session.",
		_object_schema({}), false, stop_scene
	))
	registry.register_tool(LumenToolSpec.new(
		"playtest_batch", "Write a playtest sidecar and start the scene. Inputs are replayed by the harness.",
		_object_schema({
			"scene": {"type": "string"},
			"inputs": {"type": "array", "description": "[{type,key|button,pressed,x,y,wait_ms}]"},
			"duration_ms": {"type": "number"},
		}, ["scene", "duration_ms"], ["inputs"]),
		false, playtest_batch
	))
	registry.register_tool(LumenToolSpec.new(
		"capture_screenshot", "Capture the editor 2D/3D viewport to a PNG under res://.lumen/captures/.",
		_object_schema({"name": {"type": "string"}}, ["name"]), false, capture_screenshot
	))
	registry.register_tool(LumenToolSpec.new(
		"run_tests", "Run a test scene if configured, otherwise list likely test scripts.",
		_object_schema({"scene": {"type": "string"}}, ["scene"]), false, run_tests
	))
	registry.register_tool(LumenToolSpec.new(
		"set_tile_cell", "Set one TileMapLayer cell in the edited scene.",
		_object_schema({
			"path": {"type": "string"},
			"x": {"type": "integer"},
			"y": {"type": "integer"},
			"source_id": {"type": "integer"},
			"atlas_x": {"type": "integer"},
			"atlas_y": {"type": "integer"},
		}, ["atlas_x", "atlas_y"], ["path", "x", "y", "source_id"]),
		false, set_tile_cell
	))
	registry.register_tool(LumenToolSpec.new(
		"get_tile_state", "Read used cells from a TileMapLayer.",
		_object_schema({"path": {"type": "string"}}, [], ["path"]), true, get_tile_state
	))
	registry.register_tool(LumenToolSpec.new(
		"generate_image", "Generate an image via an OpenAI-compatible image endpoint if configured. Saves under res://assets/lumen/.",
		_object_schema({
			"prompt": {"type": "string"},
			"filename": {"type": "string"},
			"size": {"type": "string", "description": "e.g. 512x512"},
		}, ["filename", "size"], ["prompt"]),
		false, generate_image
	))
	registry.register_tool(LumenToolSpec.new(
		"load_skill", "Load the full SKILL.md for a named skill.",
		_object_schema({"name": {"type": "string"}}, [], ["name"]), true, load_skill
	))
	registry.register_tool(LumenToolSpec.new(
		"search_godot_docs_hint", "Return the official docs URL for a class or topic. Does not scrape pages.",
		_object_schema({"topic": {"type": "string"}}, [], ["topic"]), true, search_godot_docs_hint
	))
	registry.register_tool(LumenToolSpec.new(
		"fill_tiles", "Fill a rectangle of cells on a TileMapLayer.",
		_object_schema({
			"path": {"type": "string"},
			"x": {"type": "integer"},
			"y": {"type": "integer"},
			"w": {"type": "integer"},
			"h": {"type": "integer"},
			"source_id": {"type": "integer"},
			"atlas_x": {"type": "integer"},
			"atlas_y": {"type": "integer"},
		}, ["atlas_x", "atlas_y"], ["path", "x", "y", "w", "h", "source_id"]),
		false, fill_tiles
	))
	registry.register_tool(LumenToolSpec.new(
		"erase_tiles", "Erase a rectangle of cells on a TileMapLayer.",
		_object_schema({
			"path": {"type": "string"},
			"x": {"type": "integer"},
			"y": {"type": "integer"},
			"w": {"type": "integer"},
			"h": {"type": "integer"},
		}, [], ["path", "x", "y", "w", "h"]),
		false, erase_tiles
	))
	registry.register_tool(LumenToolSpec.new(
		"attach_script", "Attach a script resource to a node in the edited scene.",
		_object_schema({
			"path": {"type": "string"},
			"script": {"type": "string", "description": "res:// path to .gd/.cs"},
		}, [], ["path", "script"]),
		false, attach_script
	))
	registry.register_tool(LumenToolSpec.new(
		"open_scene", "Open a scene in the editor.",
		_object_schema({"path": {"type": "string"}}, [], ["path"]), false, open_scene
	))
	registry.register_tool(LumenToolSpec.new(
		"save_scene", "Save the currently edited scene.",
		_object_schema({"path": {"type": "string", "description": "Optional save-as path"}}, ["path"]),
		false, save_scene
	))


func _object_schema(properties: Dictionary, optional: Array = [], required_override: Array = []) -> Dictionary:
	var required: Array = required_override
	if required.is_empty():
		for key in properties.keys():
			if key not in optional:
				required.append(key)
	return {"type": "object", "properties": properties, "required": required}


func _safe_res(path: String) -> String:
	var res := LumenPaths.to_res(path.strip_edges())
	if not res.begins_with("res://"):
		res = "res://" + res.lstrip("/")
	if res.begins_with("res://addons/lumen/"):
		return ""
	if ".." in res.split("/"):
		return ""
	if not LumenPaths.is_inside_project(res):
		return ""
	return res


func get_project_info(_args: Dictionary) -> Dictionary:
	var ei := EditorInterface
	var root := ei.get_edited_scene_root()
	return {
		"ok": true,
		"name": ProjectSettings.get_setting("application/config/name", ""),
		"godot": Engine.get_version_info(),
		"edited_scene": root.scene_file_path if root else "",
		"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
		"features": ProjectSettings.get_setting("application/config/features", PackedStringArray()),
	}


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
	return {"ok": true, "tree": _walk(start, 0, 400)}


func _walk(node: Node, depth: int, budget: int) -> Dictionary:
	var kids: Array = []
	var used := 1
	if depth < 12:
		for child in node.get_children():
			if used >= budget:
				kids.append({"truncated": true})
				break
			var branch := _walk(child, depth + 1, budget - used)
			used += int(branch.get("_used", 1))
			kids.append(branch)
	var out := {
		"name": node.name,
		"type": node.get_class(),
		"path": str(node.get_path()),
		"children": kids,
	}
	if node is CanvasItem:
		out["visible"] = (node as CanvasItem).visible
	out["_used"] = used
	return out


func read_file(args: Dictionary) -> Dictionary:
	var path := _safe_res(str(args.get("path", "")))
	if path == "":
		return {"ok": false, "error": "Path rejected."}
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Missing file: %s" % path}
	var text := LumenJson.read_text(path)
	return {"ok": true, "path": path, "content": LumenJson.clamp_text(text, 40_000)}


func list_dir(args: Dictionary) -> Dictionary:
	var path := _safe_res(str(args.get("path", "res://")))
	if path == "":
		return {"ok": false, "error": "Path rejected."}
	var dir := DirAccess.open(path)
	if dir == null:
		return {"ok": false, "error": "Cannot open %s" % path}
	var files: Array = []
	var dirs: Array = []
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if not name.begins_with("."):
			if dir.current_is_dir():
				dirs.append(name)
			else:
				files.append(name)
		name = dir.get_next()
	dir.list_dir_end()
	return {"ok": true, "path": path, "dirs": dirs, "files": files}


func search_project(args: Dictionary) -> Dictionary:
	var query := str(args.get("query", "")).to_lower()
	if query == "":
		return {"ok": false, "error": "Empty query."}
	var glob := str(args.get("glob", ""))
	var hits: Array = []
	_search("res://", query, glob, hits, 80)
	return {"ok": true, "hits": hits}


func _search(dir_path: String, query: String, glob: String, hits: Array, limit: int) -> void:
	if hits.size() >= limit:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "" and hits.size() < limit:
		if name.begins_with(".") or name == "addons":
			name = dir.get_next()
			continue
		var child := dir_path.path_join(name)
		if dir.current_is_dir():
			_search(child, query, glob, hits, limit)
		else:
			if glob != "" and not name.ends_with(glob):
				name = dir.get_next()
				continue
			if name.ends_with(".gd") or name.ends_with(".cs") or name.ends_with(".tscn") or name.ends_with(".md") or name.ends_with(".txt") or name.ends_with(".json"):
				var text := LumenJson.read_text(child)
				var idx := text.to_lower().find(query)
				if idx >= 0:
					var start := max(idx - 40, 0)
					hits.append({"path": child, "excerpt": text.substr(start, 120)})
		name = dir.get_next()
	dir.list_dir_end()


func get_errors(_args: Dictionary) -> Dictionary:
	var open_scripts: Array = []
	var se := EditorInterface.get_script_editor()
	if se:
		for script in se.get_open_scripts():
			if script:
				open_scripts.append(script.resource_path)
	var log_hits: Array = []
	var log_paths := PackedStringArray([
		OS.get_user_data_dir().path_join("logs/godot.log"),
		ProjectSettings.globalize_path("user://logs/godot.log"),
	])
	for log_path in log_paths:
		if not FileAccess.file_exists(log_path):
			continue
		var text := FileAccess.get_file_as_string(log_path)
		var lines := text.split("\n")
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
	}


func write_file(args: Dictionary) -> Dictionary:
	var path := _safe_res(str(args.get("path", "")))
	if path == "":
		return {"ok": false, "error": "Path rejected."}
	var err := LumenJson.write_text(path, str(args.get("content", "")))
	if err != OK:
		return {"ok": false, "error": error_string(err)}
	_scan()
	return {"ok": true, "path": path}


func edit_file(args: Dictionary) -> Dictionary:
	var path := _safe_res(str(args.get("path", "")))
	if path == "":
		return {"ok": false, "error": "Path rejected."}
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Missing file."}
	var text := LumenJson.read_text(path)
	var old := str(args.get("old_string", ""))
	var new := str(args.get("new_string", ""))
	if old == "":
		return {"ok": false, "error": "old_string is empty."}
	if bool(args.get("replace_all", false)):
		if text.find(old) < 0:
			return {"ok": false, "error": "old_string not found."}
		text = text.replace(old, new)
	else:
		var idx := text.find(old)
		if idx < 0:
			return {"ok": false, "error": "old_string not found."}
		if text.find(old, idx + old.length()) >= 0:
			return {"ok": false, "error": "old_string is not unique. Pass replace_all or a larger snippet."}
		text = text.substr(0, idx) + new + text.substr(idx + old.length())
	LumenJson.write_text(path, text)
	_scan()
	return {"ok": true, "path": path}


func delete_file(args: Dictionary) -> Dictionary:
	var path := _safe_res(str(args.get("path", "")))
	if path == "":
		return {"ok": false, "error": "Path rejected."}
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Missing file."}
	var err := DirAccess.remove_absolute(LumenPaths.to_abs(path))
	_scan()
	return {"ok": err == OK, "path": path, "error": error_string(err) if err != OK else ""}


func move_path(args: Dictionary) -> Dictionary:
	var from := _safe_res(str(args.get("from", "")))
	var to := _safe_res(str(args.get("to", "")))
	if from == "" or to == "":
		return {"ok": false, "error": "Path rejected."}
	var err := DirAccess.rename_absolute(LumenPaths.to_abs(from), LumenPaths.to_abs(to))
	_scan()
	return {"ok": err == OK, "from": from, "to": to, "error": error_string(err) if err != OK else ""}


func create_node(args: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "No edited scene."}
	var parent_path := str(args.get("parent", ""))
	var parent := root if parent_path == "" else root.get_node_or_null(NodePath(parent_path))
	if parent == null:
		return {"ok": false, "error": "Parent not found."}
	var type_name := str(args.get("type", "Node"))
	if not ClassDB.class_exists(type_name) or not ClassDB.can_instantiate(type_name):
		return {"ok": false, "error": "Cannot instantiate %s" % type_name}
	var node := ClassDB.instantiate(type_name) as Node
	if node == null:
		return {"ok": false, "error": "Instantiate failed."}
	node.name = str(args.get("name", type_name))
	parent.add_child(node)
	node.owner = root
	_mark_scene_dirty()
	return {"ok": true, "path": str(node.get_path())}


func set_node_property(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found."}
	var property := str(args.get("property", ""))
	if property == "":
		return {"ok": false, "error": "Empty property."}
	node.set(property, args.get("value", null))
	_mark_scene_dirty()
	return {"ok": true, "path": str(node.get_path()), "property": property}


func delete_node(args: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	var node := _find(str(args.get("path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found."}
	if node == root:
		return {"ok": false, "error": "Refusing to delete the scene root."}
	node.free()
	_mark_scene_dirty()
	return {"ok": true}


func reparent_node(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	var parent := _find(str(args.get("new_parent", "")))
	if node == null or parent == null:
		return {"ok": false, "error": "Node or parent not found."}
	node.reparent(parent)
	node.owner = EditorInterface.get_edited_scene_root()
	_mark_scene_dirty()
	return {"ok": true}


func get_project_setting(args: Dictionary) -> Dictionary:
	var key := str(args.get("key", ""))
	if not ProjectSettings.has_setting(key):
		return {"ok": false, "error": "Unknown setting."}
	return {"ok": true, "key": key, "value": ProjectSettings.get_setting(key)}


func set_project_setting(args: Dictionary) -> Dictionary:
	var key := str(args.get("key", ""))
	if key.begins_with("application/config/features"):
		return {"ok": false, "error": "Refusing to rewrite engine features."}
	ProjectSettings.set_setting(key, args.get("value", null))
	ProjectSettings.save()
	return {"ok": true, "key": key}


func run_scene(args: Dictionary) -> Dictionary:
	var ei := EditorInterface
	var path := str(args.get("path", ""))
	if path == "":
		ei.play_current_scene()
		return {"ok": true, "mode": "current"}
	path = _safe_res(path)
	if path == "":
		return {"ok": false, "error": "Path rejected."}
	ei.play_custom_scene(path)
	return {"ok": true, "scene": path}


func stop_scene(_args: Dictionary) -> Dictionary:
	EditorInterface.stop_playing_scene()
	return {"ok": true}


func playtest_batch(args: Dictionary) -> Dictionary:
	var sidecar := {
		"inputs": args.get("inputs", []),
		"duration_ms": int(args.get("duration_ms", 2000)),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot"))
	LumenJson.write_file(LumenPaths.HARNESS_SIDECAR, sidecar)
	return run_scene({"path": str(args.get("scene", ""))})


func capture_screenshot(args: Dictionary) -> Dictionary:
	var ei := EditorInterface
	var vp := ei.get_editor_viewport_2d()
	if vp == null:
		return {"ok": false, "error": "No 2D viewport."}
	var img := vp.get_texture().get_image()
	if img == null:
		return {"ok": false, "error": "Viewport has no image."}
	var name := str(args.get("name", "capture-%d.png" % Time.get_unix_time_from_system()))
	if not name.ends_with(".png"):
		name += ".png"
	var path := "res://.lumen/captures/" + name.get_file()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.lumen/captures"))
	var err := img.save_png(path)
	_scan()
	return {"ok": err == OK, "path": path}


func run_tests(args: Dictionary) -> Dictionary:
	var scene := str(args.get("scene", settings.get_value("test_scene", "")))
	if scene != "":
		return run_scene({"path": scene})
	for candidate in [
		"res://tests/test.tscn",
		"res://test/test.tscn",
		"res://addons/gut/gui/GutRunner.tscn",
		"res://gut_tests.tscn",
	]:
		if FileAccess.file_exists(candidate):
			return run_scene({"path": candidate})
	var tests: Array = []
	_search("res://", "test", ".gd", tests, 40)
	if tests.is_empty():
		_search("res://", "test", ".tscn", tests, 40)
	return {"ok": true, "hint": "No dedicated runner found. Pass scene to play it.", "candidates": tests}


func set_tile_cell(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null or not (node is TileMapLayer):
		return {"ok": false, "error": "TileMapLayer not found."}
	var layer := node as TileMapLayer
	var atlas := Vector2i(int(args.get("atlas_x", 0)), int(args.get("atlas_y", 0)))
	layer.set_cell(
		Vector2i(int(args.get("x", 0)), int(args.get("y", 0))),
		int(args.get("source_id", 0)),
		atlas
	)
	_mark_scene_dirty()
	return {"ok": true}


func get_tile_state(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null or not (node is TileMapLayer):
		return {"ok": false, "error": "TileMapLayer not found."}
	var layer := node as TileMapLayer
	var used := layer.get_used_cells()
	var cells: Array = []
	var i := 0
	for cell in used:
		if i >= 400:
			break
		cells.append({"x": cell.x, "y": cell.y})
		i += 1
	return {"ok": true, "count": used.size(), "cells": cells}


func generate_image(args: Dictionary) -> Dictionary:
	var prompt := str(args.get("prompt", "")).strip_edges()
	if prompt == "":
		return {"ok": false, "error": "Empty prompt."}
	var filename := str(args.get("filename", "lumen-%d.png" % Time.get_unix_time_from_system())).get_file()
	if not filename.ends_with(".png"):
		filename += ".png"
	var dest := "res://assets/lumen/" + filename
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/lumen"))
	var url := str(settings.get_value("image_base_url", "")).strip_edges()
	if url != "":
		var remote := _generate_image_remote(url, prompt, str(args.get("size", "512x512")), dest)
		if bool(remote.get("ok", false)):
			_scan()
			return remote
		var placeholder := _write_placeholder_png(dest, prompt)
		placeholder["warning"] = str(remote.get("error", "Remote image failed."))
		_scan()
		return placeholder
	var local := _write_placeholder_png(dest, prompt)
	local["note"] = "No image_base_url set. Wrote a local placeholder PNG so the path exists. Set image_base_url for a real model."
	_scan()
	return local


func load_skill(args: Dictionary) -> Dictionary:
	var text := skills.load_skill(str(args.get("name", "")))
	if text == "":
		return {"ok": false, "error": "Skill not found."}
	return {"ok": true, "content": text}


func search_godot_docs_hint(args: Dictionary) -> Dictionary:
	var topic := str(args.get("topic", "")).strip_edges()
	var slug := topic.to_lower().replace(" ", "_")
	return {
		"ok": true,
		"class_url": "https://docs.godotengine.org/en/stable/classes/class_%s.html" % slug,
		"search_url": "https://docs.godotengine.org/en/stable/search.html?q=%s" % topic.uri_encode(),
	}


func _find(path: String) -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == "." or path == str(root.name):
		return root
	return root.get_node_or_null(NodePath(path))


func _scan() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		fs.scan()


func _mark_scene_dirty() -> void:
	EditorInterface.mark_scene_as_unsaved()


func fill_tiles(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null or not (node is TileMapLayer):
		return {"ok": false, "error": "TileMapLayer not found."}
	var layer := node as TileMapLayer
	var origin := Vector2i(int(args.get("x", 0)), int(args.get("y", 0)))
	var size := Vector2i(clampi(int(args.get("w", 1)), 1, 256), clampi(int(args.get("h", 1)), 1, 256))
	var atlas := Vector2i(int(args.get("atlas_x", 0)), int(args.get("atlas_y", 0)))
	var source := int(args.get("source_id", 0))
	var count := 0
	for y in size.y:
		for x in size.x:
			layer.set_cell(origin + Vector2i(x, y), source, atlas)
			count += 1
	_mark_scene_dirty()
	return {"ok": true, "cells": count}


func erase_tiles(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null or not (node is TileMapLayer):
		return {"ok": false, "error": "TileMapLayer not found."}
	var layer := node as TileMapLayer
	var origin := Vector2i(int(args.get("x", 0)), int(args.get("y", 0)))
	var size := Vector2i(clampi(int(args.get("w", 1)), 1, 256), clampi(int(args.get("h", 1)), 1, 256))
	var count := 0
	for y in size.y:
		for x in size.x:
			layer.erase_cell(origin + Vector2i(x, y))
			count += 1
	_mark_scene_dirty()
	return {"ok": true, "erased": count}


func attach_script(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found."}
	var script_path := _safe_res(str(args.get("script", "")))
	if script_path == "" or not FileAccess.file_exists(script_path):
		return {"ok": false, "error": "Script not found."}
	var script := load(script_path)
	if script == null:
		return {"ok": false, "error": "Could not load script."}
	node.set_script(script)
	_mark_scene_dirty()
	return {"ok": true, "path": str(node.get_path()), "script": script_path}


func open_scene(args: Dictionary) -> Dictionary:
	var path := _safe_res(str(args.get("path", "")))
	if path == "" or not FileAccess.file_exists(path):
		return {"ok": false, "error": "Scene not found."}
	EditorInterface.open_scene_from_path(path)
	return {"ok": true, "path": path}


func save_scene(args: Dictionary) -> Dictionary:
	var as_path := str(args.get("path", "")).strip_edges()
	if as_path != "":
		as_path = _safe_res(as_path)
		if as_path == "":
			return {"ok": false, "error": "Path rejected."}
		EditorInterface.save_scene_as(as_path)
		return {"ok": true, "path": as_path}
	var err := EditorInterface.save_scene()
	return {"ok": err == OK, "error": error_string(err) if err != OK else ""}


func _write_placeholder_png(dest: String, prompt: String) -> Dictionary:
	var img := Image.create(512, 512, false, Image.FORMAT_RGBA8)
	var hue := float(abs(prompt.hash()) % 360) / 360.0
	img.fill(Color.from_hsv(hue, 0.35, 0.2))
	var err := img.save_png(dest)
	return {
		"ok": err == OK,
		"path": dest,
		"placeholder": true,
		"prompt": prompt,
		"error": error_string(err) if err != OK else "",
	}


func _generate_image_remote(base_url: String, prompt: String, size: String, dest: String) -> Dictionary:
	var endpoint := base_url.rstrip("/")
	if not endpoint.ends_with("/images/generations"):
		endpoint += "/images/generations"
	var parsed := endpoint
	var tls := parsed.begins_with("https://")
	parsed = parsed.trim_prefix("https://").trim_prefix("http://")
	var host := parsed.split("/")[0]
	var path := "/" + parsed.substr(host.length()).lstrip("/")
	var port := 443 if tls else 80
	if ":" in host:
		var hp := host.split(":")
		host = hp[0]
		port = int(hp[1])
	var payload := JSON.stringify({
		"model": str(settings.get_value("image_model", "gpt-image-1")),
		"prompt": prompt,
		"size": size if size != "" else "512x512",
		"response_format": "b64_json",
		"n": 1,
	})
	var headers := PackedStringArray(["Content-Type: application/json"])
	var key := settings.image_api_key()
	if key != "":
		headers.append("Authorization: Bearer %s" % key)
	var http := HTTPClient.new()
	var err := http.connect_to_host(host, port, TLSOptions.client() if tls else null)
	if err != OK:
		return {"ok": false, "error": "Connect failed: %s" % error_string(err)}
	var waited := 0
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		OS.delay_msec(30)
		waited += 30
		if waited > 15000:
			return {"ok": false, "error": "Connect timeout."}
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"ok": false, "error": "Not connected (%d)." % http.get_status()}
	err = http.request(HTTPClient.METHOD_POST, path, headers, payload)
	if err != OK:
		return {"ok": false, "error": "Request failed: %s" % error_string(err)}
	waited = 0
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		OS.delay_msec(30)
		waited += 30
		if waited > 60000:
			return {"ok": false, "error": "Request timeout."}
	var body := PackedByteArray()
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() > 0:
			body.append_array(chunk)
		else:
			OS.delay_msec(20)
	var text := body.get_string_from_utf8()
	var parsed_json: Variant = JSON.parse_string(text)
	if typeof(parsed_json) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Non-JSON image response.", "body": LumenJson.clamp_text(text, 400)}
	var data: Array = parsed_json.get("data", [])
	if data.is_empty():
		return {"ok": false, "error": LumenJson.clamp_text(text, 400)}
	var b64 := str(data[0].get("b64_json", ""))
	if b64 == "":
		return {"ok": false, "error": "No b64_json in image response."}
	var bytes := Marshalls.base64_to_raw(b64)
	var out := FileAccess.open(dest, FileAccess.WRITE)
	if out == null:
		return {"ok": false, "error": "Cannot write %s" % dest}
	out.store_buffer(bytes)
	return {"ok": true, "path": dest, "placeholder": false, "prompt": prompt}

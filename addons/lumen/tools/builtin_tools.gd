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
		"capture_screenshot", "Capture the editor 2D viewport to a PNG under res://.lumen/captures/.",
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
		"generate_image", "Generate an image via an OpenAI-compatible image endpoint if configured.",
		_object_schema({
			"prompt": {"type": "string"},
			"filename": {"type": "string"},
			"size": {"type": "string"},
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
	var ei := plugin.get_editor_interface()
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
	var root := plugin.get_editor_interface().get_edited_scene_root()
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
	var script_errors: Array = []
	var ei := plugin.get_editor_interface()
	var se := ei.get_script_editor()
	if se:
		for script in se.get_open_scripts():
			if script:
				script_errors.append(script.resource_path)
	return {
		"ok": true,
		"note": "Godot does not expose the full debugger queue to plugins on every version. Open scripts listed; read the Output dock for live errors.",
		"open_scripts": script_errors,
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
	var root := plugin.get_editor_interface().get_edited_scene_root()
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
	var root := plugin.get_editor_interface().get_edited_scene_root()
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
	node.owner = plugin.get_editor_interface().get_edited_scene_root()
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
	var ei := plugin.get_editor_interface()
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
	plugin.get_editor_interface().stop_playing_scene()
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
	var ei := plugin.get_editor_interface()
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
	var tests: Array = []
	_search("res://", "test", ".gd", tests, 30)
	return {"ok": true, "hint": "Pass scene to run it. Candidates listed.", "candidates": tests}


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
	var url := str(settings.get_value("image_base_url", ""))
	if url == "":
		return {
			"ok": false,
			"error": "No image endpoint configured. Set image_base_url + image_model in settings, or generate assets outside Lumen.",
		}
	return {
		"ok": false,
		"error": "Image generation is configured asynchronously. Use a local image API from your own key. Prompt stored.",
		"prompt": str(args.get("prompt", "")),
		"filename": str(args.get("filename", "gen.png")),
		"endpoint": url,
	}


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
	var root := plugin.get_editor_interface().get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == "." or path == str(root.name):
		return root
	return root.get_node_or_null(NodePath(path))


func _scan() -> void:
	var fs := plugin.get_editor_interface().get_resource_filesystem()
	if fs:
		fs.scan()


func _mark_scene_dirty() -> void:
	var ei := plugin.get_editor_interface()
	if ei.has_method("mark_scene_as_unsaved"):
		ei.call("mark_scene_as_unsaved")

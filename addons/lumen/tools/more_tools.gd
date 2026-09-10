@tool
class_name LumenMoreTools
extends RefCounted

## Extra tools registered after builtins. Later names replace earlier ones.

var settings: LumenSettings


func attach(p_settings: LumenSettings) -> void:
	settings = p_settings


func register(registry: LumenToolRegistry) -> void:
	registry.register_tool(LumenToolSpec.new(
		"generate_image", "Write res://assets/lumen/*.png. Uses image_base_url when set.",
		_schema({
			"prompt": {"type": "string"},
			"filename": {"type": "string"},
			"size": {"type": "string"},
		}, ["filename", "size"], ["prompt"]),
		false, generate_image
	))


func _legacy_unused_register(registry: LumenToolRegistry) -> void:
	registry.register_tool(LumenToolSpec.new(
		"fill_tiles", "Fill a rectangle of cells on a TileMapLayer.",
		_schema({
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
		_schema({
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
		_schema({
			"path": {"type": "string"},
			"script": {"type": "string"},
		}, [], ["path", "script"]),
		false, attach_script
	))
	registry.register_tool(LumenToolSpec.new(
		"open_scene", "Open a scene in the editor.",
		_schema({"path": {"type": "string"}}, [], ["path"]), false, open_scene
	))
	registry.register_tool(LumenToolSpec.new(
		"save_scene", "Save the currently edited scene.",
		_schema({"path": {"type": "string"}}, ["path"]), false, save_scene
	))
	registry.register_tool(LumenToolSpec.new(
		"generate_image", "Write res://assets/lumen/*.png. Uses image_base_url when set.",
		_schema({
			"prompt": {"type": "string"},
			"filename": {"type": "string"},
			"size": {"type": "string"},
		}, ["filename", "size"], ["prompt"]),
		false, generate_image
	))
	registry.register_tool(LumenToolSpec.new(
		"get_errors", "Open scripts plus recent error/warning lines from godot.log.",
		_schema({}), true, get_errors
	))
	registry.register_tool(LumenToolSpec.new(
		"run_tests", "Play a test scene or list test scripts.",
		_schema({"scene": {"type": "string"}}, ["scene"]), false, run_tests
	))


func fill_tiles(args: Dictionary) -> Dictionary:
	var layer := _layer(str(args.get("path", "")))
	if layer == null:
		return {"ok": false, "error": "TileMapLayer not found."}
	var origin := Vector2i(int(args.get("x", 0)), int(args.get("y", 0)))
	var size := Vector2i(clampi(int(args.get("w", 1)), 1, 256), clampi(int(args.get("h", 1)), 1, 256))
	var atlas := Vector2i(int(args.get("atlas_x", 0)), int(args.get("atlas_y", 0)))
	var source := int(args.get("source_id", 0))
	var count := 0
	for y in size.y:
		for x in size.x:
			layer.set_cell(origin + Vector2i(x, y), source, atlas)
			count += 1
	EditorInterface.mark_scene_as_unsaved()
	return {"ok": true, "cells": count}


func erase_tiles(args: Dictionary) -> Dictionary:
	var layer := _layer(str(args.get("path", "")))
	if layer == null:
		return {"ok": false, "error": "TileMapLayer not found."}
	var origin := Vector2i(int(args.get("x", 0)), int(args.get("y", 0)))
	var size := Vector2i(clampi(int(args.get("w", 1)), 1, 256), clampi(int(args.get("h", 1)), 1, 256))
	var count := 0
	for y in size.y:
		for x in size.x:
			layer.erase_cell(origin + Vector2i(x, y))
			count += 1
	EditorInterface.mark_scene_as_unsaved()
	return {"ok": true, "erased": count}


func attach_script(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found."}
	var script_path := str(args.get("script", ""))
	if not FileAccess.file_exists(script_path):
		return {"ok": false, "error": "Script not found."}
	var script := load(script_path)
	if script == null:
		return {"ok": false, "error": "Could not load script."}
	node.set_script(script)
	EditorInterface.mark_scene_as_unsaved()
	return {"ok": true, "script": script_path}


func open_scene(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", ""))
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "Scene not found."}
	EditorInterface.open_scene_from_path(path)
	return {"ok": true, "path": path}


func save_scene(args: Dictionary) -> Dictionary:
	var as_path := str(args.get("path", "")).strip_edges()
	if as_path != "":
		EditorInterface.save_scene_as(as_path)
		return {"ok": true, "path": as_path}
	var err := EditorInterface.save_scene()
	return {"ok": err == OK, "error": error_string(err) if err != OK else ""}


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
			var lower := lines[i].to_lower()
			if "error" in lower or "warning" in lower or "parse error" in lower:
				log_hits.append(lines[i].strip_edges())
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


func run_tests(args: Dictionary) -> Dictionary:
	var scene := str(args.get("scene", settings.get_value("test_scene", "") if settings else ""))
	if scene != "":
		EditorInterface.play_custom_scene(scene)
		return {"ok": true, "scene": scene}
	for candidate in [
		"res://tests/test.tscn",
		"res://test/test.tscn",
		"res://addons/gut/gui/GutRunner.tscn",
		"res://addons/gdUnit4/src/ui/GdUnitInspector.tscn",
		str(settings.get_value("gut_runner", "")) if settings else "",
	]:
		if FileAccess.file_exists(candidate):
			EditorInterface.play_custom_scene(candidate)
			return {"ok": true, "scene": candidate}
	return {"ok": true, "hint": "Pass scene to play it."}


func generate_image(args: Dictionary) -> Dictionary:
	var prompt := str(args.get("prompt", "")).strip_edges()
	if prompt == "":
		return {"ok": false, "error": "Empty prompt."}
	var filename := str(args.get("filename", "lumen-%d.png" % Time.get_unix_time_from_system())).get_file()
	if not filename.ends_with(".png"):
		filename += ".png"
	var dest := "res://assets/lumen/" + filename
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/lumen"))
	if settings == null or str(settings.get_value("image_base_url", "")).strip_edges() == "":
		return {
			"ok": false,
			"error": "No image backend. Set image_base_url to an OpenAI-compatible /images/generations endpoint. No fake PNG.",
		}
	return _remote_png(str(settings.get_value("image_base_url", "")), prompt, str(args.get("size", "512x512")), dest)


func _remote_png(base_url: String, prompt: String, size: String, dest: String) -> Dictionary:
	var endpoint := base_url.rstrip("/")
	if not endpoint.ends_with("/images/generations"):
		endpoint += "/images/generations"
	var rest := endpoint.trim_prefix("https://").trim_prefix("http://")
	var tls := endpoint.begins_with("https://")
	var host := rest.split("/")[0]
	var path := "/" + rest.substr(host.length()).lstrip("/")
	var port := 443 if tls else 80
	if ":" in host:
		var hp := host.split(":")
		host = hp[0]
		port = int(hp[1])
	var headers := PackedStringArray(["Content-Type: application/json"])
	if settings and settings.image_api_key() != "":
		headers.append("Authorization: Bearer %s" % settings.image_api_key())
	var payload := JSON.stringify({
		"model": str(settings.get_value("image_model", "gpt-image-1")) if settings else "gpt-image-1",
		"prompt": prompt,
		"size": size,
		"response_format": "b64_json",
		"n": 1,
	})
	var http := HTTPClient.new()
	var err := http.connect_to_host(host, port, TLSOptions.client() if tls else null)
	if err != OK:
		return {"ok": false, "error": error_string(err)}
	var waited := 0
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		OS.delay_msec(30)
		waited += 30
		if waited > 15000:
			return {"ok": false, "error": "Connect timeout."}
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"ok": false, "error": "Not connected."}
	err = http.request(HTTPClient.METHOD_POST, path, headers, payload)
	if err != OK:
		return {"ok": false, "error": error_string(err)}
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
		if chunk.size():
			body.append_array(chunk)
		else:
			OS.delay_msec(20)
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Non-JSON image response."}
	var data: Array = parsed.get("data", [])
	if data.is_empty() or str(data[0].get("b64_json", "")) == "":
		return {"ok": false, "error": "No b64_json."}
	var out := FileAccess.open(dest, FileAccess.WRITE)
	if out == null:
		return {"ok": false, "error": "Cannot write %s" % dest}
	out.store_buffer(Marshalls.base64_to_raw(str(data[0].get("b64_json", ""))))
	return {"ok": true, "path": dest, "placeholder": false}


func _layer(path: String) -> TileMapLayer:
	var node := _find(path)
	return node as TileMapLayer if node is TileMapLayer else null


func _find(path: String) -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == "." or path == str(root.name):
		return root
	return root.get_node_or_null(NodePath(path))


func _schema(properties: Dictionary, optional: Array = [], required_override: Array = []) -> Dictionary:
	var required: Array = required_override
	if required.is_empty():
		for key in properties.keys():
			if key not in optional:
				required.append(key)
	return {"type": "object", "properties": properties, "required": required}

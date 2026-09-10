@tool
class_name LumenAssetGen
extends RefCounted

## Bring-your-own image / mesh APIs. Files land in res:// and Godot imports them.
## No Lumen wallet. Keys stay in user:// secrets.

var settings: LumenSettings


func attach(p_settings: LumenSettings) -> void:
	settings = p_settings


func register(registry: LumenToolRegistry) -> void:
	registry.register_tool(LumenToolSpec.new(
		"generate_sprite",
		"Generate a PNG via Retro Diffusion or an OpenAI-compatible image endpoint. Saves under res://assets/lumen/.",
		{
			"type": "object",
			"properties": {
				"prompt": {"type": "string"},
				"filename": {"type": "string"},
				"width": {"type": "integer"},
				"height": {"type": "integer"},
				"style": {"type": "string", "description": "Retro Diffusion prompt_style, default rd_plus__default"},
			},
			"required": ["prompt"],
		},
		false,
		generate_sprite
	))
	registry.register_tool(LumenToolSpec.new(
		"generate_3d_model",
		"Text-to-3D via Meshy (or custom mesh_base_url). Downloads a GLB into res://assets/lumen/3d/ and can instance it.",
		{
			"type": "object",
			"properties": {
				"prompt": {"type": "string"},
				"filename": {"type": "string"},
				"refine": {"type": "boolean", "description": "Meshy refine/texture pass. Costs more, looks better."},
				"instance": {"type": "boolean", "description": "Add MeshInstance into the edited scene."},
				"parent": {"type": "string"},
			},
			"required": ["prompt"],
		},
		false,
		generate_3d_model
	))
	registry.register_tool(LumenToolSpec.new(
		"generate_3d_from_image",
		"Image-to-3D via Meshy. image is a res:// PNG/JPG already in the project.",
		{
			"type": "object",
			"properties": {
				"image": {"type": "string"},
				"filename": {"type": "string"},
				"instance": {"type": "boolean"},
				"parent": {"type": "string"},
			},
			"required": ["image"],
		},
		false,
		generate_3d_from_image
	))
	registry.register_tool(LumenToolSpec.new(
		"poll_3d_task",
		"Resume a Meshy task id if generate_3d_model returned pending.",
		{
			"type": "object",
			"properties": {
				"task_id": {"type": "string"},
				"filename": {"type": "string"},
				"instance": {"type": "boolean"},
				"parent": {"type": "string"},
			},
			"required": ["task_id"],
		},
		false,
		poll_3d_task
	))


func generate_sprite(args: Dictionary) -> Dictionary:
	var prompt := str(args.get("prompt", "")).strip_edges()
	if prompt == "":
		return {"ok": false, "error": "Empty prompt."}
	var filename := str(args.get("filename", "sprite-%d.png" % Time.get_unix_time_from_system())).get_file()
	if not filename.ends_with(".png"):
		filename += ".png"
	var dest := "res://assets/lumen/" + filename
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/lumen"))
	var kind := _image_kind()
	var result: Dictionary
	if kind == "retro":
		result = _retro_image(prompt, dest, int(args.get("width", 256)), int(args.get("height", 256)), str(args.get("style", "rd_plus__default")))
	else:
		result = _openai_image(prompt, dest, int(args.get("width", 512)), int(args.get("height", 512)))
	if bool(result.get("ok", false)):
		_scan()
	return result


func generate_3d_model(args: Dictionary) -> Dictionary:
	var prompt := str(args.get("prompt", "")).strip_edges()
	if prompt == "":
		return {"ok": false, "error": "Empty prompt."}
	var key := _mesh_key()
	if key == "":
		return {"ok": false, "error": "Set Mesh key in the dock (Meshy API key). No Lumen wallet."}
	var headers := _mesh_headers(key)
	var created := LumenHttp.request_json("POST", _mesh_base() + "/openapi/v2/text-to-3d", headers, JSON.stringify({
		"mode": "preview",
		"prompt": prompt,
		"should_remesh": true,
		"target_formats": ["glb"],
		"ai_model": "meshy-7",
	}), 30000)
	if not bool(created.get("ok", false)):
		return created
	var task_id := _task_id(created.get("json"))
	if task_id == "":
		return {"ok": false, "error": "Meshy did not return a task id.", "body": created.get("text", "")}
	var preview := _poll_meshy(task_id, headers)
	if not bool(preview.get("ok", false)):
		preview["task_id"] = task_id
		return preview
	if bool(args.get("refine", settings.get_value("mesh_refine", false))):
		var refine := LumenHttp.request_json("POST", _mesh_base() + "/openapi/v2/text-to-3d", headers, JSON.stringify({
			"mode": "refine",
			"preview_task_id": task_id,
			"target_formats": ["glb"],
		}), 30000)
		var refine_id := _task_id(refine.get("json"))
		if refine_id != "":
			var refined := _poll_meshy(refine_id, headers)
			if bool(refined.get("ok", false)):
				preview = refined
				task_id = refine_id
	return _save_glb(preview, args, task_id)


func generate_3d_from_image(args: Dictionary) -> Dictionary:
	var image := str(args.get("image", "")).strip_edges()
	if image == "" or not FileAccess.file_exists(image):
		return {"ok": false, "error": "Image not found in project."}
	var key := _mesh_key()
	if key == "":
		return {"ok": false, "error": "Set Mesh key in the dock."}
	var bytes := FileAccess.get_file_as_bytes(image)
	var data_url := "data:image/png;base64," + Marshalls.raw_to_base64(bytes)
	var headers := _mesh_headers(key)
	var created := LumenHttp.request_json("POST", _mesh_base() + "/openapi/v1/image-to-3d", headers, JSON.stringify({
		"image_url": data_url,
		"target_formats": ["glb"],
	}), 30000)
	if not bool(created.get("ok", false)):
		return created
	var task_id := _task_id(created.get("json"))
	if task_id == "":
		return {"ok": false, "error": "No task id.", "body": created.get("text", "")}
	var done := _poll_meshy(task_id, headers, "/openapi/v1/image-to-3d/")
	if not bool(done.get("ok", false)):
		done["task_id"] = task_id
		return done
	return _save_glb(done, args, task_id)


func poll_3d_task(args: Dictionary) -> Dictionary:
	var task_id := str(args.get("task_id", "")).strip_edges()
	if task_id == "":
		return {"ok": false, "error": "Empty task_id."}
	var done := _poll_meshy(task_id, _mesh_headers(_mesh_key()))
	if not bool(done.get("ok", false)):
		return done
	return _save_glb(done, args, task_id)


func _save_glb(task: Dictionary, args: Dictionary, task_id: String) -> Dictionary:
	var glb_url := str(task.get("glb", ""))
	if glb_url == "":
		return {"ok": false, "error": "Task finished without a GLB URL.", "task_id": task_id}
	var filename := str(args.get("filename", "mesh-%d.glb" % Time.get_unix_time_from_system())).get_file()
	if not filename.ends_with(".glb"):
		filename += ".glb"
	var dest := "res://assets/lumen/3d/" + filename
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/lumen/3d"))
	var raw := LumenHttp.request_bytes("GET", glb_url, PackedStringArray(), PackedByteArray(), 120000)
	if not bool(raw.get("ok", false)):
		return raw
	var file := FileAccess.open(dest, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Cannot write %s" % dest}
	file.store_buffer(raw.get("bytes"))
	_scan()
	var instanced := false
	if bool(args.get("instance", true)):
		instanced = _instance(dest, str(args.get("parent", "")))
	return {
		"ok": true,
		"path": dest,
		"task_id": task_id,
		"instanced": instanced,
		"note": "Godot imports the GLB. If the scene node is empty, wait for import and instance_3d.",
	}


func _instance(path: String, parent_path: String) -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return false
	var packed := load(path)
	if packed == null:
		return false
	var parent := root
	if parent_path != "":
		var found := root.get_node_or_null(NodePath(parent_path))
		if found:
			parent = found
	var node: Node
	if packed is PackedScene:
		node = (packed as PackedScene).instantiate()
	elif packed is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = packed
		node = mi
	else:
		return false
	node.name = path.get_file().get_basename()
	parent.add_child(node)
	node.owner = root
	return true


func _poll_meshy(task_id: String, headers: PackedStringArray, prefix: String = "/openapi/v2/text-to-3d/") -> Dictionary:
	var url := _mesh_base() + prefix + task_id
	var tries := 0
	while tries < 24:
		var row := LumenHttp.request_json("GET", url, headers, "", 20000)
		if not bool(row.get("ok", false)):
			return row
		var data: Variant = row.get("json")
		var status := ""
		var glb := ""
		if typeof(data) == TYPE_DICTIONARY:
			status = str(data.get("status", "")).to_upper()
			var urls: Variant = data.get("model_urls", {})
			if typeof(urls) == TYPE_DICTIONARY:
				glb = str(urls.get("glb", ""))
		if status == "SUCCEEDED" and glb != "":
			return {"ok": true, "glb": glb, "status": status}
		if status == "FAILED" or status == "CANCELED":
			return {"ok": false, "error": "Meshy task %s" % status, "body": row.get("text", "")}
		OS.delay_msec(2500)
		tries += 1
	return {"ok": false, "error": "Still generating. Call poll_3d_task with this id.", "task_id": task_id, "pending": true}


func _retro_image(prompt: String, dest: String, width: int, height: int, style: String) -> Dictionary:
	var key := _image_key()
	if key == "":
		return {"ok": false, "error": "Set Image key (Retro Diffusion X-RD-Token)."}
	var url := _image_base()
	if url == "" or url.find("retrodiffusion") < 0:
		url = "https://api.retrodiffusion.ai/v2/inferences"
	var row := LumenHttp.request_json("POST", url, PackedStringArray([
		"Content-Type: application/json",
		"X-RD-Token: %s" % key,
	]), JSON.stringify({
		"prompt": prompt,
		"prompt_style": style if style != "" else "rd_plus__default",
		"width": clampi(width, 16, 512),
		"height": clampi(height, 16, 512),
		"num_images": 1,
		"remove_bg": true,
	}), 90000)
	if not bool(row.get("ok", false)):
		return row
	var b64 := _first_b64(row.get("json"))
	if b64 == "":
		return {"ok": false, "error": "Retro Diffusion returned no image.", "body": row.get("text", "")}
	return _write_b64(dest, b64, prompt)


func _openai_image(prompt: String, dest: String, width: int, height: int) -> Dictionary:
	var base := _image_base()
	if base == "":
		return {"ok": false, "error": "Set Image URL to an OpenAI-compatible /images/generations endpoint, or switch to Retro Diffusion."}
	if not base.ends_with("/images/generations"):
		base = base.rstrip("/") + "/images/generations"
	var key := _image_key()
	var headers := PackedStringArray(["Content-Type: application/json"])
	if key != "":
		headers.append("Authorization: Bearer %s" % key)
	var size := "%dx%d" % [width, height]
	var row := LumenHttp.request_json("POST", base, headers, JSON.stringify({
		"model": str(settings.get_value("image_model", "gpt-image-1")),
		"prompt": prompt,
		"size": size,
		"response_format": "b64_json",
		"n": 1,
	}), 90000)
	if not bool(row.get("ok", false)):
		return row
	var b64 := _first_b64(row.get("json"))
	if b64 == "":
		return {"ok": false, "error": "No b64_json in image response.", "body": row.get("text", "")}
	return _write_b64(dest, b64, prompt)


func _write_b64(dest: String, b64: String, prompt: String) -> Dictionary:
	var clean := b64
	if "base64," in clean:
		clean = clean.substr(clean.find("base64,") + 7)
	var bytes := Marshalls.base64_to_raw(clean)
	var file := FileAccess.open(dest, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "Cannot write %s" % dest}
	file.store_buffer(bytes)
	return {"ok": true, "path": dest, "prompt": prompt}


func _first_b64(parsed: Variant) -> String:
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var data: Dictionary = parsed
	for key in ["base64_images", "images", "output_images"]:
		var arr: Variant = data.get(key, [])
		if typeof(arr) == TYPE_ARRAY and arr.size() > 0:
			var first: Variant = arr[0]
			if typeof(first) == TYPE_STRING:
				return str(first)
			if typeof(first) == TYPE_DICTIONARY:
				return str(first.get("b64_json", first.get("base64", "")))
	var inner: Variant = data.get("data", [])
	if typeof(inner) == TYPE_ARRAY and inner.size() > 0 and typeof(inner[0]) == TYPE_DICTIONARY:
		return str(inner[0].get("b64_json", ""))
	return str(data.get("b64_json", ""))


func _task_id(parsed: Variant) -> String:
	if typeof(parsed) == TYPE_STRING:
		return str(parsed)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var data: Dictionary = parsed
	var id := str(data.get("result", data.get("id", "")))
	return id


func _image_kind() -> String:
	var kind := str(settings.get_value("image_kind", "")).to_lower()
	if kind != "":
		return kind
	var url := _image_base()
	if url.find("retrodiffusion") >= 0:
		return "retro"
	if url == "":
		return "retro"
	return "openai"


func _image_base() -> String:
	return str(settings.get_value("image_base_url", "")).strip_edges()


func _mesh_base() -> String:
	var url := str(settings.get_value("mesh_base_url", "")).strip_edges()
	if url == "":
		return "https://api.meshy.ai"
	return url.rstrip("/")


func _image_key() -> String:
	if settings == null:
		return ""
	var key := str(settings.secrets.get("image_api_key", ""))
	return key if key != "" else settings.api_key()


func _mesh_key() -> String:
	if settings == null:
		return ""
	return str(settings.secrets.get("mesh_api_key", ""))


func _mesh_headers(key: String) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % key,
	])


func _scan() -> void:
	EditorInterface.get_resource_filesystem().scan()

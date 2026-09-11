@tool
class_name LumenDepthTools
extends RefCounted

## Closes the remaining editor-agent gaps that are not product extras
## (no hosted seat, no Retrodiffusion, no analytics dashboard).


func register(registry: LumenToolRegistry) -> void:
	registry.register_tool(LumenToolSpec.new(
		"search_engine_api",
		"Search live ClassDB: class names, parent, methods. Use instead of guessing Godot APIs.",
		_schema({"query": {"type": "string"}, "limit": {"type": "integer"}}, ["limit"], ["query"]),
		true,
		search_engine_api
	))
	registry.register_tool(LumenToolSpec.new(
		"list_class_methods",
		"List methods and properties on a Godot class from ClassDB.",
		_schema({"class_name": {"type": "string"}}, [], ["class_name"]),
		true,
		list_class_methods
	))
	registry.register_tool(LumenToolSpec.new(
		"set_animation_tree_param",
		"Set an AnimationTree parameter, e.g. parameters/Idle/blend_position.",
		_schema({
			"path": {"type": "string"},
			"param": {"type": "string"},
			"value": {"type": "string", "description": "float, bool, or Vector2 as x,y"},
		}, [], ["path", "param", "value"]),
		false,
		set_animation_tree_param
	))
	registry.register_tool(LumenToolSpec.new(
		"list_shader_params",
		"List shader uniforms on a CanvasItem or MeshInstance3D material.",
		_schema({"path": {"type": "string"}}, [], ["path"]),
		true,
		list_shader_params
	))
	registry.register_tool(LumenToolSpec.new(
		"playtest_input",
		"Queue keyboard, action, or mouse events and play the scene. World probe is written after replay.",
		_schema({
			"scene": {"type": "string"},
			"duration_ms": {"type": "integer"},
			"inputs": {"type": "array", "description": "[{type:key|action|mouse, key, action, x, y, wait_ms}]"},
		}, ["scene", "duration_ms"], ["inputs"]),
		false,
		playtest_input
	))
	registry.register_tool(LumenToolSpec.new(
		"run_gut_tests",
		"Play GUT runner if present, else list test_*.gd candidates.",
		_schema({"scene": {"type": "string"}}, ["scene"]),
		false,
		run_gut_tests
	))
	registry.register_tool(LumenToolSpec.new(
		"attach_csharp",
		"Write a .cs script and optionally attach it to a node. Needs a .NET Godot build.",
		_schema({
			"path": {"type": "string"},
			"class_name": {"type": "string"},
			"base": {"type": "string"},
			"node": {"type": "string"},
		}, ["class_name", "base", "node"], ["path"]),
		false,
		attach_csharp
	))
	registry.register_tool(LumenToolSpec.new(
		"list_slash_commands",
		"Built-in and project slash commands from res://lumen_commands.json.",
		_schema({}),
		true,
		list_slash_commands
	))


func search_engine_api(args: Dictionary) -> Dictionary:
	var q := str(args.get("query", "")).strip_edges().to_lower()
	if q == "":
		return {"ok": false, "error": "Empty query."}
	var limit := clampi(int(args.get("limit", 16)), 1, 40)
	var hits: Array = []
	for cls in ClassDB.get_class_list():
		var name := str(cls)
		if name.to_lower().find(q) < 0:
			continue
		hits.append({
			"class": name,
			"parent": ClassDB.get_parent_class(name),
			"docs": "https://docs.godotengine.org/en/stable/classes/class_%s.html" % name.to_lower(),
		})
		if hits.size() >= limit:
			break
	var local: Array = []
	for row in LumenDocsIndex.ENTRIES:
		var blob := (str(row.get("name", "")) + " " + str(row.get("blurb", ""))).to_lower()
		if blob.find(q) >= 0:
			local.append(row)
	return {"ok": true, "classdb": hits, "hints": local}


func list_class_methods(args: Dictionary) -> Dictionary:
	var name := str(args.get("class_name", "")).strip_edges()
	if name == "" or not ClassDB.class_exists(name):
		return {"ok": false, "error": "Unknown class.", "hint": "Use search_engine_api first."}
	var methods: Array = []
	for item in ClassDB.class_get_method_list(name, true):
		methods.append(str(item.get("name", "")))
		if methods.size() >= 80:
			break
	var props: Array = []
	for item in ClassDB.class_get_property_list(name, true):
		var pname := str(item.get("name", ""))
		if pname.begins_with("_"):
			continue
		props.append(pname)
		if props.size() >= 60:
			break
	return {
		"ok": true,
		"class": name,
		"parent": ClassDB.get_parent_class(name),
		"methods": methods,
		"properties": props,
		"docs": "https://docs.godotengine.org/en/stable/classes/class_%s.html" % name.to_lower(),
	}


func set_animation_tree_param(args: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "No edited scene."}
	var node := root.get_node_or_null(NodePath(str(args.get("path", ""))))
	if node == null or not (node is AnimationTree):
		return {"ok": false, "error": "AnimationTree not found."}
	var tree := node as AnimationTree
	var param := str(args.get("param", "")).strip_edges()
	if param == "":
		return {"ok": false, "error": "Empty param."}
	if not param.begins_with("parameters/"):
		param = "parameters/" + param
	var raw := str(args.get("value", "")).strip_edges()
	var parsed: Variant = raw
	if raw.find(",") >= 0:
		var parts := raw.split(",")
		if parts.size() >= 2:
			parsed = Vector2(parts[0].to_float(), parts[1].to_float())
	elif raw == "true" or raw == "false":
		parsed = raw == "true"
	elif raw.is_valid_float():
		parsed = raw.to_float()
	tree.set(param, parsed)
	tree.active = true
	return {"ok": true, "param": param, "value": str(parsed)}


func list_shader_params(args: Dictionary) -> Dictionary:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return {"ok": false, "error": "No edited scene."}
	var node := root.get_node_or_null(NodePath(str(args.get("path", ""))))
	if node == null:
		return {"ok": false, "error": "Node not found."}
	var mat: Material
	if node is CanvasItem:
		mat = (node as CanvasItem).material
	elif node is GeometryInstance3D:
		mat = (node as GeometryInstance3D).material_override
	if mat == null:
		return {"ok": false, "error": "No material on node."}
	if not (mat is ShaderMaterial):
		return {"ok": true, "kind": mat.get_class(), "hint": "Not a ShaderMaterial."}
	var sm := mat as ShaderMaterial
	var names: Array = []
	if sm.shader:
		for item in sm.shader.get_shader_uniform_list():
			names.append(item)
	return {"ok": true, "shader": sm.shader.resource_path if sm.shader else "", "uniforms": names}


func playtest_input(args: Dictionary) -> Dictionary:
	var sidecar := {
		"inputs": args.get("inputs", []),
		"duration_ms": int(args.get("duration_ms", 2500)),
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://.godot"))
	LumenJson.write_file("res://.godot/lumen_playtest.json", sidecar)
	var scene := str(args.get("scene", ""))
	if scene != "" and FileAccess.file_exists(scene):
		EditorInterface.play_custom_scene(scene)
	else:
		EditorInterface.play_current_scene()
	return {"ok": true, "playing": true, "inputs": sidecar["inputs"]}


func run_gut_tests(args: Dictionary) -> Dictionary:
	var scene := str(args.get("scene", ""))
	var runners := [
		scene,
		"res://addons/gut/gui/GutRunner.tscn",
		"res://tests/test.tscn",
		"res://test/GutTs.tscn",
	]
	for path in runners:
		if path != "" and FileAccess.file_exists(path):
			EditorInterface.play_custom_scene(path)
			return {"ok": true, "runner": path}
	var tests: Array = []
	_collect_tests("res://", tests, 50)
	return {"ok": true, "runner": "", "candidates": tests, "hint": "Install GUT or pass a runner scene."}


func attach_csharp(args: Dictionary) -> Dictionary:
	var path := str(args.get("path", "")).strip_edges()
	if not path.begins_with("res://") or not path.ends_with(".cs"):
		return {"ok": false, "error": "Path must be res://…cs"}
	var klass := str(args.get("class_name", path.get_file().get_basename()))
	var base := str(args.get("base", "Node"))
	if base == "":
		base = "Node"
	var body := "using Godot;\nusing System;\n\npublic partial class %s : %s\n{\n\tpublic override void _Ready()\n\t{\n\t}\n\n\tpublic override void _Process(double delta)\n\t{\n\t}\n}\n" % [klass, base]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var err := LumenJson.write_text(path, body)
	if err != OK:
		return {"ok": false, "error": error_string(err)}
	EditorInterface.get_resource_filesystem().scan()
	var node_path := str(args.get("node", "")).strip_edges()
	var attached := false
	if node_path != "":
		var root := EditorInterface.get_edited_scene_root()
		if root:
			var node := root.get_node_or_null(NodePath(node_path))
			if node:
				var script := load(path)
				if script:
					node.set_script(script)
					attached = true
	var dotnet := FileAccess.file_exists("res://*.csproj")
	if not dotnet:
		var dir := DirAccess.open("res://")
		if dir:
			dir.list_dir_begin()
			var n := dir.get_next()
			while n != "":
				if n.ends_with(".csproj"):
					dotnet = true
					break
				n = dir.get_next()
			dir.list_dir_end()
	return {"ok": true, "path": path, "attached": attached, "dotnet_project": dotnet}


func list_slash_commands(_args: Dictionary) -> Dictionary:
	var custom: Dictionary = {}
	for path in ["res://lumen_commands.json", "user://lumen/commands.json"]:
		var data: Variant = LumenJson.read_file(path, {})
		if typeof(data) == TYPE_DICTIONARY:
			for key in data.keys():
				custom[str(key)] = str(data[key])
	return {
		"ok": true,
		"builtin": ["/new", "/plan", "/default", "/model", "/undo", "/stop", "/docs", "/play"],
		"custom": custom,
	}


func _collect_tests(dir_path: String, out: Array, limit: int) -> void:
	if out.size() >= limit:
		return
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "" and out.size() < limit:
		if name.begins_with(".") or name == "addons":
			name = dir.get_next()
			continue
		var child := dir_path.path_join(name)
		if dir.current_is_dir():
			_collect_tests(child, out, limit)
		elif name.begins_with("test_") and (name.ends_with(".gd") or name.ends_with(".cs")):
			out.append(child)
		name = dir.get_next()
	dir.list_dir_end()


func _schema(properties: Dictionary, optional: Array = [], required: Array = []) -> Dictionary:
	var req: Array = required
	if req.is_empty():
		for key in properties.keys():
			if key not in optional:
				req.append(key)
	return {"type": "object", "properties": properties, "required": req}

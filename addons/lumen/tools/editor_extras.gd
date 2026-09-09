@tool
class_name LumenEditorExtras
extends RefCounted

## Scene depth, debugger, docs index, C# stub, inbound MCP, playtest report.

var settings: LumenSettings
var http: HTTPRequest
var _mcp_wait := false
var _mcp_body := {}


func attach(p_settings: LumenSettings, host: Node) -> void:
	settings = p_settings
	if host:
		http = HTTPRequest.new()
		http.timeout = 30
		http.use_threads = true
		host.add_child(http)
		http.request_completed.connect(_on_mcp)


func register(registry: LumenToolRegistry) -> void:
	registry.register_tool(LumenToolSpec.new(
		"duplicate_node", "Duplicate a node under the same parent in the edited scene.",
		_schema({"path": {"type": "string"}, "name": {"type": "string"}}, ["name"], ["path"]),
		false, duplicate_node
	))
	registry.register_tool(LumenToolSpec.new(
		"list_node_properties", "List exported / editor properties on a node.",
		_schema({"path": {"type": "string"}}, [], ["path"]), true, list_node_properties
	))
	registry.register_tool(LumenToolSpec.new(
		"list_signals", "List signals and current connections on a node.",
		_schema({"path": {"type": "string"}}, [], ["path"]), true, list_signals
	))
	registry.register_tool(LumenToolSpec.new(
		"connect_signal", "Connect a signal on one node to a method on another.",
		_schema({
			"from": {"type": "string"},
			"signal": {"type": "string"},
			"to": {"type": "string"},
			"method": {"type": "string"},
		}, [], ["from", "signal", "to", "method"]),
		false, connect_signal
	))
	registry.register_tool(LumenToolSpec.new(
		"disconnect_signal", "Disconnect one signal connection.",
		_schema({
			"from": {"type": "string"},
			"signal": {"type": "string"},
			"to": {"type": "string"},
			"method": {"type": "string"},
		}, [], ["from", "signal", "to", "method"]),
		false, disconnect_signal
	))
	registry.register_tool(LumenToolSpec.new(
		"add_to_group", "Add a node to a group.",
		_schema({"path": {"type": "string"}, "group": {"type": "string"}}, [], ["path", "group"]),
		false, add_to_group
	))
	registry.register_tool(LumenToolSpec.new(
		"list_animations", "List AnimationPlayer or AnimationTree clips on a node.",
		_schema({"path": {"type": "string"}}, [], ["path"]), true, list_animations
	))
	registry.register_tool(LumenToolSpec.new(
		"play_animation", "Play a clip on an AnimationPlayer in the edited scene.",
		_schema({"path": {"type": "string"}, "animation": {"type": "string"}}, [], ["path", "animation"]),
		false, play_animation
	))
	registry.register_tool(LumenToolSpec.new(
		"write_shader", "Write a .gdshader file and optionally assign it to a node material.",
		_schema({
			"path": {"type": "string", "description": "res://…gdshader"},
			"code": {"type": "string"},
			"node": {"type": "string", "description": "Optional node to assign ShaderMaterial"},
		}, ["node"], ["path", "code"]),
		false, write_shader
	))
	registry.register_tool(LumenToolSpec.new(
		"create_csharp_script", "Write a C# Godot script stub (.cs) under res://.",
		_schema({
			"path": {"type": "string"},
			"class_name": {"type": "string"},
			"base": {"type": "string"},
		}, ["base"], ["path", "class_name"]),
		false, create_csharp_script
	))
	registry.register_tool(LumenToolSpec.new(
		"import_asset", "Copy a file already inside the project into res://assets/.",
		_schema({
			"from": {"type": "string"},
			"to": {"type": "string"},
		}, ["to"], ["from"]),
		false, import_asset
	))
	registry.register_tool(LumenToolSpec.new(
		"get_debugger", "Playing state, recent error/warning lines, last playtest report.",
		_schema({}), true, get_debugger
	))
	registry.register_tool(LumenToolSpec.new(
		"get_playtest_report", "Read the last playtest harness report (inputs + world snapshot).",
		_schema({}), true, get_playtest_report
	))
	registry.register_tool(LumenToolSpec.new(
		"search_godot_docs", "Local class index plus official docs URLs. No page scrape.",
		_schema({"topic": {"type": "string"}}, [], ["topic"]), true, search_godot_docs
	))
	registry.register_tool(LumenToolSpec.new(
		"update_todos", "Replace the live todo list shown in the dock.",
		_schema({"items": {"type": "array"}}, [], ["items"]),
		true, update_todos
	))
	registry.register_tool(LumenToolSpec.new(
		"create_primitive_mesh", "Add a MeshInstance3D using Godot PrimitiveMesh (box, sphere, capsule, cylinder, plane, prism, torus).",
		_schema({
			"parent": {"type": "string"},
			"name": {"type": "string"},
			"shape": {"type": "string"},
			"size": {"type": "number"},
			"x": {"type": "number"},
			"y": {"type": "number"},
			"z": {"type": "number"},
			"color": {"type": "string", "description": "hex like #4a90d9"},
		}, ["parent", "size", "x", "y", "z", "color"], ["name"]),
		false, create_primitive_mesh
	))
	registry.register_tool(LumenToolSpec.new(
		"set_mesh_material", "Assign a StandardMaterial3D on a MeshInstance3D or CSG shape.",
		_schema({
			"path": {"type": "string"},
			"color": {"type": "string"},
			"metallic": {"type": "number"},
			"roughness": {"type": "number"},
		}, ["metallic", "roughness"], ["path", "color"]),
		false, set_mesh_material
	))
	registry.register_tool(LumenToolSpec.new(
		"add_csg", "Add a CSGBox3D / CSGSphere3D / CSGCylinder3D. operation: union, subtraction, intersection.",
		_schema({
			"parent": {"type": "string"},
			"name": {"type": "string"},
			"shape": {"type": "string"},
			"operation": {"type": "string"},
			"size": {"type": "number"},
			"x": {"type": "number"},
			"y": {"type": "number"},
			"z": {"type": "number"},
		}, ["parent", "operation", "size", "x", "y", "z"], ["name"]),
		false, add_csg
	))
	registry.register_tool(LumenToolSpec.new(
		"instance_3d", "Instance a packed scene or imported 3D asset (.tscn, .glb, .gltf, .fbx) into the edited scene.",
		_schema({
			"path": {"type": "string"},
			"parent": {"type": "string"},
			"name": {"type": "string"},
			"x": {"type": "number"},
			"y": {"type": "number"},
			"z": {"type": "number"},
		}, ["parent", "name", "x", "y", "z"], ["path"]),
		false, instance_3d
	))
	registry.register_tool(LumenToolSpec.new(
		"list_mcp_servers", "List inbound MCP servers from project settings (mcp_servers).",
		_schema({}), true, list_mcp_servers
	))
	registry.register_tool(LumenToolSpec.new(
		"mcp_call", "Call a tool on a configured inbound HTTP MCP server (127.0.0.1 only).",
		_schema({
			"server": {"type": "string"},
			"tool": {"type": "string"},
			"arguments": {"type": "object"},
		}, ["arguments"], ["server", "tool"]),
		false, mcp_call
	))


func _schema(properties: Dictionary, optional: Array = [], required: Array = []) -> Dictionary:
	var req: Array = required
	if req.is_empty():
		for key in properties.keys():
			if key not in optional:
				req.append(key)
	return {"type": "object", "properties": properties, "required": req}


func _find(path: String) -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	if path == "" or path == "." or path == str(root.name):
		return root
	return root.get_node_or_null(NodePath(path))


func _rel(node: Node) -> String:
	var root := EditorInterface.get_edited_scene_root()
	if root == null or node == null:
		return ""
	return str(root.get_path_to(node))


func _safe_res(path: String) -> String:
	var res := LumenPaths.to_res(path.strip_edges())
	if not res.begins_with("res://"):
		res = "res://" + res.lstrip("/")
	if res.begins_with("res://addons/lumen/") or ".." in res.split("/"):
		return ""
	if not LumenPaths.is_inside_project(res):
		return ""
	return res


func _dirty() -> void:
	EditorInterface.mark_scene_as_unsaved()


func _scan() -> void:
	var fs := EditorInterface.get_resource_filesystem()
	if fs:
		fs.scan()


func duplicate_node(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found."}
	var root := EditorInterface.get_edited_scene_root()
	if node == root:
		return {"ok": false, "error": "Refusing to duplicate the scene root."}
	var parent := node.get_parent()
	if parent == null:
		return {"ok": false, "error": "Node has no parent."}
	var copy := node.duplicate()
	var new_name := str(args.get("name", "")).strip_edges()
	if new_name != "":
		copy.name = new_name
	parent.add_child(copy)
	copy.owner = root
	_dirty()
	return {"ok": true, "path": _rel(copy)}


func list_node_properties(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found."}
	var rows: Array = []
	for prop in node.get_property_list():
		if typeof(prop) != TYPE_DICTIONARY:
			continue
		var usage := int(prop.get("usage", 0))
		if usage & PROPERTY_USAGE_EDITOR == 0:
			continue
		var name := str(prop.get("name", ""))
		if name == "" or name.begins_with("_"):
			continue
		rows.append({
			"name": name,
			"type": type_string(typeof(node.get(name))),
			"value": _short(node.get(name)),
		})
		if rows.size() >= 80:
			break
	return {"ok": true, "path": _rel(node), "type": node.get_class(), "properties": rows}


func list_signals(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found."}
	var signals: Array = []
	for info in node.get_signal_list():
		if typeof(info) != TYPE_DICTIONARY:
			continue
		var sig := str(info.get("name", ""))
		var conns: Array = []
		for conn in node.get_signal_connection_list(sig):
			if typeof(conn) != TYPE_DICTIONARY:
				continue
			var target: Variant = conn.get("callable")
			var callable := target as Callable
			conns.append({
				"to": str(callable.get_object()) if callable.is_valid() else "",
				"method": callable.get_method() if callable.is_valid() else "",
			})
		signals.append({"name": sig, "connections": conns})
		if signals.size() >= 60:
			break
	return {"ok": true, "path": _rel(node), "signals": signals, "groups": node.get_groups()}


func connect_signal(args: Dictionary) -> Dictionary:
	var from := _find(str(args.get("from", "")))
	var to := _find(str(args.get("to", "")))
	if from == null or to == null:
		return {"ok": false, "error": "from or to not found."}
	var sig := str(args.get("signal", ""))
	var method := str(args.get("method", ""))
	if not from.has_signal(sig):
		return {"ok": false, "error": "No signal %s on %s." % [sig, from.name]}
	if not to.has_method(method):
		return {"ok": false, "error": "No method %s on %s." % [method, to.name]}
	var err := from.connect(sig, Callable(to, method))
	if err != OK:
		return {"ok": false, "error": error_string(err)}
	_dirty()
	return {"ok": true, "from": _rel(from), "signal": sig, "to": _rel(to), "method": method}


func disconnect_signal(args: Dictionary) -> Dictionary:
	var from := _find(str(args.get("from", "")))
	var to := _find(str(args.get("to", "")))
	if from == null or to == null:
		return {"ok": false, "error": "from or to not found."}
	var sig := str(args.get("signal", ""))
	var method := str(args.get("method", ""))
	if from.is_connected(sig, Callable(to, method)):
		from.disconnect(sig, Callable(to, method))
	_dirty()
	return {"ok": true}


func add_to_group(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found."}
	var group := str(args.get("group", "")).strip_edges()
	if group == "":
		return {"ok": false, "error": "Empty group."}
	node.add_to_group(group)
	_dirty()
	return {"ok": true, "path": _rel(node), "groups": node.get_groups()}


func list_animations(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found."}
	if node is AnimationPlayer:
		var player := node as AnimationPlayer
		return {"ok": true, "kind": "AnimationPlayer", "animations": player.get_animation_list(), "current": player.current_animation}
	if node is AnimationTree:
		var tree := node as AnimationTree
		return {"ok": true, "kind": "AnimationTree", "active": tree.active, "tree_root": str(tree.tree_root)}
	return {"ok": false, "error": "Node is not AnimationPlayer or AnimationTree."}


func play_animation(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null or not (node is AnimationPlayer):
		return {"ok": false, "error": "AnimationPlayer not found."}
	var player := node as AnimationPlayer
	var clip := str(args.get("animation", ""))
	if not player.has_animation(clip):
		return {"ok": false, "error": "Unknown clip.", "animations": player.get_animation_list()}
	player.play(clip)
	return {"ok": true, "animation": clip}


func write_shader(args: Dictionary) -> Dictionary:
	var path := _safe_res(str(args.get("path", "")))
	if path == "" or not path.ends_with(".gdshader"):
		return {"ok": false, "error": "Path must be a res://…gdshader file."}
	var err := LumenJson.write_text(path, str(args.get("code", "")))
	if err != OK:
		return {"ok": false, "error": error_string(err)}
	_scan()
	var node_path := str(args.get("node", "")).strip_edges()
	if node_path != "":
		var node := _find(node_path)
		if node and node is CanvasItem:
			var shader := load(path) as Shader
			if shader:
				var mat := ShaderMaterial.new()
				mat.shader = shader
				(node as CanvasItem).material = mat
				_dirty()
	return {"ok": true, "path": path}


func create_csharp_script(args: Dictionary) -> Dictionary:
	var path := _safe_res(str(args.get("path", "")))
	if path == "" or not path.ends_with(".cs"):
		return {"ok": false, "error": "Path must be a res://…cs file."}
	var klass := str(args.get("class_name", "NewNode")).strip_edges()
	var base := str(args.get("base", "Node")).strip_edges()
	if base == "":
		base = "Node"
	var body := "using Godot;\n\npublic partial class %s : %s\n{\n\tpublic override void _Ready()\n\t{\n\t}\n}\n" % [klass, base]
	var err := LumenJson.write_text(path, body)
	if err != OK:
		return {"ok": false, "error": error_string(err)}
	_scan()
	return {"ok": true, "path": path}


func import_asset(args: Dictionary) -> Dictionary:
	var from := _safe_res(str(args.get("from", "")))
	if from == "" or not FileAccess.file_exists(from):
		return {"ok": false, "error": "Source not inside the project."}
	var dest := str(args.get("to", "")).strip_edges()
	if dest == "":
		dest = "res://assets/" + from.get_file()
	dest = _safe_res(dest)
	if dest == "":
		return {"ok": false, "error": "Destination rejected."}
	DirAccess.make_dir_recursive_absolute(LumenPaths.to_abs(dest.get_base_dir()))
	var err := DirAccess.copy_absolute(LumenPaths.to_abs(from), LumenPaths.to_abs(dest))
	_scan()
	return {"ok": err == OK, "from": from, "to": dest, "error": error_string(err) if err != OK else ""}


func get_debugger(_args: Dictionary) -> Dictionary:
	var open_scripts: Array = []
	var se := EditorInterface.get_script_editor()
	if se:
		for script in se.get_open_scripts():
			if script:
				open_scripts.append(script.resource_path)
	var hits: Array = []
	for log_path in [
		OS.get_user_data_dir().path_join("logs/godot.log"),
		ProjectSettings.globalize_path("user://logs/godot.log"),
	]:
		if not FileAccess.file_exists(log_path):
			continue
		var lines := FileAccess.get_file_as_string(log_path).split("\n")
		var start := maxi(0, lines.size() - 400)
		for i in range(start, lines.size()):
			var line := lines[i]
			var lower := line.to_lower()
			if "error" in lower or "warning" in lower or "stack trace" in lower or "at:" in lower:
				hits.append(line.strip_edges())
				if hits.size() >= 50:
					break
		break
	return {
		"ok": true,
		"playing": EditorInterface.is_playing_scene(),
		"playing_scene": EditorInterface.get_playing_scene(),
		"open_scripts": open_scripts,
		"log_hits": hits,
		"playtest": get_playtest_report({}),
		"debugger": LumenDebuggerPlugin.snapshot(),
	}


func get_playtest_report(_args: Dictionary) -> Dictionary:
	var path := "user://lumen/playtest_report.json"
	if not FileAccess.file_exists(path):
		return {"ok": true, "present": false, "hint": "Run playtest_batch. The harness writes this after replay."}
	var data: Variant = LumenJson.read_file(path, {})
	return {"ok": true, "present": true, "report": data}


func search_godot_docs(args: Dictionary) -> Dictionary:
	var topic := str(args.get("topic", "")).strip_edges()
	if topic == "":
		return {"ok": false, "error": "Empty topic."}
	var needle := topic.to_lower().replace(" ", "")
	var hits: Array = []
	for row in LumenDocsIndex.ENTRIES:
		var name := str(row.get("name", ""))
		var blob := (name + " " + str(row.get("blurb", ""))).to_lower().replace(" ", "")
		if name.to_lower() == topic.to_lower() or blob.find(needle) >= 0:
			hits.append(row)
		if hits.size() >= 12:
			break
	var slug := topic.to_lower().replace(" ", "_")
	return {
		"ok": true,
		"hits": hits,
		"class_url": "https://docs.godotengine.org/en/stable/classes/class_%s.html" % slug,
		"search_url": "https://docs.godotengine.org/en/stable/search.html?q=%s" % topic.uri_encode(),
	}


func update_todos(args: Dictionary) -> Dictionary:
	var raw: Variant = args.get("items", [])
	var items := LumenTodos.set_items(raw if typeof(raw) == TYPE_ARRAY else [])
	return {"ok": true, "items": items}


func create_primitive_mesh(args: Dictionary) -> Dictionary:
	var parent := _parent_of(args)
	if parent == null:
		return {"ok": false, "error": "Parent or edited scene missing."}
	var shape := str(args.get("shape", "box")).to_lower()
	var size := float(args.get("size", 1.0))
	var mesh := _primitive(shape, size)
	if mesh == null:
		return {"ok": false, "error": "Unknown shape. Use box, sphere, capsule, cylinder, plane, prism, torus."}
	var inst := MeshInstance3D.new()
	inst.name = str(args.get("name", shape.capitalize()))
	inst.mesh = mesh
	_place_3d(inst, args)
	parent.add_child(inst)
	inst.owner = EditorInterface.get_edited_scene_root()
	var color := str(args.get("color", "")).strip_edges()
	if color != "":
		inst.material_override = _std_mat(color, 0.0, 0.8)
	_dirty()
	return {"ok": true, "path": _rel(inst), "shape": shape}


func set_mesh_material(args: Dictionary) -> Dictionary:
	var node := _find(str(args.get("path", "")))
	if node == null:
		return {"ok": false, "error": "Node not found."}
	var mat := _std_mat(
		str(args.get("color", "#cccccc")),
		float(args.get("metallic", 0.0)),
		float(args.get("roughness", 0.8))
	)
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	elif node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = mat
	elif node is CSGShape3D:
		(node as CSGShape3D).material = mat
	else:
		return {"ok": false, "error": "Node has no 3D material slot."}
	_dirty()
	return {"ok": true, "path": _rel(node)}


func add_csg(args: Dictionary) -> Dictionary:
	var parent := _parent_of(args)
	if parent == null:
		return {"ok": false, "error": "Parent or edited scene missing."}
	var shape := str(args.get("shape", "box")).to_lower()
	var size := float(args.get("size", 1.0))
	var node: CSGShape3D
	match shape:
		"sphere":
			var sph := CSGSphere3D.new()
			sph.radius = size * 0.5
			node = sph
		"cylinder":
			var cyl := CSGCylinder3D.new()
			cyl.radius = size * 0.5
			cyl.height = size
			node = cyl
		_:
			var box := CSGBox3D.new()
			box.size = Vector3(size, size, size)
			node = box
			shape = "box"
	node.name = str(args.get("name", "CSG"))
	var op := str(args.get("operation", "union")).to_lower()
	match op:
		"subtraction", "subtract":
			node.operation = CSGShape3D.OPERATION_SUBTRACTION
		"intersection":
			node.operation = CSGShape3D.OPERATION_INTERSECTION
		_:
			node.operation = CSGShape3D.OPERATION_UNION
	_place_3d(node, args)
	parent.add_child(node)
	node.owner = EditorInterface.get_edited_scene_root()
	_dirty()
	return {"ok": true, "path": _rel(node), "shape": shape, "operation": op}


func instance_3d(args: Dictionary) -> Dictionary:
	var parent := _parent_of(args)
	if parent == null:
		return {"ok": false, "error": "Parent or edited scene missing."}
	var path := _safe_res(str(args.get("path", "")))
	if path == "" or not ResourceLoader.exists(path):
		return {"ok": false, "error": "Asset not found. Import the .glb/.gltf in Godot first."}
	var packed: Resource = load(path)
	if packed == null:
		return {"ok": false, "error": "Could not load %s" % path}
	var inst: Node
	if packed is PackedScene:
		inst = (packed as PackedScene).instantiate()
	elif packed is Mesh:
		var mi := MeshInstance3D.new()
		mi.mesh = packed
		inst = mi
	else:
		return {"ok": false, "error": "Not a scene or mesh: %s" % packed.get_class()}
	var given := str(args.get("name", "")).strip_edges()
	if given != "":
		inst.name = given
	if inst is Node3D:
		_place_3d(inst as Node3D, args)
	parent.add_child(inst)
	_own_tree(inst, EditorInterface.get_edited_scene_root())
	_dirty()
	return {"ok": true, "path": _rel(inst), "asset": path}


func _parent_of(args: Dictionary) -> Node:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	var parent_path := str(args.get("parent", ""))
	return root if parent_path == "" else root.get_node_or_null(NodePath(parent_path))


func _place_3d(node: Node3D, args: Dictionary) -> void:
	if args.has("x") or args.has("y") or args.has("z"):
		node.position = Vector3(float(args.get("x", 0)), float(args.get("y", 0)), float(args.get("z", 0)))


func _primitive(shape: String, size: float) -> PrimitiveMesh:
	match shape:
		"sphere":
			var s := SphereMesh.new()
			s.radius = size * 0.5
			s.height = size
			return s
		"capsule":
			var c := CapsuleMesh.new()
			c.radius = size * 0.25
			c.height = size
			return c
		"cylinder":
			var y := CylinderMesh.new()
			y.top_radius = size * 0.5
			y.bottom_radius = size * 0.5
			y.height = size
			return y
		"plane":
			var p := PlaneMesh.new()
			p.size = Vector2(size, size)
			return p
		"prism":
			return PrismMesh.new()
		"torus":
			var t := TorusMesh.new()
			t.inner_radius = size * 0.25
			t.outer_radius = size * 0.5
			return t
		"box", "cube":
			var b := BoxMesh.new()
			b.size = Vector3(size, size, size)
			return b
		_:
			return null


func _std_mat(color: String, metallic: float, roughness: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.html(color) if color.begins_with("#") else Color(color)
	mat.metallic = clampf(metallic, 0.0, 1.0)
	mat.roughness = clampf(roughness, 0.0, 1.0)
	return mat


func _own_tree(node: Node, owner: Node) -> void:
	node.owner = owner
	for child in node.get_children():
		_own_tree(child, owner)


func list_mcp_servers(_args: Dictionary) -> Dictionary:
	return {"ok": true, "servers": _servers()}


func mcp_call(args: Dictionary) -> Dictionary:
	var name := str(args.get("server", ""))
	var tool := str(args.get("tool", ""))
	var payload_args: Variant = args.get("arguments", {})
	var target := {}
	for row in _servers():
		if str(row.get("name", "")) == name:
			target = row
			break
	if target.is_empty():
		return {"ok": false, "error": "Unknown MCP server. Set mcp_servers in project.json."}
	var url := str(target.get("url", "")).strip_edges()
	if not _local_url(url):
		return {"ok": false, "error": "Inbound MCP only talks to 127.0.0.1 / localhost."}
	if http == null:
		return {"ok": false, "error": "HTTP helper missing."}
	if _mcp_wait:
		return {"ok": false, "error": "Another MCP call is running."}
	var body := JSON.stringify({
		"jsonrpc": "2.0",
		"id": 1,
		"method": "tools/call",
		"params": {"name": tool, "arguments": payload_args if typeof(payload_args) == TYPE_DICTIONARY else {}},
	})
	_mcp_wait = true
	_mcp_body = {}
	var err := http.request(url, PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, body)
	if err != OK:
		_mcp_wait = false
		return {"ok": false, "error": error_string(err)}
	var waited := 0
	while _mcp_wait and waited < 30000:
		OS.delay_msec(50)
		waited += 50
	if _mcp_wait:
		_mcp_wait = false
		return {"ok": false, "error": "MCP call timed out."}
	return _mcp_body


func _on_mcp(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_mcp_wait = false
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_mcp_body = {"ok": false, "error": "MCP HTTP %d/%d" % [result, code]}
		return
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	_mcp_body = {"ok": true, "response": parsed}


func _servers() -> Array:
	var raw: Variant = settings.get_value("mcp_servers", []) if settings else []
	return raw if typeof(raw) == TYPE_ARRAY else []


func _local_url(url: String) -> bool:
	var lower := url.to_lower()
	return lower.begins_with("http://127.0.0.1") or lower.begins_with("http://localhost")


func _short(value: Variant) -> Variant:
	match typeof(value):
		TYPE_STRING:
			return LumenJson.clamp_text(str(value), 80)
		TYPE_OBJECT:
			return str(value)
		TYPE_ARRAY:
			return "(array %d)" % (value as Array).size()
		TYPE_DICTIONARY:
			return "(dict)"
		_:
			return value

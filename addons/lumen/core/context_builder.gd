@tool
class_name LumenContextBuilder
extends RefCounted

var plugin: EditorPlugin


func _init(p_plugin: EditorPlugin) -> void:
	plugin = p_plugin


func snapshot() -> Dictionary:
	var ei := plugin.get_editor_interface()
	var root := ei.get_edited_scene_root()
	var fs := ei.get_resource_filesystem()
	return {
		"godot": Engine.get_version_info(),
		"project_name": ProjectSettings.get_setting("application/config/name", ""),
		"project_path": LumenPaths.project_root(),
		"edited_scene": root.scene_file_path if root else "",
		"edited_root": root.name if root else "",
		"selected_nodes": _selected_paths(ei, root),
		"open_scripts": _open_scripts(ei),
		"filesystem_ready": fs.is_scanning() == false if fs else true,
	}


func _open_scripts(ei: EditorInterface) -> Array:
	var out: Array = []
	var editor := ei.get_script_editor()
	if editor == null:
		return out
	for script in editor.get_open_scripts():
		if script:
			out.append(str(script.resource_path))
	return out


func _selected_paths(ei: EditorInterface, root: Node) -> Array:
	var out: Array = []
	var selection := ei.get_selection()
	if selection == null:
		return out
	for node in selection.get_selected_nodes():
		if node == null:
			continue
		if root:
			out.append(str(root.get_path_to(node)))
		else:
			out.append(str(node.get_path()))
	return out


func system_preamble(settings: LumenSettings, skills: LumenSkillLoader) -> String:
	var ctx := snapshot()
	var agents := LumenAgentsMd.load_instructions()
	var parts: PackedStringArray = PackedStringArray([
		"You are Lumen, a Godot editor agent. Edit through tools only. Read a file before you change it. Never invent unread contents.",
		"Use the native tool_calls channel. Do not wrap calls in markdown. One or two tools per step. Smallest patch that works.",
		"Local models: if a needed tool is missing, call list_more_tools then enable_tools. If a tool result was truncated, read a narrower range.",
		"Plan mode: write a plan and wait. Do not call write tools until the user approves.",
		"Godot %s. Project %s. Edited scene %s (%s). Selected: %s. Open scripts: %s" % [
			str((ctx.get("godot", {}) as Dictionary).get("string", "4.x")) if typeof(ctx.get("godot", {})) == TYPE_DICTIONARY else "4.x",
			str(ctx.get("project_name", "")),
			str(ctx.get("edited_scene", "")),
			str(ctx.get("edited_root", "")),
			", ".join(PackedStringArray(ctx.get("selected_nodes", []))),
			", ".join(PackedStringArray(ctx.get("open_scripts", []))),
		],
		"Available skills (load_skill before following them):\n%s" % skills.describe_for_prompt(),
	])
	if agents != "":
		parts.append("AGENTS.md:\n%s" % LumenJson.clamp_text(agents, 2500))
	return "\n\n".join(parts)

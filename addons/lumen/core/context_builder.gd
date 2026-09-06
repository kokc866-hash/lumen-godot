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


func system_preamble(settings: LumenSettings, skills: LumenSkillLoader) -> String:
	var ctx := snapshot()
	var agents := LumenAgentsMd.load_instructions()
	var parts: PackedStringArray = PackedStringArray([
		"You are Lumen, a local-first AI agent that lives inside the Godot editor.",
		"You edit this project through tools. You never invent file contents you have not read.",
		"Prefer the smallest change that works. Do not add multiplayer relays, accounts, or billing.",
		"When a decision is the author's, ask instead of guessing.",
		"Plan mode: if the user asked for a plan, output the plan first and wait. Do not call write tools until approved.",
		"Godot version: %s" % JSON.stringify(ctx.get("godot", {})),
		"Project: %s" % ctx.get("project_name", ""),
		"Edited scene: %s (%s)" % [ctx.get("edited_scene", ""), ctx.get("edited_root", "")],
		"Open scripts: %s" % ", ".join(PackedStringArray(ctx.get("open_scripts", []))),
		"Available skills (load with load_skill before following them):\n%s" % skills.describe_for_prompt(),
	])
	if agents != "":
		parts.append("Project instructions from AGENTS.md:\n%s" % LumenJson.clamp_text(agents, 8000))
	return "\n\n".join(parts)

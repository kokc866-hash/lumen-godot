@tool
class_name LumenSkillLoader
extends RefCounted

## Progressive disclosure: descriptions always go into the system prompt.
## Full SKILL.md is only loaded when the agent names the skill.

var log: LumenLogger


func _init(p_log: LumenLogger) -> void:
	log = p_log


func catalog() -> Array:
	var skills: Array = []
	var seen := {}
	for root in _roots():
		_scan(root, skills, seen)
	return skills


func load_skill(name: String) -> String:
	for skill in catalog():
		if str(skill.get("name", "")).to_lower() == name.to_lower():
			return LumenJson.read_text(str(skill.get("path", "")))
	return ""


func describe_for_prompt() -> String:
	var lines: PackedStringArray = PackedStringArray()
	for skill in catalog():
		lines.append("- %s: %s" % [skill.get("name", ""), skill.get("description", "")])
	if lines.is_empty():
		return "(none installed)"
	return "\n".join(lines)


func _roots() -> Array:
	return [
		"res://.lumen/skills",
		"res://.agents/skills",
		OS.get_user_data_dir().path_join("lumen/skills"),
	]


func _scan(root: String, skills: Array, seen: Dictionary) -> void:
	var abs_root := LumenPaths.to_abs(root) if root.begins_with("res://") else root
	var dir := DirAccess.open(abs_root)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if dir.current_is_dir() and not entry.begins_with("."):
			var skill_md := abs_root.path_join(entry).path_join("SKILL.md")
			var res_md := root.path_join(entry).path_join("SKILL.md") if root.begins_with("res://") else skill_md
			if FileAccess.file_exists(res_md) or FileAccess.file_exists(skill_md):
				var path := res_md if FileAccess.file_exists(res_md) else skill_md
				var parsed := _parse_frontmatter(LumenJson.read_text(path))
				var name := str(parsed.get("name", entry))
				if not seen.has(name):
					seen[name] = true
					skills.append({
						"name": name,
						"description": str(parsed.get("description", "")),
						"path": path,
					})
		entry = dir.get_next()
	dir.list_dir_end()


func _parse_frontmatter(text: String) -> Dictionary:
	var out := {"name": "", "description": ""}
	if not text.begins_with("---"):
		return out
	var end := text.find("---", 3)
	if end < 0:
		return out
	for line in text.substr(3, end - 3).split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("name:"):
			out["name"] = trimmed.substr(5).strip_edges().trim_prefix('"').trim_suffix('"')
		elif trimmed.begins_with("description:"):
			out["description"] = trimmed.substr(12).strip_edges().trim_prefix('"').trim_suffix('"')
	return out

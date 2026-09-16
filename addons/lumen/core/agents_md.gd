@tool
class_name LumenAgentsMd
extends RefCounted


static func load_instructions() -> String:
	for path in LumenPaths.AGENTS_CANDIDATES:
		if FileAccess.file_exists(path):
			return LumenJson.read_text(path)
	var user_path := OS.get_user_data_dir().path_join("lumen/AGENTS.md")
	if FileAccess.file_exists(user_path):
		return FileAccess.get_file_as_string(user_path)
	return default_text()


static func default_text() -> String:
	return """# AGENTS.md — this Godot project (Lumen)

- Change the game through editor tools, not by guessing .tscn text.
- Before a large edit: `observe`. After a write: `validate_script` on every touched .gd, then `observe_diff`.
- Play to check behaviour: `playtest_record` or `playtest_batch`, then `get_playtest_report`.
- Assets are optional. Image/Mesh keys live in the dock. No key = skip gen and use Godot primitives.
- Keep title-specific content in the project. Reusable agent rules stay in this file.
"""


static func ensure_project_file() -> void:
	if FileAccess.file_exists("res://AGENTS.md"):
		return
	LumenJson.write_text("res://AGENTS.md", default_text())

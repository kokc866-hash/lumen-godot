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
	return ""

@tool
class_name LumenJson
extends RefCounted


static func read_file(path: String, fallback: Variant = null) -> Variant:
	if not FileAccess.file_exists(path):
		return fallback
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return fallback
	var text := file.get_as_text()
	var parsed: Variant = JSON.parse_string(text)
	return fallback if parsed == null else parsed


static func write_file(path: String, data: Variant) -> Error:
	LumenPaths.ensure_dirs()
	var abs_path := LumenPaths.to_abs(path)
	var parent := abs_path.get_base_dir()
	DirAccess.make_dir_recursive_absolute(parent)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(data, "\t"))
	return OK


static func read_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


static func write_text(path: String, text: String) -> Error:
	var abs_path := LumenPaths.to_abs(path)
	DirAccess.make_dir_recursive_absolute(abs_path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	return OK


static func clamp_text(text: String, max_chars: int) -> String:
	if text.length() <= max_chars:
		return text
	return text.substr(0, max_chars) + "\n…[%d chars total]" % text.length()

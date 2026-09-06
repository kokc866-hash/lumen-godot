@tool
class_name LumenLogger
extends RefCounted

const MAX_BYTES := 512_000
var _path: String


func _init(filename: String = "lumen.log") -> void:
	LumenPaths.ensure_dirs()
	_path = LumenPaths.LOG_DIR.path_join(filename)


func info(message: String) -> void:
	_write("INFO", message)


func warn(message: String) -> void:
	_write("WARN", message)
	push_warning("[Lumen] " + message)


func error(message: String) -> void:
	_write("ERROR", message)
	push_error("[Lumen] " + message)


func _write(level: String, message: String) -> void:
	var line := "%s [%s] %s\n" % [
		Time.get_datetime_string_from_system(true, true),
		level,
		message,
	]
	var existing := ""
	if FileAccess.file_exists(_path):
		var reader := FileAccess.open(_path, FileAccess.READ)
		if reader:
			existing = reader.get_as_text()
			if existing.length() > MAX_BYTES:
				existing = existing.substr(existing.length() - MAX_BYTES / 2)
	var writer := FileAccess.open(_path, FileAccess.WRITE)
	if writer:
		writer.store_string(existing + line)

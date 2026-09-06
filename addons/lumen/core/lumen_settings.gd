@tool
class_name LumenSettings
extends RefCounted

signal changed

const DEFAULTS := {
	"provider": "",
	"base_url": "",
	"model": "",
	"temperature": 0.2,
	"max_tokens": 4096,
	"num_ctx": 65536,
	"tool_result_chars": 8000,
	"keep_alive": "-1",
	"think": false,
	"compact_tools": true,
	"plan_mode": false,
	"auto_approve_readonly": true,
	"mcp_enabled": false,
	"mcp_port": 8765,
	"image_base_url": "",
	"image_model": "",
	"docs_url": "https://docs.godotengine.org/en/stable/",
}

var project: Dictionary = {}
var secrets: Dictionary = {}
var log: LumenLogger


func _init(p_log: LumenLogger = null) -> void:
	log = p_log if p_log else LumenLogger.new()
	reload()


func reload() -> void:
	LumenPaths.ensure_dirs()
	project = LumenJson.read_file(LumenPaths.PROJECT_CONFIG, {})
	if typeof(project) != TYPE_DICTIONARY:
		project = {}
	secrets = LumenJson.read_file(LumenPaths.USER_SECRETS, {})
	if typeof(secrets) != TYPE_DICTIONARY:
		secrets = {}


func get_value(key: String, fallback: Variant = null) -> Variant:
	if project.has(key):
		return project[key]
	if DEFAULTS.has(key):
		return DEFAULTS[key]
	return fallback


func set_value(key: String, value: Variant, persist: bool = true) -> void:
	project[key] = value
	if persist:
		save_project()
	changed.emit()


func save_project() -> void:
	var err := LumenJson.write_file(LumenPaths.PROJECT_CONFIG, project)
	if err != OK:
		log.error("Could not write project config: %s" % error_string(err))


func api_key() -> String:
	return str(secrets.get("api_key", ""))


func set_api_key(value: String) -> void:
	secrets["api_key"] = value
	LumenJson.write_file(LumenPaths.USER_SECRETS, secrets)


func image_api_key() -> String:
	var key := str(secrets.get("image_api_key", ""))
	return key if key != "" else api_key()


func provider_id() -> String:
	return str(get_value("provider", ""))


func base_url() -> String:
	return str(get_value("base_url"))


func model() -> String:
	return str(get_value("model", ""))


func plan_mode() -> bool:
	return bool(get_value("plan_mode", false))


func auto_approve_readonly() -> bool:
	return bool(get_value("auto_approve_readonly", true))

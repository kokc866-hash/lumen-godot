@tool
class_name LumenSettings
extends RefCounted

signal changed

## Protocol is what the wire format accepts. Auth (key vs CLI session) is separate.
## ollama     POST /api/chat — options.num_ctx (server default 2048), keep_alive, think
## openai     POST /v1/chat/completions — no num_ctx. LM Studio context is load-time only.
## anthropic  POST /v1/messages — max_tokens required. thinking is an object, not a bool.
## gemini     vendor CLI / generateContent

const KIND_LOCAL := "local"
const KIND_API := "api"
const KIND_SUB := "subscription"
const PROTO_OLLAMA := "ollama"
const PROTO_OPENAI := "openai"
const PROTO_ANTHROPIC := "anthropic"
const PROTO_GEMINI := "gemini"

const PROVIDER_KIND := {
	"ollama": KIND_LOCAL,
	"lmstudio": KIND_LOCAL,
	"openai": KIND_API,
	"grok": KIND_API,
	"anthropic": KIND_API,
	"custom": KIND_API,
	"codex_cli": KIND_SUB,
	"claude_cli": KIND_SUB,
	"gemini_cli": KIND_SUB,
}

const KIND_DEFAULTS := {
	KIND_LOCAL: {
		"num_ctx": 65536,
		"keep_alive": "-1",
		"think": false,
		"compact_tools": true,
		"temperature": 0.2,
		"max_tokens": 4096,
		"tool_result_chars": 8000,
	},
	KIND_API: {
		"num_ctx": 65536,
		"keep_alive": "-1",
		"think": false,
		"compact_tools": false,
		"temperature": 0.2,
		"max_tokens": 8192,
		"tool_result_chars": 12000,
	},
	KIND_SUB: {
		"num_ctx": 65536,
		"keep_alive": "-1",
		"think": false,
		"compact_tools": false,
		"temperature": 0.2,
		"max_tokens": 8192,
		"tool_result_chars": 12000,
	},
}

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
	"mcp_servers": [],
	"profiles": {},
}

const PROFILE_KEYS := [
	"model", "base_url", "num_ctx", "keep_alive", "think",
	"compact_tools", "temperature", "max_tokens", "tool_result_chars",
]

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


func kind(id: String = "") -> String:
	var pid := id if id != "" else provider_id()
	return str(PROVIDER_KIND.get(pid, KIND_API if pid != "" else ""))


func protocol(id: String = "") -> String:
	var pid := id if id != "" else provider_id()
	if pid == "ollama" or _url_is_ollama():
		return "ollama"
	if pid == "anthropic" or pid == "claude_cli":
		return "anthropic"
	if pid == "gemini_cli":
		return "gemini"
	return "openai"


func capabilities(id: String = "") -> Dictionary:
	var proto := protocol(id)
	var k := kind(id)
	var sub := k == KIND_SUB
	return {
		"kind": k,
		"protocol": proto,
		"base_url": not sub,
		"api_key": k == KIND_API,
		"num_ctx": proto == "ollama",
		"keep_alive": proto == "ollama",
		"think": proto == "ollama" or proto == "anthropic",
		"compact_tools": true,
		"temperature": true,
		"max_tokens": true,
		"warmup": not sub,
		"list_models": not sub,
		"cli": sub,
	}


func context_budget() -> int:
	if protocol() == "ollama":
		return maxi(int(get_value("num_ctx", 65536)), 8192)
	return 128000


func switch_provider(new_id: String) -> void:
	var old := provider_id()
	if old != "" and old != new_id:
		store_profile(old)
	set_value("provider", new_id, false)
	load_profile(new_id)
	apply_kind_defaults(new_id, false)
	apply_model_hints(model(), false)
	save_project()
	changed.emit()


func store_profile(id: String = "") -> void:
	var pid := id if id != "" else provider_id()
	if pid == "":
		return
	var profiles: Dictionary = get_value("profiles", {})
	if typeof(profiles) != TYPE_DICTIONARY:
		profiles = {}
	var row := {}
	for key in PROFILE_KEYS:
		row[key] = get_value(key, KIND_DEFAULTS.get(kind(pid), {}).get(key))
	profiles[pid] = row
	project["profiles"] = profiles


func load_profile(id: String) -> void:
	var profiles: Variant = get_value("profiles", {})
	if typeof(profiles) != TYPE_DICTIONARY or not profiles.has(id):
		return
	var row: Variant = profiles[id]
	if typeof(row) != TYPE_DICTIONARY:
		return
	for key in PROFILE_KEYS:
		if row.has(key):
			project[key] = row[key]


func apply_kind_defaults(id: String, overwrite: bool) -> void:
	var k := kind(id)
	if k == "":
		return
	var defs: Dictionary = KIND_DEFAULTS.get(k, {})
	for key in defs.keys():
		if overwrite or not project.has(key):
			project[key] = defs[key]


func apply_model_hints(model_id: String, overwrite: bool) -> void:
	var hints := model_hints(model_id, kind())
	for key in hints.keys():
		if overwrite or not project.has(key):
			project[key] = hints[key]


func model_hints(model_id: String, k: String = "") -> Dictionary:
	var m := model_id.to_lower()
	var out := {}
	if k == "":
		k = kind()
	if k == KIND_LOCAL:
		if "70b" in m or "72b" in m or "32b" in m or "27b" in m or "30b" in m:
			out["num_ctx"] = 65536
			out["keep_alive"] = "-1"
			out["compact_tools"] = true
			out["max_tokens"] = 4096
		if "qwen" in m or "coder" in m:
			out["compact_tools"] = true
			out["temperature"] = 0.2
		if "8b" in m or "7b" in m or "3b" in m or "4b" in m:
			out["num_ctx"] = mini(int(get_value("num_ctx", 65536)), 32768)
			out["compact_tools"] = true
	else:
		out["compact_tools"] = false
		out["max_tokens"] = 8192
	return out


func _url_is_ollama() -> bool:
	var url := base_url().to_lower()
	return url.find("11434") >= 0 or url.find("ollama") >= 0

@tool
class_name LumenSettings
extends RefCounted

signal changed

## Three runtime classes. Provider is only the endpoint.
## local        = Ollama / LM Studio / loopback — context + keep_alive matter
## api          = paid model HTTP (OpenAI, Anthropic, xAI, custom) — max_tokens + temperature
## subscription = official CLI session already billed by that vendor — no Lumen wallet

const KIND_LOCAL := "local"
const KIND_API := "api"
const KIND_SUB := "subscription"

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
		"num_ctx": 131072,
		"keep_alive": "-1",
		"think": false,
		"compact_tools": true,
		"temperature": 0.2,
		"max_tokens": 8192,
		"tool_result_chars": 8000,
	},
	KIND_API: {
		"num_ctx": 0,
		"keep_alive": "",
		"think": false,
		"compact_tools": false,
		"temperature": 0.2,
		"max_tokens": 32768,
		"tool_result_chars": 16000,
	},
	KIND_SUB: {
		"num_ctx": 0,
		"keep_alive": "",
		"think": false,
		"compact_tools": false,
		"temperature": 0.2,
		"max_tokens": 32768,
		"tool_result_chars": 16000,
	},
}

const DEFAULTS := {
	"provider": "",
	"base_url": "",
	"model": "",
	"temperature": 0.2,
	"max_tokens": 32768,
	"num_ctx": 131072,
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
	"image_kind": "retro",
	"mesh_base_url": "https://api.meshy.ai",
	"mesh_refine": false,
	"docs_url": "https://docs.godotengine.org/en/stable/",
	"mcp_servers": [],
	"profiles": {},
}

## Connection-level keys stored on profiles[pid].
const PROFILE_CONN_KEYS := ["base_url"]

## Per-model binding keys under profiles[pid].models[mid].
const MODEL_BINDING_KEYS := [
	"num_ctx", "keep_alive", "think",
	"compact_tools", "temperature", "max_tokens", "tool_result_chars",
]

## Deprecated flat profile keys (read-fallback one version).
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
	_migrate_stale_limits()
	var pid := str(project.get("provider", ""))
	if pid != "":
		var row := _profile_row(pid)
		if not row.is_empty():
			_migrate_profile_bindings(pid, row)


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


func set_image_api_key(value: String) -> void:
	secrets["image_api_key"] = value
	LumenJson.write_file(LumenPaths.USER_SECRETS, secrets)


func mesh_api_key() -> String:
	return str(secrets.get("mesh_api_key", ""))


func set_mesh_api_key(value: String) -> void:
	secrets["mesh_api_key"] = value
	LumenJson.write_file(LumenPaths.USER_SECRETS, secrets)


func provider_id() -> String:
	return str(get_value("provider", ""))


func base_url() -> String:
	return str(get_value("base_url"))


func model() -> String:
	var pid := provider_id()
	if pid != "":
		var mid := selected_model(pid)
		if mid != "":
			return mid
	return str(get_value("model", ""))


func selected_model(id: String = "") -> String:
	var pid := id if id != "" else provider_id()
	var row := _profile_row(pid)
	var mid := str(row.get("selected_model", ""))
	if mid != "":
		return mid
	# Deprecated flat fallback.
	return str(row.get("model", get_value("model", "")))


func _profiles() -> Dictionary:
	var raw: Variant = project.get("profiles", {})
	if typeof(raw) == TYPE_DICTIONARY:
		return raw as Dictionary
	return {}


func _profile_row(pid: String) -> Dictionary:
	if pid == "":
		return {}
	var profiles := _profiles()
	var row: Variant = profiles.get(pid, {})
	if typeof(row) != TYPE_DICTIONARY:
		return {}
	return row as Dictionary


func _ensure_profile(pid: String) -> Dictionary:
	var profiles := _profiles().duplicate(true)
	var row: Variant = profiles.get(pid, {})
	if typeof(row) != TYPE_DICTIONARY:
		row = {}
	var dict: Dictionary = (row as Dictionary).duplicate(true)
	if not dict.has("models") or typeof(dict["models"]) != TYPE_DICTIONARY:
		dict["models"] = {}
	if not dict.has("catalog") or typeof(dict["catalog"]) != TYPE_ARRAY:
		dict["catalog"] = []
	profiles[pid] = dict
	project["profiles"] = profiles
	return dict


func _defaults_for(pid: String) -> Dictionary:
	var out := {}
	var defs: Dictionary = KIND_DEFAULTS.get(kind(pid), {})
	for key in MODEL_BINDING_KEYS:
		if defs.has(key):
			out[key] = defs[key]
		elif DEFAULTS.has(key):
			out[key] = DEFAULTS[key]
	return out


func _binding_from_project() -> Dictionary:
	var out := {}
	for key in MODEL_BINDING_KEYS:
		out[key] = get_value(key)
	return out


func _apply_binding_to_project(binding: Dictionary) -> void:
	for key in MODEL_BINDING_KEYS:
		if binding.has(key):
			project[key] = binding[key]


func _save_binding(pid: String, mid: String) -> void:
	if pid == "" or mid == "":
		return
	var row := _ensure_profile(pid)
	var models: Dictionary = (row["models"] as Dictionary).duplicate(true)
	models[mid] = _binding_from_project()
	row["models"] = models
	row["selected_model"] = mid
	row["model"] = mid  # deprecated mirror
	var profiles := _profiles().duplicate(true)
	profiles[pid] = row
	project["profiles"] = profiles


func model_catalog(id: String = "") -> PackedStringArray:
	var pid := id if id != "" else provider_id()
	var row := _profile_row(pid)
	var out := PackedStringArray()
	var raw: Variant = row.get("catalog", [])
	if typeof(raw) == TYPE_ARRAY:
		for item in raw:
			var s := str(item).strip_edges()
			if s != "" and out.find(s) < 0:
				out.append(s)
	if out.is_empty():
		return catalog(pid)
	return out


func set_model_catalog(names: PackedStringArray, id: String = "") -> void:
	var pid := id if id != "" else provider_id()
	if pid == "":
		return
	var row := _ensure_profile(pid)
	var arr: Array = []
	for n in names:
		var s := str(n).strip_edges()
		if s != "" and s not in arr:
			arr.append(s)
	row["catalog"] = arr
	var profiles := _profiles().duplicate(true)
	profiles[pid] = row
	project["profiles"] = profiles
	save_project()


## Save active binding, create missing mid with connection defaults + hints once, load UI/project.
func switch_model(pid: String, mid: String) -> void:
	mid = mid.strip_edges()
	if pid == "" or mid == "":
		return
	var row := _ensure_profile(pid)
	var prev := str(row.get("selected_model", ""))
	if prev == "" :
		prev = str(row.get("model", get_value("model", "")))
	# 1) write back active settings into previous binding
	if prev != "" and provider_id() == pid:
		_save_binding(pid, prev)
		row = _ensure_profile(pid)
	var models: Dictionary = (row["models"] as Dictionary).duplicate(true)
	var created := false
	# 2) create binding if missing (hints only on first create)
	if not models.has(mid) or typeof(models[mid]) != TYPE_DICTIONARY:
		var binding := _defaults_for(pid)
		var hints := model_hints(mid, kind(pid))
		for key in hints.keys():
			binding[key] = hints[key]
		models[mid] = binding
		created = true
	row["models"] = models
	row["selected_model"] = mid
	row["model"] = mid
	var profiles := _profiles().duplicate(true)
	profiles[pid] = row
	project["profiles"] = profiles
	project["model"] = mid
	# 3) load active binding into flat project keys (runtime + UI)
	_apply_binding_to_project(models[mid] as Dictionary)
	save_project()
	changed.emit()
	if created and log:
		log.info("Created model binding %s/%s" % [pid, mid])


func plan_mode() -> bool:
	return bool(get_value("plan_mode", false))


func auto_approve_readonly() -> bool:
	return bool(get_value("auto_approve_readonly", true))


func kind(id: String = "") -> String:
	var pid := id if id != "" else provider_id()
	return str(PROVIDER_KIND.get(pid, KIND_API if pid != "" else ""))


func protocol(id: String = "") -> String:
	var pid := id if id != "" else provider_id()
	if pid == "codex_cli":
		return "codex"
	if pid == "claude_cli":
		return "anthropic"
	if pid == "gemini_cli":
		return "gemini"
	if pid == "ollama" or _url_is_ollama():
		return "ollama"
	if pid == "anthropic":
		return "anthropic"
	if pid == "lmstudio":
		return "openai"
	return "openai"


func capabilities(id: String = "") -> Dictionary:
	var proto := protocol(id)
	var k := kind(id)
	var sub := k == KIND_SUB
	# Ollama docs: num_ctx lives in options; omit it and the server uses 2048.
	# LM Studio / llama.cpp: context is a load setting, not a chat field.
	# Anthropic: max_tokens is required; thinking is {type, budget_tokens}.
	# OpenAI chat: temperature + max_tokens / max_completion_tokens. No num_ctx.
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
		"list_models": true,
		"cli": sub,
	}


func context_budget() -> int:
	if protocol() == "ollama":
		return maxi(int(get_value("num_ctx", 131072)), 8192)
	return maxi(int(get_value("max_tokens", 32768)) * 4, 128000)


func switch_provider(new_id: String) -> void:
	var old := provider_id()
	if old != "" and old != new_id:
		store_profile(old)
	set_value("provider", new_id, false)
	load_profile(new_id)
	apply_kind_defaults(new_id, false)
	var mid := selected_model(new_id)
	if mid != "":
		# Binding already loaded via load_profile; keep user values.
		project["model"] = mid
	save_project()
	changed.emit()


func store_profile(id: String = "") -> void:
	var pid := id if id != "" else provider_id()
	if pid == "":
		return
	var row := _ensure_profile(pid)
	for key in PROFILE_CONN_KEYS:
		row[key] = get_value(key)
	var mid := selected_model(pid)
	if mid == "":
		mid = str(get_value("model", "")).strip_edges()
	if mid != "":
		_save_binding(pid, mid)
		row = _ensure_profile(pid)
	else:
		# Keep deprecated flat keys for one version.
		for key in PROFILE_KEYS:
			row[key] = get_value(key)
		var profiles := _profiles().duplicate(true)
		profiles[pid] = row
		project["profiles"] = profiles


func load_profile(id: String) -> void:
	var profiles: Variant = get_value("profiles", {})
	if typeof(profiles) != TYPE_DICTIONARY or not profiles.has(id):
		return
	var row: Variant = profiles[id]
	if typeof(row) != TYPE_DICTIONARY:
		return
	var dict: Dictionary = row as Dictionary
	# Connection fields.
	for key in PROFILE_CONN_KEYS:
		if dict.has(key):
			project[key] = dict[key]
	# Migrate legacy flat profile → models[mid] once.
	_migrate_profile_bindings(id, dict)
	dict = _profile_row(id)
	var mid := str(dict.get("selected_model", ""))
	if mid == "":
		mid = str(dict.get("model", ""))
	if mid != "":
		project["model"] = mid
		var models: Variant = dict.get("models", {})
		if typeof(models) == TYPE_DICTIONARY and models.has(mid) and typeof(models[mid]) == TYPE_DICTIONARY:
			_apply_binding_to_project(models[mid] as Dictionary)
			return
	# Deprecated flat fallback.
	for key in PROFILE_KEYS:
		if dict.has(key):
			project[key] = dict[key]


func _migrate_profile_bindings(pid: String, row: Dictionary) -> void:
	var models_raw: Variant = row.get("models", {})
	var has_models := typeof(models_raw) == TYPE_DICTIONARY and not (models_raw as Dictionary).is_empty()
	if has_models:
		return
	var mid := str(row.get("selected_model", row.get("model", ""))).strip_edges()
	if mid == "":
		return
	var binding := {}
	for key in MODEL_BINDING_KEYS:
		if row.has(key):
			binding[key] = row[key]
		elif project.has(key) and provider_id() == pid:
			binding[key] = project[key]
		else:
			var defs := _defaults_for(pid)
			if defs.has(key):
				binding[key] = defs[key]
	var fresh := _ensure_profile(pid)
	var models: Dictionary = {}
	models[mid] = binding
	fresh["models"] = models
	fresh["selected_model"] = mid
	fresh["model"] = mid
	for key in PROFILE_CONN_KEYS:
		if row.has(key):
			fresh[key] = row[key]
	var profiles := _profiles().duplicate(true)
	profiles[pid] = fresh
	project["profiles"] = profiles


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
		out["keep_alive"] = "-1"
		out["compact_tools"] = true
		out["max_tokens"] = 8192
		out["num_ctx"] = 131072
		if "qwen3.8" in m or "qwen3.6" in m or "qwen3.5" in m or "256k" in m:
			out["num_ctx"] = 262144
			out["max_tokens"] = 16384
		elif "70b" in m or "72b" in m or "32b" in m or "27b" in m or "30b" in m:
			out["num_ctx"] = 131072
			out["max_tokens"] = 8192
		elif "8b" in m or "7b" in m or "4b" in m or "3b" in m:
			out["num_ctx"] = 65536
			out["max_tokens"] = 4096
	else:
		out["compact_tools"] = false
		out["max_tokens"] = 32768
		if "codex" in m or "gpt-5" in m or "gpt-6" in m or "gpt-4.1" in m:
			out["max_tokens"] = 32768
		if "claude" in m and ("sonnet-4-5" in m or "haiku" in m):
			out["max_tokens"] = 32768
		if "claude" in m and ("sonnet-5" in m or "opus" in m or "fable" in m or "mythos" in m):
			out["max_tokens"] = 65536
		if "gemini" in m:
			out["max_tokens"] = 32768
		if "grok" in m:
			out["max_tokens"] = 32768
	return out


func _migrate_stale_limits() -> void:
	var k := kind()
	if k == KIND_API or k == KIND_SUB:
		var mx := int(get_value("max_tokens", 0))
		if mx == 4096 or mx == 8192:
			project["max_tokens"] = 32768
		project["compact_tools"] = false
	elif k == KIND_LOCAL:
		if int(get_value("num_ctx", 0)) == 65536:
			project["num_ctx"] = 131072
		if int(get_value("max_tokens", 0)) == 4096:
			project["max_tokens"] = 8192


func catalog(id: String = "") -> PackedStringArray:
	var pid := id if id != "" else provider_id()
	match pid:
		"codex_cli", "openai":
			return PackedStringArray(["gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.3-codex", "gpt-4.1"])
		"claude_cli", "anthropic":
			return PackedStringArray(["claude-sonnet-5", "claude-opus-5", "claude-sonnet-4-5", "claude-haiku-4-5"])
		"gemini_cli":
			return PackedStringArray(["gemini-2.5-pro", "gemini-2.5-flash", "gemini-3.1-pro"])
		"grok":
			return PackedStringArray(["grok-4.5", "grok-4"])
		_:
			return PackedStringArray()


func _url_is_ollama() -> bool:
	var url := base_url().to_lower()
	return url.find("11434") >= 0 or url.find("ollama") >= 0

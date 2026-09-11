@tool
class_name LumenModelDiscovery
extends RefCounted

## Routes List Models by provider_id. Live discovery first; seed catalog() is fallback only.

signal models_listed(names: PackedStringArray)
signal failed(message: String)

var settings: LumenSettings
var cli: LumenCliAuth
var openai: LumenOpenAICompatible
var anthropic: LumenAnthropic
var gemini: LumenGemini
var log: LumenLogger
var _busy := false
var _provider := ""


func setup(
	p_settings: LumenSettings,
	p_cli: LumenCliAuth,
	p_openai: LumenOpenAICompatible,
	p_anthropic: LumenAnthropic,
	p_gemini: LumenGemini,
	p_log: LumenLogger
) -> void:
	settings = p_settings
	cli = p_cli
	openai = p_openai
	anthropic = p_anthropic
	gemini = p_gemini
	log = p_log
	if openai:
		if not openai.models_listed.is_connected(_on_provider_listed):
			openai.models_listed.connect(_on_provider_listed)
		if openai.has_signal("models_failed") and not openai.models_failed.is_connected(_on_provider_failed):
			openai.models_failed.connect(_on_provider_failed)
	if anthropic:
		if not anthropic.models_listed.is_connected(_on_provider_listed):
			anthropic.models_listed.connect(_on_provider_listed)
		if anthropic.has_signal("models_failed") and not anthropic.models_failed.is_connected(_on_provider_failed):
			anthropic.models_failed.connect(_on_provider_failed)
	if gemini:
		if not gemini.models_listed.is_connected(_on_provider_listed):
			gemini.models_listed.connect(_on_provider_listed)
		if gemini.has_signal("models_failed") and not gemini.models_failed.is_connected(_on_provider_failed):
			gemini.models_failed.connect(_on_provider_failed)


func list_models(provider_id: String = "") -> void:
	var pid := provider_id if provider_id != "" else (settings.provider_id() if settings else "")
	if pid == "":
		failed.emit("Choose a provider first.")
		return
	if _busy:
		failed.emit("Model discovery is already running.")
		return
	_busy = true
	_provider = pid
	match pid:
		"openai", "grok", "lmstudio", "ollama", "custom":
			_list_openai_compatible()
		"anthropic":
			_list_anthropic(false)
		"claude_cli":
			_list_claude_cli()
		"codex_cli":
			_list_codex_cli()
		"gemini_cli":
			_list_gemini_cli()
		_:
			_busy = false
			failed.emit("Unknown provider for model discovery: %s" % pid)


func fallback_catalog(provider_id: String = "") -> PackedStringArray:
	## seed catalog() ∪ saved catalog — used when live discovery fails.
	var pid := provider_id if provider_id != "" else _provider
	if pid == "" and settings:
		pid = settings.provider_id()
	var out := PackedStringArray()
	var seen := {}
	if settings == null:
		return out
	for n in settings.catalog(pid):
		var s := str(n).strip_edges()
		if s != "" and not seen.has(s):
			seen[s] = true
			out.append(s)
	for n in settings.model_catalog(pid):
		var s2 := str(n).strip_edges()
		if s2 != "" and not seen.has(s2):
			seen[s2] = true
			out.append(s2)
	return out


func _list_openai_compatible() -> void:
	var url := settings.base_url().strip_edges() if settings else ""
	if url == "":
		_busy = false
		failed.emit("Set a Base URL first.")
		return
	openai.list_models(url, settings.api_key() if settings else "")


func _list_anthropic(use_oauth: bool, token: String = "") -> void:
	var key := token
	if key == "":
		key = settings.api_key() if settings else ""
	if key == "":
		_busy = false
		failed.emit("Anthropic credential is empty.")
		return
	anthropic.list_models(key, use_oauth)


func _list_claude_cli() -> void:
	if cli == null:
		_busy = false
		failed.emit("CLI auth helper not bound.")
		return
	var creds := cli.load_claude_token()
	if not bool(creds.get("ok", false)):
		_busy = false
		failed.emit("No Claude CLI session. Run Login, then Scan.")
		return
	_list_anthropic(true, str(creds.get("access_token", "")))


func _list_gemini_cli() -> void:
	if cli == null:
		_busy = false
		failed.emit("CLI auth helper not bound.")
		return
	var creds := cli.load_gemini_token()
	if not bool(creds.get("ok", false)):
		_busy = false
		failed.emit("No Gemini CLI session and no GEMINI_API_KEY.")
		return
	gemini.list_models(str(creds.get("access_token", "")), str(creds.get("api_key", "")))


func _list_codex_cli() -> void:
	if cli == null:
		_busy = false
		failed.emit("CLI auth helper not bound.")
		return
	var result := cli.list_codex_models()
	_busy = false
	if not bool(result.get("ok", false)):
		failed.emit(str(result.get("error", "codex debug models failed.")))
		return
	var names: PackedStringArray = result.get("names", PackedStringArray())
	if names.is_empty():
		failed.emit("codex debug models returned no slugs.")
		return
	models_listed.emit(names)


func _on_provider_listed(names: PackedStringArray) -> void:
	if not _busy:
		return
	_busy = false
	if names.is_empty():
		failed.emit("Runtime reported no models.")
		return
	models_listed.emit(names)


func _on_provider_failed(message: String) -> void:
	if not _busy:
		return
	_busy = false
	failed.emit(message)

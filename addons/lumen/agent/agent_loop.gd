@tool
class_name LumenAgentLoop
extends RefCounted

signal status(text: String)
signal assistant_delta(text: String)
signal tool_proposed(call_id: String, name: String, args: Dictionary, readonly: bool)
signal turn_done(message: String)
signal turn_failed(message: String)
signal plan_ready(plan: Dictionary)

const MAX_STEPS := 16
const WRITE_TOOLS := [
	"write_file", "edit_file", "delete_file", "move_path",
	"create_node", "set_node_property", "delete_node", "reparent_node",
	"set_project_setting", "set_tile_cell", "fill_tiles", "erase_tiles",
	"generate_image", "attach_script", "open_scene", "save_scene",
]

var plugin: EditorPlugin
var settings: LumenSettings
var registry: LumenToolRegistry
var snapshots: LumenSnapshotStore
var plan: LumenPlanMode
var openai: LumenOpenAICompatible
var anthropic: LumenAnthropic
var codex: LumenCodexSubscription
var gemini: LumenGemini
var cli: LumenCliAuth
var log: LumenLogger
var context: LumenContextBuilder
var skills: LumenSkillLoader

var messages: Array = []
var running := false
var _turn_id := ""
var _pending_calls: Array = []
var _approvals: Dictionary = {}
var _always: Dictionary = {}
var _continued_length := false


func setup(
	p_plugin: EditorPlugin,
	p_settings: LumenSettings,
	p_registry: LumenToolRegistry,
	p_snapshots: LumenSnapshotStore,
	p_plan: LumenPlanMode,
	p_openai: LumenOpenAICompatible,
	p_anthropic: LumenAnthropic,
	p_log: LumenLogger,
	p_context: LumenContextBuilder,
	p_skills: LumenSkillLoader
) -> void:
	plugin = p_plugin
	settings = p_settings
	registry = p_registry
	snapshots = p_snapshots
	plan = p_plan
	openai = p_openai
	anthropic = p_anthropic
	log = p_log
	context = p_context
	skills = p_skills
	if not openai.finished.is_connected(_on_openai):
		openai.finished.connect(_on_openai)
		openai.failed.connect(_fail)
	if not anthropic.finished.is_connected(_on_openai):
		anthropic.finished.connect(_on_openai)
		anthropic.failed.connect(_fail)
	_always.clear()
	for name in settings.get_value("always_tools", []):
		_always[str(name)] = true


func bind_cli(p_cli: LumenCliAuth, p_codex: LumenCodexSubscription, p_gemini: LumenGemini = null) -> void:
	cli = p_cli
	codex = p_codex
	gemini = p_gemini
	if codex and not codex.finished.is_connected(_on_openai):
		codex.finished.connect(_on_openai)
		codex.failed.connect(_fail)
	if gemini and not gemini.finished.is_connected(_on_openai):
		gemini.finished.connect(_on_openai)
		gemini.failed.connect(_fail)
	load_persisted()


func reset_chat() -> void:
	messages.clear()
	plan.clear()
	_pending_calls.clear()
	_approvals.clear()
	_save_persisted()


func submit_user(text: String, attachments: Array = []) -> void:
	if running:
		_fail("Agent is already running.")
		return
	var payload := text
	if not attachments.is_empty():
		payload += "\n\nAttached paths:\n"
		for path in attachments:
			payload += "- %s\n" % path
	if messages.is_empty():
		messages.append({
			"role": "system",
			"content": context.system_preamble(settings, skills),
		})
	messages.append({"role": "user", "content": payload})
	_turn_id = snapshots.begin_turn(text.substr(0, 80))
	_continued_length = false
	_save_persisted()
	running = true
	_step()


func approve_tool(call_id: String) -> void:
	_approvals[call_id] = true
	_flush_approvals()


func reject_tool(call_id: String) -> void:
	_approvals[call_id] = false
	_flush_approvals()


func always_tool(name: String) -> void:
	_always[name] = true
	var stored: Array = settings.get_value("always_tools", [])
	if name not in stored:
		stored.append(name)
		settings.set_value("always_tools", stored)


func approve_plan() -> void:
	plan.approve()
	messages.append({"role": "user", "content": "Plan approved. Execute it with tools now."})
	running = true
	_step()


func reject_plan() -> void:
	plan.reject()
	messages.append({"role": "user", "content": "Plan rejected. Wait for a new instruction."})
	turn_done.emit("Plan rejected.")


func _step() -> void:
	_compact()
	status.emit("Talking to %s…" % settings.provider_id())
	var tools := registry.openai_tools()
	var provider := settings.provider_id()
	if provider == "codex_cli":
		if codex == null:
			_fail("Codex subscription provider is not attached.")
			return
		codex.chat(
			settings.model(),
			messages,
			tools,
			int(settings.get_value("max_tokens", 4096)),
			float(settings.get_value("temperature", 0.2))
		)
		return
	if provider == "anthropic" or provider == "claude_cli":
		var system := ""
		var rest: Array = []
		for msg in messages:
			if str(msg.get("role", "")) == "system":
				system += str(msg.get("content", "")) + "\n"
			else:
				rest.append(msg)
		var key := settings.api_key()
		var oauth := provider == "claude_cli"
		if oauth and cli:
			var creds := cli.load_claude_token()
			if bool(creds.get("ok", false)):
				key = str(creds.get("access_token", ""))
			else:
				_fail("No Claude Code session. Click Login Claude or run `claude /login`.")
				return
		anthropic.chat(
			key,
			settings.model(),
			system,
			rest,
			tools,
			int(settings.get_value("max_tokens", 4096)),
			float(settings.get_value("temperature", 0.2)),
			oauth
		)
		return
	if provider == "gemini_cli":
		if gemini == null or cli == null:
			_fail("Gemini provider is not attached.")
			return
		var creds := cli.load_gemini_token()
		if not bool(creds.get("ok", false)):
			_fail("No Gemini session. Click Login Gemini or set GEMINI_API_KEY.")
			return
		gemini.chat(
			str(creds.get("access_token", "")),
			str(creds.get("api_key", "")),
			settings.model() if settings.model() != "" else "gemini-2.5-flash",
			messages,
			tools,
			int(settings.get_value("max_tokens", 4096)),
			float(settings.get_value("temperature", 0.2))
		)
		return
	var payload := {
		"model": settings.model(),
		"temperature": float(settings.get_value("temperature", 0.2)),
		"max_tokens": int(settings.get_value("max_tokens", 8192)),
		"messages": messages,
		"tools": tools,
		"num_ctx": int(settings.get_value("num_ctx", 65536)),
		"keep_alive": str(settings.get_value("keep_alive", "30m")),
	}
	openai.chat(settings.base_url(), settings.api_key(), payload)


func load_persisted() -> void:
	var path := LumenPaths.CHAT_DIR.path_join("current.json")
	var stored: Variant = LumenJson.read_file(path, [])
	if typeof(stored) == TYPE_ARRAY and not stored.is_empty():
		messages = stored


func _save_persisted() -> void:
	LumenPaths.ensure_dirs()
	LumenJson.write_file(LumenPaths.CHAT_DIR.path_join("current.json"), messages)


func _on_openai(result: Dictionary) -> void:
	var choices: Array = result.get("choices", [])
	if choices.is_empty():
		_fail("Provider returned no choices.")
		return
	var message: Dictionary = choices[0].get("message", {})
	var finish := str(choices[0].get("finish_reason", ""))
	var text := str(message.get("content", ""))
	var tool_calls: Array = message.get("tool_calls", [])
	if tool_calls.is_empty():
		tool_calls = LumenToolParse.from_content(text)
		if not tool_calls.is_empty():
			message["tool_calls"] = tool_calls
			text = ""
			message["content"] = ""
	messages.append(message)
	_save_persisted()
	if text != "":
		assistant_delta.emit(text)
		if settings.plan_mode() and not plan.has_approval() and _looks_like_plan(text) and tool_calls.is_empty():
			running = false
			var parsed := _extract_plan(text)
			plan.submit(parsed)
			plan_ready.emit(parsed)
			return
	if tool_calls.is_empty():
		if finish == "length" and not _continued_length:
			_continued_length = true
			messages.append({
				"role": "user",
				"content": "Your last reply hit max_tokens. Continue from there, or call a tool with a smaller payload.",
			})
			_step()
			return
		running = false
		turn_done.emit(text if text != "" else "(done)")
		return
	if _count_assistant_turns() > MAX_STEPS:
		running = false
		_fail("Stopped after %d tool steps. Narrow the request or start /new." % MAX_STEPS)
		return
	_pending_calls = tool_calls.duplicate(true)
	_approvals.clear()
	for call in _pending_calls:
		var fn: Dictionary = call.get("function", {})
		var name := str(fn.get("name", ""))
		var args := _parse_args(str(fn.get("arguments", "{}")))
		var readonly := registry.is_readonly(name)
		if settings.plan_mode() and not plan.has_approval() and name in WRITE_TOOLS:
			messages.append({
				"role": "tool",
				"tool_call_id": str(call.get("id", "")),
				"content": "Blocked: plan mode is on and the plan is not approved.",
			})
			continue
		if readonly and settings.auto_approve_readonly():
			_approvals[str(call.get("id", ""))] = true
		elif _always.has(name):
			_approvals[str(call.get("id", ""))] = true
		else:
			tool_proposed.emit(str(call.get("id", "")), name, args, readonly)
	_flush_approvals()


func _flush_approvals() -> void:
	if _pending_calls.is_empty():
		return
	for call in _pending_calls:
		var id := str(call.get("id", ""))
		if not _approvals.has(id):
			return
	status.emit("Running tools…")
	for call in _pending_calls:
		var id := str(call.get("id", ""))
		var fn: Dictionary = call.get("function", {})
		var name := str(fn.get("name", ""))
		var args := _parse_args(str(fn.get("arguments", "{}")))
		var allowed := bool(_approvals.get(id, false))
		var result: Dictionary
		if args.get("_parse_error", false):
			result = {"ok": false, "error": "Tool arguments were truncated or invalid JSON. Retry with a smaller payload."}
		elif not allowed:
			result = {"ok": false, "error": "User rejected this tool call."}
		else:
			if name in WRITE_TOOLS:
				if args.has("path"):
					snapshots.capture(_turn_id, str(args.get("path", "")))
				if args.has("from"):
					snapshots.capture(_turn_id, str(args.get("from", "")))
				_capture_edited_scene()
			result = registry.run(name, args)
		var cap := int(settings.get_value("tool_result_chars", 12000))
		messages.append({
			"role": "tool",
			"tool_call_id": id,
			"content": LumenJson.clamp_text(JSON.stringify(result), cap),
		})
	_pending_calls.clear()
	_step()


func _parse_args(raw: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(raw if raw != "" else "{}")
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {"_parse_error": true}


func _looks_like_plan(text: String) -> bool:
	var lower := text.to_lower()
	return lower.find("plan") >= 0 and (lower.find("1.") >= 0 or lower.find("- ") >= 0)


func _extract_plan(text: String) -> Dictionary:
	return {"markdown": text, "steps": _steps_from_markdown(text)}


func _steps_from_markdown(text: String) -> Array:
	var steps: Array = []
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with("- ") or trimmed.match("^[0-9]+\\.*"):
			steps.append(trimmed)
	return steps


func _count_assistant_turns() -> int:
	var n := 0
	for msg in messages:
		if str(msg.get("role", "")) == "assistant":
			n += 1
	return n


func _compact() -> void:
	var tool_cap := int(settings.get_value("tool_result_chars", 12000))
	var keep := 20
	var budget := int(settings.get_value("num_ctx", 65536)) * 3
	var system: Array = []
	var tail: Array = []
	for msg in messages:
		var copy: Dictionary = (msg as Dictionary).duplicate(true)
		if str(copy.get("role", "")) == "tool":
			copy["content"] = LumenJson.clamp_text(str(copy.get("content", "")), tool_cap)
		if str(copy.get("role", "")) == "system":
			system.append(copy)
		else:
			tail.append(copy)
	if tail.size() > keep:
		messages = system + [{"role": "user", "content": "(Earlier turns were trimmed to stay inside the local context window.)"}] + tail.slice(tail.size() - keep)
	else:
		messages = system + tail
	var total := 0
	for msg in messages:
		total += str(msg.get("content", "")).length()
	if total <= budget:
		return
	var tighter := mini(12, tail.size())
	if tail.size() > tighter:
		tail = tail.slice(tail.size() - tighter)
		messages = system + [{"role": "user", "content": "(Context compacted for the local model.)"}] + tail



func _capture_edited_scene() -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return
	var path := root.scene_file_path
	if path == "":
		return
	EditorInterface.save_scene()
	snapshots.capture(_turn_id, path)


func _fail(message: String) -> void:
	running = false
	log.error(message)
	turn_failed.emit(message)

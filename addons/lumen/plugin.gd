@tool
extends EditorPlugin

const DockScene := preload("res://addons/lumen/ui/dock.tscn")

var dock: Control
var editor_dock: Node
var log: LumenLogger
var settings: LumenSettings
var snapshots: LumenSnapshotStore
var skills: LumenSkillLoader
var context: LumenContextBuilder
var registry: LumenToolRegistry
var builtins: LumenBuiltinTools
var plan: LumenPlanMode
var openai: LumenOpenAICompatible
var anthropic: LumenAnthropic
var cli_auth: LumenCliAuth
var codex: LumenCodexSubscription
var gemini: LumenGemini
var loop: LumenAgentLoop
var mcp: LumenMcpServer


func _enter_tree() -> void:
	log = LumenLogger.new()
	settings = LumenSettings.new(log)
	snapshots = LumenSnapshotStore.new(log)
	skills = LumenSkillLoader.new(log)
	context = LumenContextBuilder.new(self)
	registry = LumenToolRegistry.new()
	builtins = LumenBuiltinTools.new(self, settings, skills, log)
	builtins.register(registry)
	var more := LumenMoreTools.new()
	more.attach(settings)
	more.register(registry)
	plan = LumenPlanMode.new()
	openai = LumenOpenAICompatible.new()
	anthropic = LumenAnthropic.new()
	cli_auth = LumenCliAuth.new(log)
	codex = LumenCodexSubscription.new()
	gemini = LumenGemini.new()
	loop = LumenAgentLoop.new()
	dock = DockScene.instantiate()
	editor_dock = LumenEditor.attach_dock(self, dock)
	openai.attach(dock, log)
	anthropic.attach(dock, log)
	codex.attach(dock, log, cli_auth)
	gemini.attach(dock, log)
	loop.setup(self, settings, registry, snapshots, plan, openai, anthropic, log, context, skills)
	loop.bind_cli(cli_auth, codex, gemini)
	dock.bind_settings(settings)
	dock.bind_cli(cli_auth)
	dock.restore_messages(loop.messages)
	dock.cli_scan.connect(_on_cli_scan)
	dock.cli_login.connect(_on_cli_login)
	dock.cli_use.connect(_on_cli_use)
	dock.send_pressed.connect(_on_send)
	dock.new_chat.connect(_on_new)
	dock.undo_pressed.connect(_on_undo)
	dock.approve_plan.connect(_on_approve_plan)
	dock.reject_plan.connect(_on_reject_plan)
	dock.settings_changed.connect(_on_settings)
	loop.status.connect(dock.set_status)
	loop.assistant_delta.connect(dock.append_assistant)
	loop.turn_done.connect(func(_text):
		dock.set_busy(false)
		dock.set_status("Idle")
		dock.clear_tools()
	)
	loop.turn_failed.connect(func(text):
		dock.set_busy(false)
		dock.append_system(text)
		dock.set_status("Error")
	)
	loop.tool_proposed.connect(_on_tool_proposed)
	loop.plan_ready.connect(func(p):
		dock.set_busy(false)
		dock.show_plan(str(p.get("markdown", "")))
		dock.set_status("Waiting for plan approval")
	)
	mcp = LumenMcpServer.new()
	dock.add_child(mcp)
	mcp.configure(registry, log, int(settings.get_value("mcp_port", 8765)))
	if bool(settings.get_value("mcp_enabled", false)):
		mcp.start()
	_ensure_playtest_autoload()
	dock.refresh_cli_status()
	log.info("Lumen entered the editor.")


func _exit_tree() -> void:
	if mcp:
		mcp.stop()
	if dock:
		LumenEditor.detach_dock(self, editor_dock, dock)
		dock = null
		editor_dock = null


func _on_send(text: String, mentions: PackedStringArray) -> void:
	if text.begins_with("/"):
		_slash(text)
		return
	if loop.running:
		dock.set_status("Already running.")
		return
	dock.set_busy(true)
	var attachments: Array = []
	for mention in mentions:
		var path := mention if mention.begins_with("res://") else "res://" + mention
		attachments.append(path)
		if FileAccess.file_exists(path):
			attachments.append("(contents of %s)\n%s" % [path, LumenJson.clamp_text(LumenJson.read_text(path), 8000)])
	loop.submit_user(text, attachments)


func _slash(text: String) -> void:
	var cmd := text.substr(1).strip_edges().split(" ")[0].to_lower()
	match cmd:
		"new":
			_on_new()
		"plan":
			settings.set_value("plan_mode", true)
			dock.plan_check.set_pressed_no_signal(true)
			dock.append_system("Plan mode on.")
		"default":
			settings.set_value("plan_mode", false)
			dock.plan_check.set_pressed_no_signal(false)
			dock.append_system("Plan mode off.")
		"model":
			var parts := text.split(" ", false, 1)
			if parts.size() > 1:
				settings.set_value("model", parts[1].strip_edges())
				dock.model_edit.text = settings.model()
				dock.append_system("Model set to %s" % settings.model())
			else:
				dock.append_system("Current model: %s" % settings.model())
		"undo":
			_on_undo()
		_:
			dock.append_system("Unknown command. /new /plan /default /model <id> /undo")


func _on_new() -> void:
	loop.reset_chat()
	dock.reset_transcript()
	dock.hide_plan()
	dock.clear_tools()
	dock.set_busy(false)
	dock.set_status("New chat")


func _on_undo() -> void:
	var result := snapshots.restore_last()
	if bool(result.get("ok", false)):
		EditorInterface.get_resource_filesystem().scan()
		var root := EditorInterface.get_edited_scene_root()
		if root and root.scene_file_path != "":
			EditorInterface.reload_scene_from_path(root.scene_file_path)
		dock.append_system("Restored %s" % str(result.get("files", [])))
	else:
		dock.append_system(str(result.get("error", "Undo failed.")))


func _on_approve_plan() -> void:
	dock.hide_plan()
	dock.set_busy(true)
	loop.approve_plan()


func _on_reject_plan() -> void:
	dock.hide_plan()
	dock.set_busy(false)
	loop.reject_plan()


func _on_settings() -> void:
	if mcp == null:
		return
	mcp.stop()
	mcp.port = int(settings.get_value("mcp_port", 8765))
	if bool(settings.get_value("mcp_enabled", false)):
		mcp.start()
		dock.set_status("MCP on 127.0.0.1:%d" % mcp.port)
	else:
		if dock.status_label.text.begins_with("MCP"):
			dock.set_status("Ready")


func _on_cli_scan() -> void:
	dock.refresh_cli_status()
	dock.append_system(cli_auth.status_line())


func _on_cli_login(kind: String) -> void:
	var result := cli_auth.start_login(kind)
	if bool(result.get("ok", false)):
		dock.append_system(str(result.get("message", "Login started.")))
	else:
		dock.append_system(str(result.get("error", "Login failed.")))


func _on_cli_use(kind: String) -> void:
	match kind:
		"codex":
			settings.set_value("provider", "codex_cli")
			if settings.model() == "":
				settings.set_value("model", "gpt-5.3-codex")
		"claude":
			settings.set_value("provider", "claude_cli")
			if settings.model() == "":
				settings.set_value("model", "claude-sonnet-4-5")
		"gemini":
			settings.set_value("provider", "gemini_cli")
			if settings.model() == "":
				settings.set_value("model", "gemini-2.5-flash")
		_:
			dock.append_system("Unknown CLI.")
			return
	dock.bind_settings(settings)
	dock.refresh_cli_status()
	dock.append_system("Using %s via the official CLI session on this machine." % kind)
	dock.set_status("Provider: %s" % kind)


func _ensure_playtest_autoload() -> void:
	if ProjectSettings.has_setting("autoload/LumenPlaytestIO"):
		return
	add_autoload_singleton("LumenPlaytestIO", "res://addons/lumen/playtest/harness.gd")
	log.info("Registered Autoload LumenPlaytestIO for playtest replay.")


func _on_tool_proposed(call_id: String, name: String, args: Dictionary, readonly: bool) -> void:
	dock.append_tool(name, JSON.stringify(args).substr(0, 120))
	dock.set_busy(false)
	dock.add_tool_prompt(
		call_id,
		name,
		args,
		readonly,
		func(id):
			dock.set_busy(true)
			loop.approve_tool(id),
		func(id): loop.reject_tool(id),
		func(tool_name): loop.always_tool(tool_name)
	)

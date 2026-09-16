@tool
extends EditorPlugin

var _dock_scene: PackedScene

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
var _debugger: EditorDebuggerPlugin


func _enter_tree() -> void:
	_dock_scene = load("res://addons/lumen/ui/dock.tscn") as PackedScene
	if _dock_scene == null:
		push_error("Lumen: ui/dock.tscn failed to load. Check Output for parse errors in dock.gd / dock.tscn.")
		return
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
	var extras := LumenEditorExtras.new()
	extras.attach(settings, self)
	extras.register(registry)
	var query := LumenSceneQuery.new()
	query.register(registry)
	var depth := LumenDepthTools.new()
	depth.register(registry)
	var assets := LumenAssetGen.new()
	assets.attach(settings)
	assets.register(registry)
	var polish := LumenPolishTools.new()
	polish.attach(settings)
	polish.register(registry)
	var observe := LumenObserve.new()
	observe.register(registry)
	registry.mark_extras()
	registry.register_meta()
	plan = LumenPlanMode.new()
	openai = LumenOpenAICompatible.new()
	anthropic = LumenAnthropic.new()
	cli_auth = LumenCliAuth.new(log)
	codex = LumenCodexSubscription.new()
	gemini = LumenGemini.new()
	loop = LumenAgentLoop.new()
	dock = _dock_scene.instantiate()
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
	dock.test_pressed.connect(_on_test_connection)
	dock.stop_pressed.connect(_on_stop)
	dock.models_pressed.connect(_on_list_models)
	if not openai.models_listed.is_connected(_on_models_listed):
		openai.models_listed.connect(_on_models_listed)
	loop.status.connect(dock.set_status)
	loop.assistant_delta.connect(dock.append_assistant)
	if loop.has_signal("stream_delta"):
		loop.stream_delta.connect(dock.append_stream)
	if loop.has_signal("think_delta"):
		loop.think_delta.connect(dock.show_think)
	if dock.has_signal("chat_open"):
		dock.chat_open.connect(_on_chat_open)
	if dock.has_signal("chat_delete"):
		dock.chat_delete.connect(_on_chat_delete)
	_debugger = LumenDebuggerPlugin.new()
	add_debugger_plugin(_debugger)
	dock.refresh_chats()
	dock.refresh_todos()
	loop.turn_done.connect(func(_text):
		dock.set_busy(false)
		dock.set_status("Idle")
		dock.clear_tools()
		dock.end_stream()
		dock.refresh_todos()
		if dock.has_method("clear_think"):
			pass
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
	_connect_editor()
	_push_editor_context()
	LumenAgentsMd.ensure_project_file()
	log.info("Lumen entered the editor.")

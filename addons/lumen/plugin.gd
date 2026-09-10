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
var _debugger: EditorDebuggerPlugin


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
	registry.mark_extras()
	registry.register_meta()
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
	dock.test_pressed.connect(_on_test_connection)
	dock.stop_pressed.connect(_on_stop)
	dock.models_pressed.connect(_on_list_models)
	if not openai.models_listed.is_connected(_on_models_listed):
		openai.models_listed.connect(_on_models_listed)
	loop.status.connect(dock.set_status)
	loop.assistant_delta.connect(dock.append_assistant)
	if loop.has_signal("stream_delta"):
		loop.stream_delta.connect(dock.append_stream)
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
	log.info("Lumen entered the editor.")


func _exit_tree() -> void:
	_disconnect_editor()
	if _debugger:
		remove_debugger_plugin(_debugger)
		_debugger = null
	if mcp:
		mcp.stop()
	if dock:
		LumenEditor.detach_dock(self, editor_dock, dock)
		dock = null
		editor_dock = null


func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_L or not event.ctrl_pressed or not event.shift_pressed:
		return
	LumenEditor.focus_dock(editor_dock)
	if dock:
		dock.focus_composer()
	get_viewport().set_input_as_handled()


func _connect_editor() -> void:
	if not scene_changed.is_connected(_on_scene_changed):
		scene_changed.connect(_on_scene_changed)
	var selection := EditorInterface.get_selection()
	if selection and not selection.selection_changed.is_connected(_on_editor_selection):
		selection.selection_changed.connect(_on_editor_selection)


func _disconnect_editor() -> void:
	if scene_changed.is_connected(_on_scene_changed):
		scene_changed.disconnect(_on_scene_changed)
	var selection := EditorInterface.get_selection()
	if selection and selection.selection_changed.is_connected(_on_editor_selection):
		selection.selection_changed.disconnect(_on_editor_selection)


func _on_scene_changed(_scene: Node) -> void:
	_push_editor_context()


func _on_editor_selection() -> void:
	_push_editor_context()


func _push_editor_context() -> void:
	if dock == null:
		return
	var root := EditorInterface.get_edited_scene_root()
	var scene_path := root.scene_file_path if root else ""
	var paths := PackedStringArray()
	var selection := EditorInterface.get_selection()
	if selection:
		for node in selection.get_selected_nodes():
			if node == null:
				continue
			if root:
				paths.append(str(root.get_path_to(node)))
			else:
				paths.append(str(node.name))
	dock.set_editor_context(scene_path, paths)


func _on_send(text: String, mentions: PackedStringArray) -> void:
	if settings.provider_id() == "":
		dock.append_system("Choose a provider in Connection first.")
		return
	if text.begins_with("/"):
		_slash(text)
		return
	if loop.running:
		dock.set_status("Queued")
	else:
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
				var mid := parts[1].strip_edges()
				var pid := settings.provider_id()
				if pid == "":
					dock.append_system("Choose a provider first.")
				else:
					dock.commit_settings()
					settings.switch_model(pid, mid)
					dock.bind_settings(settings)
					dock.append_system("Model set to %s" % settings.model())
			else:
				dock.append_system("Current model: %s" % settings.model())
		"undo":
			_on_undo()
		"stop":
			_on_stop()
		"docs":
			var q := text.substr(5).strip_edges()
			if q == "":
				dock.append_system("Usage: /docs CharacterBody2D")
			else:
				var extras := LumenEditorExtras.new()
				dock.append_system(JSON.stringify(extras.search_godot_docs({"topic": q})))
		"play":
			EditorInterface.play_current_scene()
			dock.append_system("Playing current scene.")
		_:
			if not _try_custom_slash(cmd, text):
				dock.append_system("Unknown command. /new /plan /default /model /undo /stop /docs /play")


func _try_custom_slash(cmd: String, text: String) -> bool:
	for path in ["res://lumen_commands.json", "user://lumen/commands.json"]:
		var data: Variant = LumenJson.read_file(path, {})
		if typeof(data) != TYPE_DICTIONARY or not data.has(cmd):
			continue
		var prompt := str(data[cmd])
		var rest := text.substr(cmd.length() + 1).strip_edges()
		if rest != "":
			prompt += "\n\n" + rest
		dock.append_system("Custom /%s" % cmd)
		loop.submit_user(prompt, [])
		dock.set_busy(true)
		return true
	return false


func _on_stop() -> void:
	loop.stop()
	dock.set_busy(false)
	dock.set_status("Stopped")
	dock.append_system("Stopped.")


func _on_list_models() -> void:
	var pid := settings.provider_id()
	if pid.ends_with("_cli"):
		var names := settings.catalog(pid)
		if names.is_empty():
			names = settings.model_catalog(pid)
		dock.set_status("Idle")
		dock.apply_models(names)
		return
	var url := settings.base_url().strip_edges()
	if url == "":
		dock.append_system("Set a Base URL first.")
		return
	dock.set_status("Listing models…")
	openai.list_models(url, settings.api_key())


func _on_models_listed(names: PackedStringArray) -> void:
	dock.set_status("Idle")
	dock.apply_models(names)


func _chat_meta() -> Dictionary:
	return {
		"id": loop.chat_id,
		"provider": settings.provider_id() if settings else "",
		"model": settings.model() if settings else "",
	}


func _on_new() -> void:
	loop.stop()
	if not loop.messages.is_empty():
		loop.chat_id = LumenChatStore.archive(loop.messages, _chat_meta())
	LumenTodos.clear()
	loop.reset_chat()
	dock.reset_transcript()
	dock.hide_plan()
	dock.clear_tools()
	dock.set_busy(false)
	dock.set_status("New chat")
	dock.refresh_chats()
	dock.refresh_todos()


func _on_chat_open(id: String) -> void:
	if id == "" or id == loop.chat_id:
		return
	loop.stop()
	if not loop.messages.is_empty():
		LumenChatStore.archive(loop.messages, _chat_meta())
	loop.chat_id = id
	loop.load_messages(LumenChatStore.load_chat(id))
	dock.reset_transcript()
	dock.restore_messages(loop.messages)
	dock.set_status("Loaded chat")
	dock.refresh_chats()


func _on_chat_delete(id: String) -> void:
	LumenChatStore.delete_chat(id)
	if id == loop.chat_id:
		_on_new()
	else:
		dock.refresh_chats()


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
	var pid := ""
	var default_mid := ""
	match kind:
		"codex":
			pid = "codex_cli"
			default_mid = "gpt-5.3-codex"
		"claude":
			pid = "claude_cli"
			default_mid = "claude-sonnet-4-5"
		"gemini":
			pid = "gemini_cli"
			default_mid = "gemini-2.5-flash"
		_:
			dock.append_system("Unknown CLI.")
			return
	settings.switch_provider(pid)
	var mid := settings.model()
	if mid == "":
		mid = default_mid
	settings.switch_model(pid, mid)
	# Prefill catalog so ModelOption is usable without an extra Scan.
	var names := settings.catalog(pid)
	if not names.is_empty():
		settings.set_model_catalog(names, pid)
	dock.bind_settings(settings)
	dock.refresh_cli_status()
	dock.append_system("Using %s via the official CLI session on this machine." % kind)
	dock.set_status("Provider: %s" % kind)


func _on_test_connection() -> void:
	var provider := settings.provider_id()
	if provider.ends_with("_cli"):
		dock.set_status("CLI session — Scan, then Use.")
		dock.append_system("CLI providers use the official session on this machine. Press Scan in CLI sessions.")
		return
	if provider == "anthropic":
		if settings.api_key() == "":
			dock.set_status("Error: API key missing.")
			dock.append_system("Anthropic needs a key in user:// secrets.")
			return
		dock.set_status("Configured · Anthropic")
		dock.append_system("Anthropic key present. Send a message to verify the Messages API.")
		return
	var url := settings.base_url().strip_edges()
	if url == "":
		dock.set_status("Error: Base URL missing.")
		return
	if not (url.begins_with("http://") or url.begins_with("https://")):
		dock.set_status("Error: URL must be http(s).")
		return
	dock.set_status("Loading %s…" % settings.model())
	if not openai.probed.is_connected(_on_probed):
		openai.probed.connect(_on_probed)
	openai.warmup(
		url,
		settings.api_key(),
		settings.model(),
		str(settings.get_value("keep_alive", "-1")),
		int(settings.get_value("num_ctx", 65536))
	)


func _on_probed(ok: bool, message: String) -> void:
	if openai.probed.is_connected(_on_probed):
		openai.probed.disconnect(_on_probed)
	if ok:
		dock.set_status("Loaded · %s" % settings.model())
		dock.append_system("Runtime ready. keep_alive %s, context %s. Large local models stay resident so tool steps do not reload VRAM." % [
			str(settings.get_value("keep_alive", "-1")),
			str(settings.get_value("num_ctx", 65536)),
		])
	else:
		dock.set_status("Error")
		dock.append_system(message)


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

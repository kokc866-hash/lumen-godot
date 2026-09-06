@tool
extends EditorPlugin

const DockScene := preload("res://addons/lumen/ui/dock.tscn")

var dock: Control
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
	plan = LumenPlanMode.new()
	openai = LumenOpenAICompatible.new()
	anthropic = LumenAnthropic.new()
	loop = LumenAgentLoop.new()
	dock = DockScene.instantiate()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	openai.attach(dock, log)
	anthropic.attach(dock, log)
	loop.setup(self, settings, registry, snapshots, plan, openai, anthropic, log, context, skills)
	dock.bind_settings(settings)
	dock.send_pressed.connect(_on_send)
	dock.new_chat.connect(_on_new)
	dock.undo_pressed.connect(_on_undo)
	dock.approve_plan.connect(_on_approve_plan)
	dock.reject_plan.connect(_on_reject_plan)
	dock.settings_changed.connect(_on_settings)
	loop.status.connect(dock.set_status)
	loop.assistant_delta.connect(dock.append_assistant)
	loop.turn_done.connect(func(text):
		dock.set_status("Idle")
		if text != "":
			pass
	)
	loop.turn_failed.connect(func(text):
		dock.append_system("Error: " + text)
		dock.set_status("Error")
	)
	loop.tool_proposed.connect(_on_tool_proposed)
	loop.plan_ready.connect(func(p):
		dock.show_plan(str(p.get("markdown", "")))
		dock.set_status("Waiting for plan approval")
	)
	mcp = LumenMcpServer.new()
	dock.add_child(mcp)
	mcp.configure(registry, log, int(settings.get_value("mcp_port", 8765)))
	if bool(settings.get_value("mcp_enabled", false)):
		mcp.start()
	log.info("Lumen entered the editor.")


func _exit_tree() -> void:
	if mcp:
		mcp.stop()
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null


func _on_send(text: String, mentions: PackedStringArray) -> void:
	if text.begins_with("/"):
		_slash(text)
		return
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
			dock.plan_check.button_pressed = true
			dock.append_system("Plan mode on.")
		"default":
			settings.set_value("plan_mode", false)
			dock.plan_check.button_pressed = false
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
	dock.set_status("New chat")


func _on_undo() -> void:
	var result := snapshots.restore_last()
	if bool(result.get("ok", false)):
		get_editor_interface().get_resource_filesystem().scan()
		dock.append_system("Restored %s" % str(result.get("files", [])))
	else:
		dock.append_system(str(result.get("error", "Undo failed.")))


func _on_approve_plan() -> void:
	dock.hide_plan()
	loop.approve_plan()


func _on_reject_plan() -> void:
	dock.hide_plan()
	loop.reject_plan()


func _on_settings() -> void:
	if mcp:
		mcp.stop()
		mcp.port = int(settings.get_value("mcp_port", 8765))
		if bool(settings.get_value("mcp_enabled", false)):
			mcp.start()


func _on_tool_proposed(call_id: String, name: String, args: Dictionary, readonly: bool) -> void:
	dock.append_tool(name, JSON.stringify(args).substr(0, 120))
	dock.add_tool_prompt(
		call_id,
		name,
		args,
		readonly,
		func(id): loop.approve_tool(id),
		func(id): loop.reject_tool(id),
		func(tool_name): loop.always_tool(tool_name)
	)

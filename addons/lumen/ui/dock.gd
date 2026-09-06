@tool
extends Control

signal send_pressed(text: String, mentions: PackedStringArray)
signal new_chat
signal undo_pressed
signal approve_plan
signal reject_plan
signal settings_changed
signal cli_scan
signal cli_login(kind: String)
signal cli_use(kind: String)

@onready var transcript: RichTextLabel = %Transcript
@onready var composer: TextEdit = %Composer
@onready var send_button: Button = %SendButton
@onready var status_label: Label = %Status
@onready var model_edit: LineEdit = %ModelEdit
@onready var provider_option: OptionButton = %ProviderOption
@onready var base_url_edit: LineEdit = %BaseUrlEdit
@onready var key_edit: LineEdit = %KeyEdit
@onready var image_url_edit: LineEdit = %ImageUrlEdit
@onready var mcp_port_edit: LineEdit = %McpPortEdit
@onready var plan_check: CheckBox = %PlanCheck
@onready var mcp_check: CheckBox = %McpCheck
@onready var plan_box: VBoxContainer = %PlanBox
@onready var plan_text: RichTextLabel = %PlanText
@onready var tool_box: VBoxContainer = %ToolBox

var settings: LumenSettings
var cli: LumenCliAuth


func bind_settings(p_settings: LumenSettings) -> void:
	settings = p_settings
	_load_fields()


func bind_cli(p_cli: LumenCliAuth) -> void:
	cli = p_cli
	refresh_cli_status()


func _ready() -> void:
	send_button.pressed.connect(_on_send)
	%NewButton.pressed.connect(func(): new_chat.emit())
	%UndoButton.pressed.connect(func(): undo_pressed.emit())
	%ApprovePlan.pressed.connect(func(): approve_plan.emit())
	%RejectPlan.pressed.connect(func(): reject_plan.emit())
	%SaveSettings.pressed.connect(_save_fields)
	if has_node("%ScanCli"):
		%ScanCli.pressed.connect(func():
			cli_scan.emit()
			refresh_cli_status()
		)
		%LoginCodex.pressed.connect(func(): cli_login.emit("codex"))
		%LoginClaude.pressed.connect(func(): cli_login.emit("claude"))
		%LoginGemini.pressed.connect(func(): cli_login.emit("gemini"))
		%UseCodex.pressed.connect(func(): cli_use.emit("codex"))
		%UseClaude.pressed.connect(func(): cli_use.emit("claude"))
		if has_node("%UseGemini"):
			%UseGemini.pressed.connect(func(): cli_use.emit("gemini"))
	provider_option.item_selected.connect(_on_provider)
	composer.gui_input.connect(_on_composer_input)
	plan_box.visible = false
	_seed_providers()
	append_system("Lumen is local-first. No account. Set a provider, then describe what you want.")


func _seed_providers() -> void:
	if provider_option.item_count > 0:
		return
	provider_option.add_item("ollama", 0)
	provider_option.add_item("lmstudio", 1)
	provider_option.add_item("openai", 2)
	provider_option.add_item("anthropic", 3)
	provider_option.add_item("custom", 4)
	provider_option.add_item("codex_cli", 5)
	provider_option.add_item("claude_cli", 6)
	provider_option.add_item("gemini_cli", 7)


func _load_fields() -> void:
	if settings == null:
		return
	_select_provider(settings.provider_id())
	base_url_edit.text = settings.base_url()
	model_edit.text = settings.model()
	key_edit.text = settings.api_key()
	if has_node("%ImageUrlEdit"):
		image_url_edit.text = str(settings.get_value("image_base_url", ""))
	if has_node("%McpPortEdit"):
		mcp_port_edit.text = str(settings.get_value("mcp_port", 8765))
	plan_check.button_pressed = settings.plan_mode()
	mcp_check.button_pressed = bool(settings.get_value("mcp_enabled", false))


func _save_fields() -> void:
	if settings == null:
		return
	settings.set_value("provider", _provider_name())
	settings.set_value("base_url", base_url_edit.text.strip_edges())
	settings.set_value("model", model_edit.text.strip_edges())
	settings.set_value("plan_mode", plan_check.button_pressed)
	settings.set_value("mcp_enabled", mcp_check.button_pressed)
	if has_node("%ImageUrlEdit"):
		settings.set_value("image_base_url", image_url_edit.text.strip_edges())
	if has_node("%McpPortEdit"):
		settings.set_value("mcp_port", int(mcp_port_edit.text.strip_edges()) if mcp_port_edit.text.strip_edges().is_valid_int() else 8765)
	settings.set_api_key(key_edit.text.strip_edges())
	settings_changed.emit()
	set_status("Settings saved. API key stays in user://lumen/secrets.json.")


func _on_provider(index: int) -> void:
	match index:
		0:
			base_url_edit.text = "http://127.0.0.1:11434/v1"
		1:
			base_url_edit.text = "http://127.0.0.1:1234/v1"
		2:
			base_url_edit.text = "https://api.openai.com/v1"
		3:
			base_url_edit.text = "https://api.anthropic.com"
		5:
			base_url_edit.text = "(codex login session)"
			if model_edit.text.strip_edges() == "":
				model_edit.text = "gpt-5.3-codex"
		6:
			base_url_edit.text = "(claude /login session)"
			if model_edit.text.strip_edges() == "":
				model_edit.text = "claude-sonnet-4-5"
		7:
			base_url_edit.text = "(gemini CLI session)"
			if model_edit.text.strip_edges() == "":
				model_edit.text = "gemini-2.5-flash"
		_:
			pass


func _provider_name() -> String:
	return provider_option.get_item_text(provider_option.selected)


func _select_provider(name: String) -> void:
	for i in provider_option.item_count:
		if provider_option.get_item_text(i) == name:
			provider_option.select(i)
			return
	provider_option.select(4)


func _on_send() -> void:
	var text := composer.text.strip_edges()
	if text == "":
		return
	var mentions := PackedStringArray()
	for token in text.split(" "):
		if token.begins_with("@") and token.length() > 1:
			mentions.append(token.substr(1))
	append_user(text)
	composer.text = ""
	send_pressed.emit(text, mentions)


func _on_composer_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and event.ctrl_pressed:
			_on_send()
			accept_event()


func set_status(text: String) -> void:
	status_label.text = text


func append_system(text: String) -> void:
	transcript.append_text("[color=#9aa0a6]%s[/color]\n\n" % _esc(text))


func append_user(text: String) -> void:
	transcript.append_text("[b]You[/b]\n%s\n\n" % _esc(text))


func append_assistant(text: String) -> void:
	transcript.append_text("[b][color=#f2c14e]Lumen[/color][/b]\n%s\n\n" % _esc(text))


func append_tool(name: String, detail: String) -> void:
	transcript.append_text("[color=#7cb87c]tool %s[/color] %s\n" % [_esc(name), _esc(detail)])


func show_plan(markdown: String) -> void:
	plan_box.visible = true
	plan_text.text = markdown


func hide_plan() -> void:
	plan_box.visible = false


func clear_tools() -> void:
	for child in tool_box.get_children():
		child.queue_free()


func add_tool_prompt(call_id: String, name: String, args: Dictionary, readonly: bool, on_yes: Callable, on_no: Callable, on_always: Callable) -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = "%s %s %s" % ["read" if readonly else "write", name, JSON.stringify(args).substr(0, 80)]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var yes := Button.new()
	yes.text = "Allow"
	yes.pressed.connect(func():
		on_yes.call(call_id)
		row.queue_free()
	)
	var no := Button.new()
	no.text = "Reject"
	no.pressed.connect(func():
		on_no.call(call_id)
		row.queue_free()
	)
	var always := Button.new()
	always.text = "Always"
	always.pressed.connect(func():
		on_always.call(name)
		on_yes.call(call_id)
		row.queue_free()
	)
	row.add_child(label)
	row.add_child(yes)
	row.add_child(always)
	row.add_child(no)
	tool_box.add_child(row)


func restore_messages(messages: Array) -> void:
	if messages.is_empty():
		return
	transcript.clear()
	append_system("Restored last chat from user://lumen/chats/current.json")
	for msg in messages:
		var role := str(msg.get("role", ""))
		var text := str(msg.get("content", ""))
		if text == "":
			continue
		if role == "user":
			append_user(text)
		elif role == "assistant":
			append_assistant(text)


func reset_transcript() -> void:
	transcript.clear()
	append_system("New chat. Previous context dropped.")


func refresh_cli_status() -> void:
	if not has_node("%CliStatus"):
		return
	if cli == null:
		%CliStatus.text = "CLI sessions: not bound."
		return
	%CliStatus.text = cli.status_line()


func _esc(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")

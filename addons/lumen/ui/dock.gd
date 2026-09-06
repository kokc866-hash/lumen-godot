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
signal test_pressed

const PROVIDERS := [
	{"id": "ollama", "label": "Ollama", "url": "http://127.0.0.1:11434/v1", "model": "qwen3.6:27b"},
	{"id": "lmstudio", "label": "LM Studio", "url": "http://127.0.0.1:1234/v1", "model": ""},
	{"id": "openai", "label": "OpenAI", "url": "https://api.openai.com/v1", "model": "gpt-4.1"},
	{"id": "grok", "label": "Grok", "url": "https://api.x.ai/v1", "model": "grok-4.5"},
	{"id": "anthropic", "label": "Anthropic", "url": "https://api.anthropic.com", "model": "claude-sonnet-4-5"},
	{"id": "custom", "label": "Custom", "url": "", "model": ""},
	{"id": "codex_cli", "label": "Codex CLI", "url": "", "model": "gpt-5.3-codex"},
	{"id": "claude_cli", "label": "Claude CLI", "url": "", "model": "claude-sonnet-4-5"},
	{"id": "gemini_cli", "label": "Gemini CLI", "url": "", "model": "gemini-2.5-flash"},
]

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
var _busy := false
var _seeding := false
var editor_scene: String = ""
var editor_selected: String = ""


func bind_settings(p_settings: LumenSettings) -> void:
	settings = p_settings
	_load_fields()
	_apply_provider_visibility()


func bind_cli(p_cli: LumenCliAuth) -> void:
	cli = p_cli
	refresh_cli_status()


func commit_settings() -> void:
	_save_fields(false)


func set_busy(value: bool) -> void:
	_busy = value
	send_button.disabled = value
	composer.editable = not value
	%NewButton.disabled = value
	send_button.text = "Working" if value else "Send"


func _ready() -> void:
	send_button.pressed.connect(_on_send)
	%NewButton.pressed.connect(func(): new_chat.emit())
	%UndoButton.pressed.connect(func(): undo_pressed.emit())
	%ApprovePlan.pressed.connect(func(): approve_plan.emit())
	%RejectPlan.pressed.connect(func(): reject_plan.emit())
	%SaveSettings.pressed.connect(func(): _save_fields(true))
	if has_node("%TestConnection"):
		%TestConnection.pressed.connect(func():
			_save_fields(false)
			test_pressed.emit()
		)
	%ScanCli.pressed.connect(func():
		cli_scan.emit()
		refresh_cli_status()
	)
	%LoginCodex.pressed.connect(func(): cli_login.emit("codex"))
	%LoginClaude.pressed.connect(func(): cli_login.emit("claude"))
	%LoginGemini.pressed.connect(func(): cli_login.emit("gemini"))
	%UseCodex.pressed.connect(func(): cli_use.emit("codex"))
	%UseClaude.pressed.connect(func(): cli_use.emit("claude"))
	%UseGemini.pressed.connect(func(): cli_use.emit("gemini"))
	provider_option.item_selected.connect(_on_provider)
	plan_check.toggled.connect(func(_on): _save_fields(false))
	mcp_check.toggled.connect(func(_on): _save_fields(false))
	if has_node("%CompactCheck"):
		%CompactCheck.toggled.connect(func(_on): _save_fields(false))
	if has_node("%ThinkCheck"):
		%ThinkCheck.toggled.connect(func(_on): _save_fields(false))
	composer.gui_input.connect(_on_composer_input)
	plan_box.visible = false
	_seed_providers()
	if has_node("%InsertContext"):
		%InsertContext.pressed.connect(_on_insert_context)
	append_system("Local-first agent. Open Connection or CLI sessions, then describe a change.")


func _seed_providers() -> void:
	if provider_option.item_count > 0:
		return
	_seeding = true
	provider_option.add_item("", 0)
	provider_option.set_item_metadata(0, "")
	for i in PROVIDERS.size():
		var row: Dictionary = PROVIDERS[i]
		var idx := i + 1
		provider_option.add_item(str(row["label"]), idx)
		provider_option.set_item_metadata(idx, str(row["id"]))
	_seeding = false


func _load_fields() -> void:
	if settings == null:
		return
	_select_provider(settings.provider_id())
	base_url_edit.text = settings.base_url()
	model_edit.text = settings.model()
	key_edit.text = settings.api_key()
	image_url_edit.text = str(settings.get_value("image_base_url", ""))
	mcp_port_edit.text = str(settings.get_value("mcp_port", 8765))
	if has_node("%CtxEdit"):
		%CtxEdit.text = str(settings.get_value("num_ctx", 65536))
	if has_node("%KeepEdit"):
		%KeepEdit.text = str(settings.get_value("keep_alive", "-1"))
	if has_node("%TempEdit"):
		%TempEdit.text = str(settings.get_value("temperature", 0.2))
	if has_node("%MaxEdit"):
		%MaxEdit.text = str(settings.get_value("max_tokens", 4096))
	plan_check.set_pressed_no_signal(settings.plan_mode())
	mcp_check.set_pressed_no_signal(bool(settings.get_value("mcp_enabled", false)))
	if has_node("%CompactCheck"):
		%CompactCheck.set_pressed_no_signal(bool(settings.get_value("compact_tools", true)))
	if has_node("%ThinkCheck"):
		%ThinkCheck.set_pressed_no_signal(bool(settings.get_value("think", false)))
	_apply_provider_visibility()
	_refresh_conn_chip()


func _save_fields(announce: bool = true) -> void:
	if settings == null:
		return
	settings.set_value("provider", _provider_id())
	settings.set_value("base_url", base_url_edit.text.strip_edges())
	settings.set_value("model", model_edit.text.strip_edges())
	settings.set_value("plan_mode", plan_check.button_pressed)
	settings.set_value("mcp_enabled", mcp_check.button_pressed)
	settings.set_value("image_base_url", image_url_edit.text.strip_edges())
	var port_text := mcp_port_edit.text.strip_edges()
	settings.set_value("mcp_port", int(port_text) if port_text.is_valid_int() else 8765)
	if has_node("%CtxEdit"):
		var ctx_text: String = %CtxEdit.text.strip_edges()
		settings.set_value("num_ctx", int(ctx_text) if ctx_text.is_valid_int() else 65536)
	if has_node("%KeepEdit"):
		var keep := %KeepEdit.text.strip_edges()
		settings.set_value("keep_alive", keep if keep != "" else "-1")
	if has_node("%TempEdit"):
		var temp := %TempEdit.text.strip_edges()
		settings.set_value("temperature", float(temp) if temp.is_valid_float() else 0.2)
	if has_node("%MaxEdit"):
		var mx := %MaxEdit.text.strip_edges()
		settings.set_value("max_tokens", int(mx) if mx.is_valid_int() else 4096)
	if has_node("%CompactCheck"):
		settings.set_value("compact_tools", %CompactCheck.button_pressed)
	if has_node("%ThinkCheck"):
		settings.set_value("think", %ThinkCheck.button_pressed)
	settings.set_api_key(key_edit.text.strip_edges())
	settings_changed.emit()
	if announce:
		set_status("Connection saved.")


func _on_provider(index: int) -> void:
	if _seeding:
		return
	var id := str(provider_option.get_item_metadata(index))
	var row: Dictionary = {}
	for item in PROVIDERS:
		if str(item["id"]) == id:
			row = item
			break
	var url := str(row.get("url", ""))
	if url != "":
		base_url_edit.text = url
	var model := str(row.get("model", ""))
	if model != "" and model_edit.text.strip_edges() == "":
		model_edit.text = model
	_apply_provider_visibility()
	_save_fields(false)
	_refresh_conn_chip()
	if has_node("%ConnFold"):
		%ConnFold.folded = false


func _refresh_conn_chip() -> void:
	if not has_node("%ConnChip"):
		return
	var id := _provider_id()
	var label := id
	for row in PROVIDERS:
		if str(row["id"]) == id:
			label = str(row["label"])
			break
	%ConnChip.text = label
	if has_node("%ConnFold"):
		%ConnFold.title = "Connection" if label == "" else "Connection  ·  %s" % label


func _apply_provider_visibility() -> void:
	var id := _provider_id()
	var cli_mode := id.ends_with("_cli")
	base_url_edit.editable = not cli_mode
	key_edit.editable = not cli_mode
	base_url_edit.visible = not cli_mode
	key_edit.visible = not cli_mode
	if has_node("%ULabel"):
		%ULabel.visible = not cli_mode
	if has_node("%KLabel"):
		%KLabel.visible = not cli_mode
	if cli_mode:
		base_url_edit.placeholder_text = "uses CLI session"
		key_edit.placeholder_text = "not used"
	else:
		base_url_edit.placeholder_text = "http://127.0.0.1:11434/v1"
		key_edit.placeholder_text = "user:// secrets"


func _provider_id() -> String:
	if provider_option.selected < 0:
		return ""
	return str(provider_option.get_item_metadata(provider_option.selected))


func _select_provider(name: String) -> void:
	for i in provider_option.item_count:
		if str(provider_option.get_item_metadata(i)) == name:
			provider_option.select(i)
			return
	provider_option.select(0)


func _on_send() -> void:
	if _busy:
		return
	var text := composer.text.strip_edges()
	if text == "":
		return
	_save_fields(false)
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
	var lower := text.to_lower()
	if "error" in lower or "fail" in lower:
		status_label.modulate = Color(0.95, 0.55, 0.5)
	elif "idle" in lower or "ready" in lower or "saved" in lower:
		status_label.modulate = Color(1, 1, 1)
	else:
		status_label.modulate = Color(0.82, 0.86, 0.92)


func append_system(text: String) -> void:
	transcript.append_text("[color=#8b909a]%s[/color]\n\n" % _esc(text))


func append_user(text: String) -> void:
	transcript.append_text("[b]You[/b]\n%s\n\n" % _esc(text))


func append_assistant(text: String) -> void:
	var accent := _accent_hex()
	transcript.append_text("[b][color=%s]Lumen[/color][/b]\n%s\n\n" % [accent, _esc(text)])


func append_tool(name: String, detail: String) -> void:
	transcript.append_text("[color=#7a9e7a]tool %s[/color] %s\n" % [_esc(name), _esc(detail)])


func show_plan(markdown: String) -> void:
	plan_box.visible = true
	plan_text.text = markdown


func hide_plan() -> void:
	plan_box.visible = false


func clear_tools() -> void:
	for child in tool_box.get_children():
		child.queue_free()


func add_tool_prompt(call_id: String, name: String, args: Dictionary, readonly: bool, on_yes: Callable, on_no: Callable, on_always: Callable) -> void:
	var card := PanelContainer.new()
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = "%s  %s\n%s" % ["Read" if readonly else "Write", name, JSON.stringify(args).substr(0, 160)]
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation", 6)
	var yes := Button.new()
	yes.text = "Allow"
	yes.pressed.connect(func():
		on_yes.call(call_id)
		card.queue_free()
	)
	var always := Button.new()
	always.text = "Always"
	always.pressed.connect(func():
		on_always.call(name)
		on_yes.call(call_id)
		card.queue_free()
	)
	var no := Button.new()
	no.text = "Reject"
	no.pressed.connect(func():
		on_no.call(call_id)
		card.queue_free()
	)
	actions.add_child(no)
	actions.add_child(always)
	actions.add_child(yes)
	row.add_child(label)
	row.add_child(actions)
	card.add_child(row)
	tool_box.add_child(card)


func restore_messages(messages: Array) -> void:
	if messages.is_empty():
		return
	transcript.clear()
	append_system("Restored last chat.")
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
	append_system("New chat.")


func refresh_cli_status() -> void:
	if cli == null:
		%CliStatus.text = "CLI helper not bound."
		return
	var s := cli.scan()
	%CliStatus.text = cli.status_line()
	_set_cli_button(%LoginCodex, s.get("codex", {}), false)
	_set_cli_button(%LoginClaude, s.get("claude", {}), false)
	_set_cli_button(%LoginGemini, s.get("gemini", {}), false)
	_set_cli_button(%UseCodex, s.get("codex", {}), true)
	_set_cli_button(%UseClaude, s.get("claude", {}), true)
	_set_cli_button(%UseGemini, s.get("gemini", {}), true)
	if has_node("%CliFold") and (bool(s.get("codex", {}).get("session", false)) or bool(s.get("claude", {}).get("session", false)) or bool(s.get("gemini", {}).get("session", false))):
		%CliFold.folded = false


func _set_cli_button(btn: Button, row: Variant, use_session: bool) -> void:
	if typeof(row) != TYPE_DICTIONARY:
		btn.disabled = true
		return
	if use_session:
		btn.disabled = not bool(row.get("session", false))
		btn.tooltip_text = "Session ready." if not btn.disabled else "No session. Login first."
	else:
		btn.disabled = not bool(row.get("cli", false))
		btn.tooltip_text = "Opens a terminal for official login." if not btn.disabled else "CLI binary not on PATH."


func _accent_hex() -> String:
	if has_theme_color("accent_color", "Editor"):
		return "#" + get_theme_color("accent_color", "Editor").to_html(false)
	return "#9eb4c8"


func _esc(text: String) -> String:
	return text.replace("[", "[lb]").replace("]", "[rb]")


func set_editor_context(scene_path: String, selected_paths: PackedStringArray) -> void:
	editor_scene = scene_path
	editor_selected = selected_paths[0] if selected_paths.size() > 0 else ""
	if not has_node("%ContextBar"):
		return
	var bits: PackedStringArray = PackedStringArray()
	if editor_scene != "":
		bits.append(editor_scene)
	if editor_selected != "":
		bits.append(editor_selected)
	%ContextBar.visible = bits.size() > 0
	if has_node("%ContextLabel"):
		%ContextLabel.text = " · ".join(bits)


func focus_composer() -> void:
	composer.grab_focus()


func insert_mention(path: String) -> void:
	var token := path.strip_edges()
	if token == "":
		return
	if not token.begins_with("@"):
		if not (token.begins_with("res://") or token.begins_with(".") or token.begins_with("/")):
			token = "res://" + token.lstrip("/")
		token = "@" + token
	var cur := composer.text
	if cur != "" and not cur.ends_with(" ") and not cur.ends_with("\n"):
		composer.text = cur + " " + token + " "
	else:
		composer.text = cur + token + " "
	composer.grab_focus()
	var line := composer.get_line_count() - 1
	composer.set_caret_line(line)
	composer.set_caret_column(composer.get_line(line).length())


func _on_insert_context() -> void:
	if editor_selected != "":
		insert_mention(editor_selected)
	elif editor_scene != "":
		insert_mention(editor_scene)


func _can_drop_data(_at: Vector2, data: Variant) -> bool:
	return _drop_paths(data).size() > 0


func _drop_data(_at: Vector2, data: Variant) -> void:
	for path in _drop_paths(data):
		insert_mention(str(path))


func _drop_paths(data: Variant) -> PackedStringArray:
	var out := PackedStringArray()
	if typeof(data) != TYPE_DICTIONARY:
		return out
	var kind := str(data.get("type", ""))
	if kind == "files" or kind == "files_and_dirs":
		for f in data.get("files", []):
			out.append(str(f))
	elif kind == "nodes":
		for n in data.get("nodes", []):
			out.append(str(n))
	elif kind == "resource":
		var res: Variant = data.get("resource")
		if res is Resource and str(res.resource_path) != "":
			out.append(str(res.resource_path))
	return out

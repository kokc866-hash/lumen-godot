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
signal stop_pressed
signal models_pressed
signal chat_open(id: String)

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
var _mention: PopupMenu
var _mention_timer: Timer
var _stream_open := false
var _chat_ids: PackedStringArray = PackedStringArray()
var _active_chat := ""


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
	send_button.text = "Send"
	composer.editable = true
	%NewButton.disabled = value
	if has_node("%StopButton"):
		%StopButton.disabled = not value


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
	if has_node("%ListModels"):
		%ListModels.pressed.connect(func():
			_save_fields(false)
			models_pressed.emit()
		)
	if has_node("%StopButton"):
		%StopButton.pressed.connect(func(): stop_pressed.emit())
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
	composer.text_changed.connect(_on_composer_text)
	_mention = PopupMenu.new()
	add_child(_mention)
	_mention.id_pressed.connect(_on_mention_pick)
	plan_box.visible = false
	_seed_providers()
	if has_node("%InsertContext"):
		%InsertContext.pressed.connect(_on_insert_context)
	if has_node("%ChatSearch"):
		%ChatSearch.text_changed.connect(func(t): refresh_chats(t))
	if has_node("%ChatList"):
		%ChatList.item_selected.connect(_on_chat_selected)
	append_system("Choose a provider in Connection, then describe a change. Ctrl+Enter sends.")
	_apply_chrome()


func _notification(what: int) -> void:
	if what == NOTIFICATION_THEME_CHANGED:
		_apply_chrome()


func _ed_color(name: String, fallback: Color) -> Color:
	if has_theme_color(name, "Editor"):
		return get_theme_color(name, "Editor")
	return fallback


func _pill(bg: Color, pad_x: int = 8, pad_y: int = 3, radius: int = 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.set_corner_radius_all(radius)
	box.content_margin_left = pad_x
	box.content_margin_right = pad_x
	box.content_margin_top = pad_y
	box.content_margin_bottom = pad_y
	return box


func _apply_chrome() -> void:
	var accent := _ed_color("accent_color", Color(0.45, 0.72, 0.98))
	var font := _ed_color("font_color", Color(0.86, 0.88, 0.91))
	var muted := Color(font.r, font.g, font.b, 0.62)
	var surface := _ed_color("dark_color_1", Color(0.14, 0.15, 0.17))
	var inset := _ed_color("dark_color_2", Color(0.10, 0.11, 0.13))
	var contrast := _ed_color("contrast_color_1", Color(1, 1, 1, 0.06))
	var chip_bg := Color(contrast.r, contrast.g, contrast.b, 0.10) if contrast.a < 0.2 else contrast.lerp(surface, 0.7)
	if has_node("%Title"):
		%Title.add_theme_color_override("font_color", accent)
		%Title.add_theme_font_size_override("font_size", 14)
	if has_node("%ModelChip"):
		%ModelChip.add_theme_color_override("font_color", muted)
		%ModelChip.add_theme_font_size_override("font_size", 11)
	if has_node("%ConnChip"):
		%ConnChip.add_theme_color_override("font_color", muted)
		%ConnChip.add_theme_font_size_override("font_size", 11)
	if has_node("%ModelChipWrap"):
		%ModelChipWrap.add_theme_stylebox_override("panel", _pill(chip_bg))
	if has_node("%ConnChipWrap"):
		%ConnChipWrap.add_theme_stylebox_override("panel", _pill(chip_bg))
	if has_node("%ContextLabel"):
		%ContextLabel.add_theme_color_override("font_color", muted)
	if transcript:
		transcript.add_theme_stylebox_override("normal", _pill(inset, 8, 8, 6))
		transcript.add_theme_color_override("default_color", font)
	if composer:
		composer.add_theme_stylebox_override("normal", _pill(inset, 8, 6, 6))
		composer.add_theme_stylebox_override("focus", _pill(inset.lerp(accent, 0.08), 8, 6, 6))
		composer.add_theme_color_override("font_color", font)
		composer.add_theme_color_override("font_placeholder_color", muted)
	if status_label:
		status_label.add_theme_color_override("font_color", muted)
		status_label.add_theme_font_size_override("font_size", 11)
	if send_button:
		var send_sb := _pill(accent.darkened(0.25), 12, 4, 6)
		send_button.add_theme_stylebox_override("normal", send_sb)
		send_button.add_theme_stylebox_override("hover", _pill(accent.darkened(0.12), 12, 4, 6))
		send_button.add_theme_stylebox_override("pressed", _pill(accent.darkened(0.35), 12, 4, 6))
		send_button.add_theme_stylebox_override("disabled", _pill(chip_bg, 12, 4, 6))
		send_button.add_theme_color_override("font_color", Color.WHITE)
	if has_node("%StopButton"):
		%StopButton.add_theme_stylebox_override("normal", _pill(chip_bg, 10, 4, 6))
		%StopButton.add_theme_stylebox_override("hover", _pill(Color(0.55, 0.22, 0.2, 0.9), 10, 4, 6))
		%StopButton.add_theme_stylebox_override("disabled", _pill(Color(chip_bg.r, chip_bg.g, chip_bg.b, 0.35), 10, 4, 6))
	if has_node("%NewButton"):
		%NewButton.add_theme_font_size_override("font_size", 12)
	if has_node("%UndoButton"):
		%UndoButton.add_theme_font_size_override("font_size", 12)
	if has_node("%ChatList"):
		%ChatList.add_theme_color_override("font_color", font)
		%ChatList.add_theme_color_override("font_hovered_color", accent)
		%ChatList.add_theme_color_override("font_selected_color", accent)
	if plan_text:
		plan_text.add_theme_stylebox_override("normal", _pill(surface, 8, 6, 6))
	if has_node("%TodoList"):
		%TodoList.add_theme_stylebox_override("normal", _pill(surface, 6, 4, 6))


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
	if has_node("%ConnFold"):
		%ConnFold.folded = settings.provider_id() != ""


func _save_fields(announce: bool = true) -> void:
	if settings == null:
		return
	settings.set_value("provider", _provider_id())
	settings.set_value("base_url", base_url_edit.text.strip_edges())
	var prev_model := settings.model()
	settings.set_value("model", model_edit.text.strip_edges())
	if model_edit.text.strip_edges() != prev_model:
		settings.apply_model_hints(model_edit.text.strip_edges(), false)
	settings.store_profile()
	settings.save_project()
	settings.set_value("plan_mode", plan_check.button_pressed)
	settings.set_value("mcp_enabled", mcp_check.button_pressed)
	settings.set_value("image_base_url", image_url_edit.text.strip_edges())
	var port_text := mcp_port_edit.text.strip_edges()
	settings.set_value("mcp_port", int(port_text) if port_text.is_valid_int() else 8765)
	if has_node("%CtxEdit"):
		var ctx_text: String = %CtxEdit.text.strip_edges()
		settings.set_value("num_ctx", int(ctx_text) if ctx_text.is_valid_int() else 65536)
	if has_node("%KeepEdit"):
		var keep: String = str(%KeepEdit.text).strip_edges()
		settings.set_value("keep_alive", keep if keep != "" else "-1")
	if has_node("%TempEdit"):
		var temp: String = str(%TempEdit.text).strip_edges()
		settings.set_value("temperature", float(temp) if temp.is_valid_float() else 0.2)
	if has_node("%MaxEdit"):
		var mx: String = str(%MaxEdit.text).strip_edges()
		settings.set_value("max_tokens", int(mx) if mx.is_valid_int() else 4096)
	if has_node("%CompactCheck"):
		settings.set_value("compact_tools", %CompactCheck.button_pressed)
	if has_node("%ThinkCheck"):
		settings.set_value("think", %ThinkCheck.button_pressed)
	settings.set_api_key(key_edit.text.strip_edges())
	settings_changed.emit()
	_refresh_conn_chip()
	if announce:
		set_status("Connection saved.")
		if has_node("%ConnFold") and _provider_id() != "":
			%ConnFold.folded = true


func _on_provider(index: int) -> void:
	if _seeding:
		return
	var id := str(provider_option.get_item_metadata(index))
	_save_fields(false)
	if settings:
		settings.store_profile(settings.provider_id())
		settings.switch_provider(id)
	var row: Dictionary = {}
	for item in PROVIDERS:
		if str(item["id"]) == id:
			row = item
			break
	if settings and settings.base_url() == "" and str(row.get("url", "")) != "":
		base_url_edit.text = str(row["url"])
		settings.set_value("base_url", base_url_edit.text, false)
	if settings and settings.model() == "" and str(row.get("model", "")) != "":
		model_edit.text = str(row["model"])
		settings.set_value("model", model_edit.text, false)
		settings.apply_model_hints(model_edit.text, false)
		settings.save_project()
	_load_fields()
	_apply_provider_visibility()
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
	if has_node("%ConnChipWrap"):
		%ConnChipWrap.visible = label != ""
	if has_node("%ConnFold"):
		%ConnFold.title = "Connection" if label == "" else "Connection  ·  %s" % label
	if has_node("%ModelChip"):
		var model := model_edit.text.strip_edges() if model_edit else ""
		%ModelChip.text = model
		%ModelChip.tooltip_text = model if model != "" else "No model set"
		if has_node("%ModelChipWrap"):
			%ModelChipWrap.visible = model != ""


func _apply_provider_visibility() -> void:
	var id := _provider_id()
	var cap: Dictionary = settings.capabilities(id) if settings else {"base_url": true, "api_key": true, "kind": ""}
	var kind := str(cap.get("kind", ""))
	var show_url := bool(cap.get("base_url", true))
	var show_key := bool(cap.get("api_key", false))
	base_url_edit.editable = show_url
	key_edit.editable = show_key
	base_url_edit.visible = show_url
	key_edit.visible = show_key
	if has_node("%ULabel"):
		%ULabel.visible = show_url
	if has_node("%KLabel"):
		%KLabel.visible = show_key
	_show_adv("%CtxLabel", "%CtxEdit", bool(cap.get("num_ctx", false)))
	_show_adv("%KeepLabel", "%KeepEdit", bool(cap.get("keep_alive", false)))
	_show_adv("%TempLabel", "%TempEdit", bool(cap.get("temperature", true)))
	_show_adv("%MaxLabel", "%MaxEdit", bool(cap.get("max_tokens", true)))
	if has_node("%ThinkCheck"):
		%ThinkCheck.visible = bool(cap.get("think", false))
	if has_node("%ListModels"):
		%ListModels.visible = bool(cap.get("list_models", true))
	if has_node("%TestConnection"):
		%TestConnection.visible = bool(cap.get("warmup", true))
	if has_node("%AdvFold"):
		var proto := settings.protocol(id) if settings else ""
		match proto:
			"ollama":
				%AdvFold.title = "Ollama /api/chat"
			"anthropic":
				%AdvFold.title = "Anthropic Messages"
			"gemini":
				%AdvFold.title = "Gemini"
			"openai":
				%AdvFold.title = "OpenAI-compatible /v1"
			_:
				%AdvFold.title = "Model options"
	if kind == "subscription":
		base_url_edit.placeholder_text = "uses CLI session"
		key_edit.placeholder_text = "not used"
	else:
		base_url_edit.placeholder_text = "http://127.0.0.1:11434/v1"
		key_edit.placeholder_text = "user:// secrets"


func _show_adv(label_path: String, edit_path: String, on: bool) -> void:
	if has_node(label_path):
		get_node(label_path).visible = on
	if has_node(edit_path):
		get_node(edit_path).visible = on

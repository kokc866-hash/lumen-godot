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

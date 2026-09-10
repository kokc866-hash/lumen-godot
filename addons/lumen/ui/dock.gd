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
signal chat_delete(id: String)

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
@onready var model_option: OptionButton = %ModelOption
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
var _model_ui_lock := false
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
	# Keep ghost icon from dock.tscn (Slice B); never reset to "Send".
	composer.editable = true
	%NewButton.disabled = value
	if has_node("%StopButton"):
		%StopButton.disabled = not value
	if value:
		set_status("Typing…")
	elif status_label and status_label.text == "Typing…":
		set_status("Ready")


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
	if has_node("%ModelOption"):
		model_option.item_selected.connect(_on_model_option)
	if model_edit:
		model_edit.text_submitted.connect(_on_model_edit_submitted)
		model_edit.focus_exited.connect(_on_model_edit_focus_exited)
	plan_check.toggled.connect(func(_on): _save_fields(false))
	mcp_check.toggled.connect(func(_on): _save_fields(false))
	if has_node("%CompactCheck"):
		%CompactCheck.toggled.connect(func(_on): _save_fields(false))
	if has_node("%ThinkCheck"):
		%ThinkCheck.toggled.connect(func(_on): _save_fields(false))
	composer.gui_input.connect(_on_composer_input)
	composer.text_changed.connect(_on_composer_text)
	if has_node("%ModelChipWrap"):
		%ModelChipWrap.gui_input.connect(_on_model_chip_gui)
	if has_node("%ModelChip"):
		%ModelChip.gui_input.connect(_on_model_chip_gui)
		%ModelChip.mouse_filter = Control.MOUSE_FILTER_STOP
	if has_node("%ConnChipWrap"):
		%ConnChipWrap.gui_input.connect(_on_model_chip_gui)
		%ConnChipWrap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if has_node("%ConnChip"):
		%ConnChip.gui_input.connect(_on_model_chip_gui)
		%ConnChip.mouse_filter = Control.MOUSE_FILTER_STOP
		%ConnChip.tooltip_text = "Open Connection"
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
		%ChatList.gui_input.connect(_on_chat_list_input)
	_show_empty_state()
	_layout_transcript_first()
	_bind_fold_accordion()
	_collapse_chrome_folds()
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
		transcript.add_theme_font_size_override("normal_font_size", 13)
	if composer:
		composer.add_theme_stylebox_override("normal", _pill(inset, 8, 6, 6))
		composer.add_theme_stylebox_override("focus", _pill(inset.lerp(accent, 0.08), 8, 6, 6))
		composer.add_theme_color_override("font_color", font)
		composer.add_theme_color_override("font_placeholder_color", muted)
	if status_label:
		status_label.add_theme_color_override("font_color", muted)
		status_label.add_theme_font_size_override("font_size", 11)
	if send_button:
		# Ghost/secondary — Enter is primary send.
		send_button.flat = true
		send_button.tooltip_text = "Enter sends · Ctrl+Enter also sends"
		send_button.add_theme_stylebox_override("normal", _pill(Color(0, 0, 0, 0), 10, 8, 6))
		send_button.add_theme_stylebox_override("hover", _pill(chip_bg, 10, 8, 6))
		send_button.add_theme_stylebox_override("pressed", _pill(chip_bg.lerp(accent, 0.25), 10, 8, 6))
		send_button.add_theme_stylebox_override("disabled", _pill(Color(0, 0, 0, 0), 10, 8, 6))
		send_button.add_theme_color_override("font_color", muted)
		send_button.add_theme_color_override("font_hover_color", accent)
		send_button.add_theme_color_override("font_disabled_color", Color(muted.r, muted.g, muted.b, 0.35))
		send_button.add_theme_font_size_override("font_size", 18)
	if has_node("%StopButton"):
		%StopButton.add_theme_stylebox_override("normal", _pill(chip_bg, 10, 4, 6))
		%StopButton.add_theme_stylebox_override("hover", _pill(Color(0.55, 0.22, 0.2, 0.9), 10, 4, 6))
		%StopButton.add_theme_stylebox_override("disabled", _pill(Color(chip_bg.r, chip_bg.g, chip_bg.b, 0.35), 10, 4, 6))
	if has_node("%NewButton"):
		%NewButton.text = "+"
		%NewButton.flat = true
		%NewButton.tooltip_text = "New chat"
		%NewButton.add_theme_font_size_override("font_size", 16)
	if has_node("%UndoButton"):
		%UndoButton.text = "↶"
		%UndoButton.flat = true
		%UndoButton.tooltip_text = "Undo last agent turn"
		%UndoButton.add_theme_font_size_override("font_size", 14)
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
	_sync_model_ui(settings.model())
	key_edit.text = settings.api_key()
	image_url_edit.text = str(settings.get_value("image_base_url", ""))
	if has_node("%ImageKeyEdit"):
		%ImageKeyEdit.text = settings.image_api_key()
	if has_node("%MeshUrlEdit"):
		%MeshUrlEdit.text = str(settings.get_value("mesh_base_url", "https://api.meshy.ai"))
	if has_node("%MeshKeyEdit"):
		%MeshKeyEdit.text = settings.mesh_api_key()
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
	# C1: folds stay collapsed; ModelChip / explicit actions open on demand.
	if has_node("%ConnFold"):
		%ConnFold.folded = true


func _load_binding_fields() -> void:
	if settings == null:
		return
	_sync_model_ui(settings.model())
	if has_node("%CtxEdit"):
		%CtxEdit.text = str(settings.get_value("num_ctx", 65536))
	if has_node("%KeepEdit"):
		%KeepEdit.text = str(settings.get_value("keep_alive", "-1"))
	if has_node("%TempEdit"):
		%TempEdit.text = str(settings.get_value("temperature", 0.2))
	if has_node("%MaxEdit"):
		%MaxEdit.text = str(settings.get_value("max_tokens", 4096))
	if has_node("%CompactCheck"):
		%CompactCheck.set_pressed_no_signal(bool(settings.get_value("compact_tools", true)))
	if has_node("%ThinkCheck"):
		%ThinkCheck.set_pressed_no_signal(bool(settings.get_value("think", false)))


func _save_fields(announce: bool = true) -> void:
	if settings == null:
		return
	settings.set_value("provider", _provider_id(), false)
	settings.set_value("base_url", base_url_edit.text.strip_edges(), false)
	# Write current Modell-Settings into project BEFORE any switch_model.
	if has_node("%CtxEdit"):
		var ctx_text: String = %CtxEdit.text.strip_edges()
		settings.set_value("num_ctx", int(ctx_text) if ctx_text.is_valid_int() else 65536, false)
	if has_node("%KeepEdit"):
		var keep: String = str(%KeepEdit.text).strip_edges()
		settings.set_value("keep_alive", keep if keep != "" else "-1", false)
	if has_node("%TempEdit"):
		var temp: String = str(%TempEdit.text).strip_edges()
		settings.set_value("temperature", float(temp) if temp.is_valid_float() else 0.2, false)
	if has_node("%MaxEdit"):
		var mx: String = str(%MaxEdit.text).strip_edges()
		settings.set_value("max_tokens", int(mx) if mx.is_valid_int() else 4096, false)
	if has_node("%CompactCheck"):
		settings.set_value("compact_tools", %CompactCheck.button_pressed, false)
	if has_node("%ThinkCheck"):
		settings.set_value("think", %ThinkCheck.button_pressed, false)
	var mid := _active_model_id()
	var prev := settings.model()
	var switched := false
	if mid != "" and mid != prev:
		settings.switch_model(_provider_id(), mid)
		switched = true
	elif mid != "":
		settings.set_value("model", mid, false)
		settings.store_profile()
		settings.save_project()
	else:
		settings.store_profile()
		settings.save_project()
	settings.set_value("plan_mode", plan_check.button_pressed)
	settings.set_value("mcp_enabled", mcp_check.button_pressed)
	settings.set_value("image_base_url", image_url_edit.text.strip_edges())
	if has_node("%ImageKeyEdit"):
		settings.set_image_api_key(str(%ImageKeyEdit.text).strip_edges())
	if has_node("%MeshUrlEdit"):
		settings.set_value("mesh_base_url", str(%MeshUrlEdit.text).strip_edges())
	if has_node("%MeshKeyEdit"):
		settings.set_mesh_api_key(str(%MeshKeyEdit.text).strip_edges())
	if str(settings.get_value("image_base_url", "")).find("retrodiffusion") >= 0:
		settings.set_value("image_kind", "retro")
	elif str(settings.get_value("image_base_url", "")).strip_edges() == "":
		settings.set_value("image_kind", "retro")
	else:
		settings.set_value("image_kind", "openai")
	var port_text := mcp_port_edit.text.strip_edges()
	settings.set_value("mcp_port", int(port_text) if port_text.is_valid_int() else 8765)
	settings.set_api_key(key_edit.text.strip_edges())
	if switched:
		# Reload binding fields so UI shows the target model, not leaked A→B values.
		_load_binding_fields()
	settings_changed.emit()
	_refresh_conn_chip()
	if announce:
		set_status("Connection saved.")
		if has_node("%ConnFold") and _provider_id() != "":
			%ConnFold.folded = true
		if has_node("%AdvFold"):
			%AdvFold.folded = true
		if has_node("%AssetFold"):
			%AssetFold.folded = true


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
		settings.switch_model(id, str(row["model"]))
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
	%ConnChip.tooltip_text = ("Open Connection — %s" % label) if label != "" else "Open Connection"
	if has_node("%ConnChipWrap"):
		%ConnChipWrap.visible = label != ""
		%ConnChipWrap.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if has_node("%ConnFold"):
		%ConnFold.title = "Connection" if label == "" else "Connection  ·  %s" % label
	if has_node("%ModelChip"):
		var model := settings.model() if settings else (model_edit.text.strip_edges() if model_edit else "")
		%ModelChip.text = model
		%ModelChip.tooltip_text = ("Open Connection — %s" % model) if model != "" else "Open Connection / set model"
		if has_node("%ModelChipWrap"):
			%ModelChipWrap.visible = model != ""



func _layout_transcript_first() -> void:
	## Header/Context → Transcript (+ transient boxes) → Composer/Footer → Folds.
	var root := get_node_or_null("Root") as VBoxContainer
	if root == null or transcript == null:
		return
	var order: Array[Node] = []
	for path in ["Header", "HeadSep", "ContextBar"]:
		var n := root.get_node_or_null(path)
		if n:
			order.append(n)
	order.append(transcript)
	for path in ["TodoBox", "PlanBox", "ToolBox", "ComposerRow", "Footer", "ChatFold", "ConnFold", "AdvFold", "AssetFold"]:
		var n2 := root.get_node_or_null(path)
		if n2:
			order.append(n2)
	for i in order.size():
		root.move_child(order[i], i)
	transcript.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	transcript.custom_minimum_size = Vector2(0, 160)


func _collapse_chrome_folds() -> void:
	for path in ["%ChatFold", "%ConnFold", "%AdvFold", "%AssetFold"]:
		if has_node(path):
			get_node(path).folded = true


func _bind_fold_accordion() -> void:
	for path in ["%ChatFold", "%ConnFold", "%AdvFold", "%AssetFold"]:
		if not has_node(path):
			continue
		var fold: FoldableContainer = get_node(path)
		if not fold.folding_changed.is_connected(_on_chrome_fold_changed):
			fold.folding_changed.connect(_on_chrome_fold_changed.bind(fold))


func _on_chrome_fold_changed(is_folded: bool, source: FoldableContainer) -> void:
	## Max one chrome fold open (Transcript stays the focus surface).
	if is_folded:
		return
	for path in ["%ChatFold", "%ConnFold", "%AdvFold", "%AssetFold"]:
		if not has_node(path):
			continue
		var fold: FoldableContainer = get_node(path)
		if fold != source and not fold.folded:
			fold.folded = true


func _on_model_chip_gui(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open_connection_fold()
		accept_event()


func _open_connection_fold() -> void:
	if has_node("%ConnFold"):
		%ConnFold.folded = false
	if has_node("%ModelOption") and model_option:
		model_option.grab_focus()
	elif model_edit and model_edit.visible:
		model_edit.grab_focus()


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
		# C2: one settings narrative — ConnFold = connection/model; Adv = Advanced only.
		%AdvFold.title = "Advanced"
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


func apply_models(names: PackedStringArray) -> void:
	## Scan = list refresh only. Never selects / switches model.
	if names.is_empty():
		append_system("Runtime reported no models.")
		return
	if settings:
		settings.set_model_catalog(names)
	_fill_model_option(names, settings.model() if settings else _active_model_id())
	_refresh_conn_chip()
	append_system("Models refreshed (%d). Select one in Connection." % names.size())


func _active_model_id() -> String:
	if model_option and model_option.visible and model_option.item_count > 0:
		var idx := model_option.selected
		if idx >= 0:
			var meta := str(model_option.get_item_metadata(idx))
			if meta != "" and meta != "__custom__":
				return meta
	if model_edit:
		return model_edit.text.strip_edges()
	return settings.model() if settings else ""


func _sync_model_ui(mid: String) -> void:
	var names := PackedStringArray()
	if settings:
		names = settings.model_catalog()
	_fill_model_option(names, mid)
	if model_edit:
		model_edit.text = mid


func _fill_model_option(names: PackedStringArray, selected: String) -> void:
	if model_option == null:
		if model_edit:
			model_edit.text = selected
		return
	_model_ui_lock = true
	model_option.clear()
	var found := -1
	for i in names.size():
		var n := str(names[i]).strip_edges()
		if n == "":
			continue
		model_option.add_item(n)
		model_option.set_item_metadata(model_option.item_count - 1, n)
		if n == selected:
			found = model_option.item_count - 1
	# Custom / not-in-list fallback entry.
	model_option.add_item("Custom…")
	model_option.set_item_metadata(model_option.item_count - 1, "__custom__")
	if found >= 0:
		model_option.select(found)
		if model_edit:
			model_edit.editable = false
			model_edit.text = selected
			model_edit.visible = false
		if has_node("%CustomLabel"):
			%CustomLabel.visible = false
	else:
		model_option.select(model_option.item_count - 1)
		if model_edit:
			model_edit.editable = true
			model_edit.visible = true
			model_edit.text = selected
		if has_node("%CustomLabel"):
			%CustomLabel.visible = true
	_model_ui_lock = false


func _on_model_option(index: int) -> void:
	if _model_ui_lock or settings == null:
		return
	var meta := str(model_option.get_item_metadata(index))
	if meta == "__custom__":
		if model_edit:
			model_edit.visible = true
			model_edit.editable = true
		if has_node("%CustomLabel"):
			%CustomLabel.visible = true
		return
	_apply_switch_model(meta)


func _on_model_edit_submitted(text: String) -> void:
	_apply_switch_model(text.strip_edges())


func _on_model_edit_focus_exited() -> void:
	if model_edit == null or settings == null:
		return
	if not model_edit.visible or not model_edit.editable:
		return
	var mid := model_edit.text.strip_edges()
	if mid != "" and mid != settings.model():
		_apply_switch_model(mid)


func _apply_switch_model(mid: String) -> void:
	mid = mid.strip_edges()
	if mid == "" or settings == null:
		return
	var pid := _provider_id()
	if pid == "":
		pid = settings.provider_id()
	if pid == "":
		append_system("Choose a provider first.")
		return
	# Save connection fields first so binding write sees current Temp/Ctx edits.
	_save_connection_only()
	settings.switch_model(pid, mid)
	_load_fields()
	_refresh_conn_chip()
	set_status("Model: %s" % mid)


func _save_connection_only() -> void:
	## Persist connection + current binding fields without switching model.
	if settings == null:
		return
	settings.set_value("provider", _provider_id(), false)
	settings.set_value("base_url", base_url_edit.text.strip_edges(), false)
	if has_node("%CtxEdit"):
		var ctx_text: String = %CtxEdit.text.strip_edges()
		settings.set_value("num_ctx", int(ctx_text) if ctx_text.is_valid_int() else 65536, false)
	if has_node("%KeepEdit"):
		var keep: String = str(%KeepEdit.text).strip_edges()
		settings.set_value("keep_alive", keep if keep != "" else "-1", false)
	if has_node("%TempEdit"):
		var temp: String = str(%TempEdit.text).strip_edges()
		settings.set_value("temperature", float(temp) if temp.is_valid_float() else 0.2, false)
	if has_node("%MaxEdit"):
		var mx: String = str(%MaxEdit.text).strip_edges()
		settings.set_value("max_tokens", int(mx) if mx.is_valid_int() else 4096, false)
	if has_node("%CompactCheck"):
		settings.set_value("compact_tools", %CompactCheck.button_pressed, false)
	if has_node("%ThinkCheck"):
		settings.set_value("think", %ThinkCheck.button_pressed, false)


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
	if composer:
		composer.grab_focus()


func _on_composer_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	var key: int = event.keycode
	var is_enter := key == KEY_ENTER or key == KEY_KP_ENTER
	if not is_enter:
		return
	# Mention-Popup: Enter wählt, sendet nie.
	if _mention != null and _mention.visible:
		if event.shift_pressed:
			return
		var idx := _mention.get_focused_item()
		if idx < 0 and _mention.get_item_count() > 0:
			idx = 0
		if idx >= 0:
			_on_mention_pick(idx)
		accept_event()
		return
	# Shift+Enter → Zeilenumbruch (TextEdit default).
	if event.shift_pressed:
		return
	# Enter / KP_Enter / Ctrl+Enter-Alias → senden.
	_on_send()
	if composer:
		composer.grab_focus()
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



func _show_empty_state() -> void:
	transcript.clear()
	var has_provider := settings != null and settings.provider_id() != ""
	if has_provider:
		append_system("Ready — describe a change. Enter sends · Shift+Enter new line.")
	else:
		append_system("No connection yet — click the model chip to open Connection.")


func append_system(text: String) -> void:
	# Meta line — not a bubble.
	transcript.append_text("[color=#6b7280][font_size=11]%s[/font_size][/color]\n" % _esc(text))


func append_user(text: String) -> void:
	end_stream()
	# User bubble: right / muted role.
	transcript.append_text(
		"[right][color=#8b909a][font_size=11]You[/font_size][/color]\n[font_size=13]%s[/font_size][/right]\n"
		% _esc(text)
	)


func append_assistant(text: String) -> void:
	end_stream()
	var accent := _accent_hex()
	# Assistant: left / accent role + body.
	transcript.append_text(
		"[color=%s][font_size=11]Lumen[/font_size][/color]\n[font_size=13]%s[/font_size]\n"
		% [accent, _esc(text)]
	)


func append_stream(text: String) -> void:
	if text == "":
		return
	if not _stream_open:
		var accent := _accent_hex()
		transcript.append_text("[color=%s][font_size=11]Lumen[/font_size][/color]\n[font_size=13]" % accent)
		_stream_open = true
	transcript.append_text(_esc(text))


func end_stream() -> void:
	if _stream_open:
		transcript.append_text("[/font_size]\n")
		_stream_open = false


func refresh_chats(query: String = "") -> void:
	if not has_node("%ChatList"):
		return
	%ChatList.clear()
	_chat_ids = PackedStringArray()
	var rows: Array = LumenChatStore.list_chats(query)
	for row in rows:
		var id := str(row.get("id", ""))
		_chat_ids.append(id)
		var title := str(row.get("title", id))
		if id == _active_chat:
			title = "· " + title
		var idx: int = %ChatList.add_item(title)
		var tip := str(row.get("preview", ""))
		var extra := str(row.get("model", ""))
		if extra != "":
			tip = ("%s · %s" % [extra, tip]) if tip != "" else extra
		%ChatList.set_item_tooltip(idx, tip)
		if id == _active_chat:
			%ChatList.set_item_custom_fg_color(idx, Color(0.82, 0.9, 1.0))
	if has_node("%ChatFold"):
		%ChatFold.title = "Chats" if rows.is_empty() else "Chats  ·  %d" % rows.size()


func _on_chat_selected(index: int) -> void:
	if index < 0 or index >= _chat_ids.size():
		return
	_active_chat = _chat_ids[index]
	chat_open.emit(_active_chat)
	refresh_chats(%ChatSearch.text if has_node("%ChatSearch") else "")


func _on_chat_list_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode != KEY_DELETE and event.keycode != KEY_BACKSPACE:
		return
	if not has_node("%ChatList"):
		return
	var idx: int = %ChatList.get_selected_items()[0] if %ChatList.get_selected_items().size() > 0 else -1
	if idx < 0 or idx >= _chat_ids.size():
		return
	chat_delete.emit(_chat_ids[idx])
	accept_event()


func refresh_todos() -> void:
	if not has_node("%TodoBox"):
		return
	var items: Array = LumenTodos.items
	%TodoBox.visible = not items.is_empty()
	if not has_node("%TodoList"):
		return
	var lines := PackedStringArray()
	for row in items:
		var mark := "x" if bool(row.get("done", false)) else " "
		lines.append("[%s] %s" % [mark, str(row.get("text", ""))])
	%TodoList.text = "\n".join(lines)


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
	_active_chat = ""
	transcript.clear()
	_show_empty_state()
	refresh_chats(%ChatSearch.text if has_node("%ChatSearch") else "")


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
	# C1: do not auto-expand AdvFold — Scan updates status only.


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


func _on_composer_text() -> void:
	if _mention == null:
		return
	var token := _at_token()
	if token == "":
		_mention.hide()
		return
	if _mention_timer == null:
		_mention_timer = Timer.new()
		_mention_timer.one_shot = true
		_mention_timer.wait_time = 0.12
		add_child(_mention_timer)
		_mention_timer.timeout.connect(_show_mentions)
	_mention_timer.start()


func _show_mentions() -> void:
	if _mention == null:
		return
	var token := _at_token()
	if token == "":
		_mention.hide()
		return
	_mention.clear()
	var shown := 0
	if editor_scene != "" and editor_scene.to_lower().find(token.to_lower()) >= 0:
		_mention.add_item(editor_scene)
		shown += 1
	if editor_selected != "":
		_mention.add_item(editor_selected)
		shown += 1
	shown += _add_file_mentions("res://", token.to_lower(), 24)
	if shown == 0:
		_mention.hide()
		return
	var pos := composer.get_screen_position() + Vector2(0, composer.size.y)
	_mention.position = pos
	_mention.popup()


func _add_file_mentions(dir_path: String, needle: String, limit: int) -> int:
	var added := 0
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "" and added < limit:
		if name.begins_with(".") or name == "addons":
			name = dir.get_next()
			continue
		var child := dir_path.path_join(name)
		if dir.current_is_dir():
			added += _add_file_mentions(child, needle, limit - added)
		elif name.to_lower().find(needle) >= 0 and _mentionable(name):
			_mention.add_item(child)
			added += 1
		name = dir.get_next()
	dir.list_dir_end()
	return added


func _mentionable(name: String) -> bool:
	for ext in [".gd", ".cs", ".tscn", ".gdshader", ".json", ".md", ".png", ".svg", ".tres", ".res", ".glb", ".gltf"]:
		if name.ends_with(ext):
			return true
	return false


func _at_token() -> String:
	var line := composer.get_line(composer.get_caret_line())
	var col := composer.get_caret_column()
	var left := line.substr(0, col)
	var at := left.rfind("@")
	if at < 0:
		return ""
	var token := left.substr(at + 1)
	if " " in token or "\t" in token:
		return ""
	return token


func _on_mention_pick(id: int) -> void:
	var path := _mention.get_item_text(id)
	var line_i := composer.get_caret_line()
	var line := composer.get_line(line_i)
	var col := composer.get_caret_column()
	var left := line.substr(0, col)
	var at := left.rfind("@")
	if at < 0:
		insert_mention(path)
		return
	var new_line := left.substr(0, at) + "@" + path + " " + line.substr(col)
	composer.set_line(line_i, new_line)
	composer.set_caret_column((left.substr(0, at) + "@" + path + " ").length())
	_mention.hide()

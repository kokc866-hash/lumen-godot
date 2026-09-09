@tool
extends "res://addons/lumen/ui/dock_core.gd"

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
	if names.is_empty():
		append_system("Runtime reported no models.")
		return
	if model_edit.text.strip_edges() == "":
		model_edit.text = names[0]
		_save_fields(false)
	_refresh_conn_chip()
	append_system("Models: %s" % ", ".join(names))


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
	end_stream()
	var accent := _accent_hex()
	transcript.append_text("[b][color=%s]Lumen[/color][/b]\n%s\n\n" % [accent, _esc(text)])


func append_stream(text: String) -> void:
	if text == "":
		return
	if not _stream_open:
		var accent := _accent_hex()
		transcript.append_text("[b][color=%s]Lumen[/color][/b]\n" % accent)
		_stream_open = true
	transcript.append_text(_esc(text))


func end_stream() -> void:
	if _stream_open:
		transcript.append_text("\n\n")
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
	append_system("New chat.")
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
	if has_node("%AdvFold") and (bool(s.get("codex", {}).get("session", false)) or bool(s.get("claude", {}).get("session", false)) or bool(s.get("gemini", {}).get("session", false))):
		%AdvFold.folded = false


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
	shown += _add_file_mentions("res://", token.to_lower(), 8)
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

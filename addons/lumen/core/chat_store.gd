@tool
class_name LumenChatStore
extends RefCounted


static func list_chats(query: String = "") -> Array:
	LumenPaths.ensure_dirs()
	var dir := DirAccess.open(LumenPaths.CHAT_DIR)
	if dir == null:
		return []
	var rows: Array = []
	var needle := query.strip_edges().to_lower()
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".json") and name != "current.json":
			var path := LumenPaths.CHAT_DIR.path_join(name)
			var data: Variant = LumenJson.read_file(path, {})
			var title := name.get_basename()
			var updated := FileAccess.get_modified_time(path)
			var preview := ""
			var count := 0
			var provider := ""
			var model := ""
			if typeof(data) == TYPE_DICTIONARY:
				title = str(data.get("title", title))
				updated = int(data.get("updated", updated))
				provider = str(data.get("provider", ""))
				model = str(data.get("model", ""))
				var msgs: Variant = data.get("messages", [])
				if typeof(msgs) == TYPE_ARRAY:
					count = msgs.size()
					preview = _preview(msgs)
			if _matches(needle, title, name, preview, provider, model):
				rows.append({
					"id": name.get_basename(),
					"title": title,
					"path": path,
					"updated": updated,
					"count": count,
					"preview": preview,
					"provider": provider,
					"model": model,
				})
		name = dir.get_next()
	dir.list_dir_end()
	rows.sort_custom(func(a, b): return int(a.get("updated", 0)) > int(b.get("updated", 0)))
	return rows


static func archive(messages: Array, meta: Dictionary = {}) -> String:
	if messages.is_empty():
		return ""
	var id := str(meta.get("id", ""))
	if id == "":
		id = _new_id()
	return save_chat(id, messages, meta)


static func save_chat(id: String, messages: Array, meta: Dictionary = {}) -> String:
	if id == "" or messages.is_empty():
		return ""
	LumenPaths.ensure_dirs()
	var title := str(meta.get("title", ""))
	if title == "":
		title = _title_from(messages)
	var payload := {
		"title": title,
		"messages": messages,
		"updated": int(Time.get_unix_time_from_system()),
		"provider": str(meta.get("provider", "")),
		"model": str(meta.get("model", "")),
		"count": messages.size(),
	}
	LumenJson.write_file(LumenPaths.CHAT_DIR.path_join(id + ".json"), payload)
	return id


static func load_chat(id: String) -> Array:
	var data: Variant = LumenJson.read_file(LumenPaths.CHAT_DIR.path_join(id + ".json"), {})
	if typeof(data) == TYPE_DICTIONARY:
		var msgs: Variant = data.get("messages", [])
		return msgs if typeof(msgs) == TYPE_ARRAY else []
	if typeof(data) == TYPE_ARRAY:
		return data
	return []


static func delete_chat(id: String) -> bool:
	if id == "" or id == "current":
		return false
	var path := LumenPaths.CHAT_DIR.path_join(id + ".json")
	if not FileAccess.file_exists(path):
		return false
	return DirAccess.remove_absolute(path) == OK


static func rename_chat(id: String, title: String) -> void:
	var path := LumenPaths.CHAT_DIR.path_join(id + ".json")
	var data: Variant = LumenJson.read_file(path, {})
	if typeof(data) != TYPE_DICTIONARY:
		return
	data["title"] = title.strip_edges()
	data["updated"] = int(Time.get_unix_time_from_system())
	LumenJson.write_file(path, data)


static func _new_id() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "").replace(" ", "-")
	return "%s-%d" % [stamp, Time.get_ticks_msec()]


static func _title_from(messages: Array) -> String:
	for msg in messages:
		if typeof(msg) != TYPE_DICTIONARY:
			continue
		if str(msg.get("role", "")) != "user":
			continue
		var text := str(msg.get("content", "")).strip_edges().replace("\n", " ")
		if text.begins_with("(Older"):
			continue
		if text != "":
			return text.substr(0, 56)
	return "chat"


static func _preview(messages: Array) -> String:
	var last := ""
	for msg in messages:
		if typeof(msg) != TYPE_DICTIONARY:
			continue
		var role := str(msg.get("role", ""))
		if role != "user" and role != "assistant":
			continue
		var text := str(msg.get("content", "")).strip_edges().replace("\n", " ")
		if text != "":
			last = text
	return last.substr(0, 80)


static func _matches(needle: String, title: String, name: String, preview: String, provider: String, model: String) -> bool:
	if needle == "":
		return true
	for hay in [title, name, preview, provider, model]:
		if hay.to_lower().find(needle) >= 0:
			return true
	return false

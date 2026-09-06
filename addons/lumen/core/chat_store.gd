@tool
class_name LumenChatStore
extends RefCounted

static func list_chats(query: String = "") -> Array:
	LumenPaths.ensure_dirs()
	var dir := DirAccess.open(LumenPaths.CHAT_DIR)
	if dir == null:
		return []
	var rows: Array = []
	var needle := query.to_lower()
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.ends_with(".json") and name != "current.json":
			var path := LumenPaths.CHAT_DIR.path_join(name)
			var data: Variant = LumenJson.read_file(path, {})
			var title := name.get_basename()
			if typeof(data) == TYPE_DICTIONARY:
				title = str(data.get("title", title))
			if needle == "" or title.to_lower().find(needle) >= 0 or name.to_lower().find(needle) >= 0:
				rows.append({"id": name.get_basename(), "title": title, "path": path})
		name = dir.get_next()
	dir.list_dir_end()
	rows.reverse()
	return rows


static func archive(messages: Array) -> String:
	if messages.is_empty():
		return ""
	LumenPaths.ensure_dirs()
	var title := "chat"
	for msg in messages:
		if str(msg.get("role", "")) == "user":
			title = str(msg.get("content", "chat")).substr(0, 48).replace("\n", " ")
			break
	var id := "%s-%d" % [Time.get_datetime_string_from_system().replace(":", ""), Time.get_ticks_msec()]
	id = id.replace(" ", "-")
	var path := LumenPaths.CHAT_DIR.path_join(id + ".json")
	LumenJson.write_file(path, {"title": title, "messages": messages})
	return id


static func load_chat(id: String) -> Array:
	var path := LumenPaths.CHAT_DIR.path_join(id + ".json")
	var data: Variant = LumenJson.read_file(path, {})
	if typeof(data) == TYPE_DICTIONARY:
		var msgs: Variant = data.get("messages", [])
		return msgs if typeof(msgs) == TYPE_ARRAY else []
	if typeof(data) == TYPE_ARRAY:
		return data
	return []

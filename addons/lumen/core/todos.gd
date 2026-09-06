@tool
class_name LumenTodos
extends RefCounted

static var items: Array = []


static func set_items(next: Array) -> Array:
	items = []
	for row in next:
		if typeof(row) == TYPE_DICTIONARY:
			items.append({
				"id": str(row.get("id", str(items.size() + 1))),
				"text": str(row.get("text", "")),
				"done": bool(row.get("done", false)),
			})
		elif str(row) != "":
			items.append({"id": str(items.size() + 1), "text": str(row), "done": false})
	return items


static func clear() -> void:
	items.clear()

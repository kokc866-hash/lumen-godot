@tool
class_name LumenEditor
extends RefCounted

## Godot 4.7+ editor access. EditorInterface is a singleton.
## Docks use EditorDock + add_dock (4.6/4.7). Old add_control_to_dock is fallback.


static func ei() -> EditorInterface:
	return EditorInterface


static func attach_dock(plugin: EditorPlugin, content: Control) -> Node:
	if ClassDB.class_exists("EditorDock") and plugin.has_method("add_dock"):
		var wrap: Node = ClassDB.instantiate("EditorDock")
		wrap.set("title", "Lumen")
		wrap.set("default_slot", EditorPlugin.DOCK_SLOT_RIGHT_UL)
		wrap.add_child(content)
		plugin.call("add_dock", wrap)
		return wrap
	plugin.add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, content)
	return content


static func detach_dock(plugin: EditorPlugin, wrap: Node, content: Control) -> void:
	if wrap != null and wrap != content and plugin.has_method("remove_dock"):
		plugin.call("remove_dock", wrap)
		if is_instance_valid(wrap):
			wrap.queue_free()
		return
	if content != null:
		plugin.remove_control_from_docks(content)
		if is_instance_valid(content):
			content.queue_free()

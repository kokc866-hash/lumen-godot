@tool
class_name LumenEditor
extends RefCounted

## Godot 4.7+ EditorDock. Vertical, bottom, or floating. Alt+L opens the tab.

const LAYOUT_ALL := 7


static func ei() -> EditorInterface:
	return EditorInterface


static func attach_dock(plugin: EditorPlugin, content: Control) -> Node:
	var icon: Texture2D = load("res://addons/lumen/icon.svg")
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	if ClassDB.class_exists("EditorDock") and plugin.has_method("add_dock"):
		var wrap: Node = ClassDB.instantiate("EditorDock")
		wrap.set("title", "Lumen")
		wrap.set("layout_key", "lumen")
		wrap.set("default_slot", EditorPlugin.DOCK_SLOT_RIGHT_UL)
		wrap.set("available_layouts", LAYOUT_ALL)
		wrap.set("force_show_icon", true)
		wrap.set("closable", true)
		if icon:
			wrap.set("dock_icon", icon)
		var shortcut := Shortcut.new()
		var ev := InputEventKey.new()
		ev.keycode = KEY_L
		ev.alt_pressed = true
		shortcut.events = [ev]
		wrap.set("dock_shortcut", shortcut)
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


static func focus_dock(wrap: Node) -> void:
	if wrap != null and wrap.has_method("make_visible"):
		wrap.call("make_visible")

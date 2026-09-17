@tool
extends "res://addons/lumen/ui/dock_core.gd"

func _provider_id() -> String:
	if provider_option.selected < 0:
		return ""
	return str(provider_option.get_item_metadata(provider_option.selected))

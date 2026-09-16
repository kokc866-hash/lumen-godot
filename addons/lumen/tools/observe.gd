@tool
class_name LumenObserve
extends RefCounted

## Anvil-style loop, Lumen-owned: observe -> act -> observe_diff -> validate.


func register(registry: LumenToolRegistry) -> void:
	registry.register_tool(LumenToolSpec.new(
		"observe",
		"Compact editor truth: scene, selection, play, errors, last playtest. Call before a big change.",
		{"type": "object", "properties": {}},
		true,
		obseserve
	))

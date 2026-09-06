@tool
class_name LumenToolSpec
extends RefCounted

var name: String
var description: String
var parameters: Dictionary
var readonly: bool
var callback: Callable


func _init(p_name: String, p_description: String, p_parameters: Dictionary, p_readonly: bool, p_callback: Callable) -> void:
	name = p_name
	description = p_description
	parameters = p_parameters
	readonly = p_readonly
	callback = p_callback


func openai_schema() -> Dictionary:
	return {
		"type": "function",
		"function": {
			"name": name,
			"description": description,
			"parameters": parameters,
		},
	}

@tool
class_name LumenPlanMode
extends RefCounted

signal awaiting_approval(plan: Dictionary)
signal approved(plan: Dictionary)
signal rejected

var pending: Dictionary = {}
var approved_plan: Dictionary = {}


func submit(plan: Dictionary) -> void:
	pending = plan
	awaiting_approval.emit(plan)


func approve() -> void:
	approved_plan = pending
	pending = {}
	approved.emit(approved_plan)


func reject() -> void:
	pending = {}
	approved_plan = {}
	rejected.emit()


func is_waiting() -> bool:
	return not pending.is_empty()


func has_approval() -> bool:
	return not approved_plan.is_empty()


func clear() -> void:
	pending = {}
	approved_plan = {}

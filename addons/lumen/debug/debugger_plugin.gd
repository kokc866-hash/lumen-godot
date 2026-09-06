@tool
class_name LumenDebuggerPlugin
extends EditorDebuggerPlugin

## Captures play-session output and breaks for get_debugger.

static var output: PackedStringArray = PackedStringArray()
static var stacks: Array = []
static var session_playing := false


func _setup_session(session_id: int) -> void:
	var session := get_session(session_id)
	if session == null:
		return
	session.started.connect(func():
		session_playing = true
		_note("session started")
	)
	session.stopped.connect(func():
		session_playing = false
		_note("session stopped")
	)
	if session.has_signal("breaked"):
		session.breaked.connect(func(_can_debug := true):
			_note("break")
			stacks.append({"at": Time.get_datetime_string_from_system(), "breaked": true})
			if stacks.size() > 20:
				stacks.remove_at(0)
		)


func _has_capture(capture: String) -> bool:
	return capture == "output" or capture == "error" or capture.begins_with("godot")


func _capture(message: String, data: Array, _session_id: int) -> bool:
	_note("%s %s" % [message, str(data)])
	return false


static func _note(line: String) -> void:
	output.append(line.strip_edges())
	if output.size() > 80:
		output.remove_at(0)


static func snapshot() -> Dictionary:
	return {
		"session_playing": session_playing,
		"output": output,
		"stacks": stacks,
	}

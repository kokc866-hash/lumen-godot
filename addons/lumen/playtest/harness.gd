extends Node

## Optional runtime helper. Copy into a scene as Autoload named LumenPlaytestIO
## if you want batch input replay during Play. Lumen writes the sidecar; this
## script only reads it. Nothing here talks to the network.

const SIDECAR := "res://.godot/lumen_playtest.json"
const MIN_HOLD_FRAMES := 2

var _inputs: Array = []
var _duration_ms := 0
var _started_ms := 0


func _ready() -> void:
	if not FileAccess.file_exists(SIDECAR):
		queue_free()
		return
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(SIDECAR))
	if typeof(data) != TYPE_DICTIONARY:
		queue_free()
		return
	_inputs = data.get("inputs", [])
	_duration_ms = int(data.get("duration_ms", 0))
	_started_ms = Time.get_ticks_msec()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SIDECAR))
	_replay()


func _replay() -> void:
	for entry in _inputs:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var wait_ms := int(entry.get("wait_ms", 0))
		if wait_ms > 0:
			await get_tree().create_timer(wait_ms / 1000.0).timeout
		_dispatch(entry, true)
		for _i in MIN_HOLD_FRAMES:
			await get_tree().physics_frame
		if bool(entry.get("release", true)):
			_dispatch(entry, false)
	if _duration_ms > 0:
		var remain := _duration_ms - (Time.get_ticks_msec() - _started_ms)
		if remain > 0:
			await get_tree().create_timer(remain / 1000.0).timeout
	print("lumen_pt:done")


func _dispatch(entry: Dictionary, pressed: bool) -> void:
	var kind := str(entry.get("type", "key"))
	if kind == "mouse":
		var ev := InputEventMouseButton.new()
		ev.button_index = int(entry.get("button", MOUSE_BUTTON_LEFT))
		ev.pressed = pressed
		ev.position = Vector2(float(entry.get("x", 0)), float(entry.get("y", 0)))
		Input.parse_input_event(ev)
		return
	var evk := InputEventKey.new()
	evk.pressed = pressed
	var key_name := str(entry.get("key", ""))
	if key_name != "":
		evk.keycode = OS.find_keycode_from_string(key_name)
	Input.parse_input_event(evk)

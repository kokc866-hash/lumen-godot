extends Node

## Optional runtime helper. Copy into a scene as Autoload named LumenPlaytestIO
## if you want batch input replay during Play. Lumen writes the sidecar; this
## script only reads it. Nothing here talks to the network.

const SIDECAR := "res://.godot/lumen_playtest.json"
const REPORT := "user://lumen/playtest_report.json"
const MIN_HOLD_FRAMES := 2

var _inputs: Array = []
var _duration_ms := 0
var _started_ms := 0
var _log: Array = []


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
	_write_report()
	print("lumen_pt:done")


func _write_report() -> void:
	var scene := get_tree().current_scene
	var world: Array = []
	if scene:
		world.append(_probe(scene, 0))
		for child in scene.get_children():
			world.append(_probe(child, 1))
			if world.size() >= 40:
				break
	var report := {
		"done": true,
		"elapsed_ms": Time.get_ticks_msec() - _started_ms,
		"inputs": _log,
		"scene": scene.scene_file_path if scene else "",
		"world": world,
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("user://lumen"))
	var f := FileAccess.open(REPORT, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report))


func _probe(node: Node, depth: int) -> Dictionary:
	var row := {
		"name": node.name,
		"type": node.get_class(),
		"depth": depth,
		"groups": node.get_groups(),
	}
	if node is Node2D:
		var n2 := node as Node2D
		row["x"] = n2.global_position.x
		row["y"] = n2.global_position.y
		row["rot"] = n2.global_rotation
	elif node is Node3D:
		var n3 := node as Node3D
		row["x"] = n3.global_position.x
		row["y"] = n3.global_position.y
		row["z"] = n3.global_position.z
	if node is CanvasItem:
		row["visible"] = (node as CanvasItem).visible
	return row


func _dispatch(entry: Dictionary, pressed: bool) -> void:
	_log.append({
		"t": Time.get_ticks_msec() - _started_ms,
		"type": str(entry.get("type", "key")),
		"key": str(entry.get("key", "")),
		"pressed": pressed,
	})
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

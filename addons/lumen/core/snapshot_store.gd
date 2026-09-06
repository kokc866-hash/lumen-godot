@tool
class_name LumenSnapshotStore
extends RefCounted

## File-level undo. Each agent turn writes a snapshot of files it is about to
## change. Restore copies those bytes back. No silent overwrite of live files
## without a prior snapshot.

const MAX_TURNS := 30

var log: LumenLogger
var _index: Array = []


func _init(p_log: LumenLogger) -> void:
	log = p_log
	LumenPaths.ensure_dirs()
	_index = LumenJson.read_file(LumenPaths.SNAPSHOT_DIR.path_join("index.json"), [])
	if typeof(_index) != TYPE_ARRAY:
		_index = []


func begin_turn(label: String = "") -> String:
	var id := Time.get_datetime_string_from_system(true, true).replace(":", "")
	id += "-%d" % Time.get_ticks_msec()
	_index.append({
		"id": id,
		"label": label,
		"created": Time.get_unix_time_from_system(),
		"files": [],
	})
	_trim()
	_save_index()
	return id


func capture(turn_id: String, res_path: String) -> void:
	if not FileAccess.file_exists(res_path):
		_remember(turn_id, res_path, false)
		return
	var dest_dir := LumenPaths.SNAPSHOT_DIR.path_join(turn_id)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dest_dir) if dest_dir.begins_with("user://") else dest_dir)
	var dest := dest_dir.path_join(res_path.replace("res://", "").replace("/", "__"))
	var data := FileAccess.get_file_as_bytes(res_path)
	var out := FileAccess.open(dest, FileAccess.WRITE)
	if out == null:
		log.error("Snapshot failed for %s" % res_path)
		return
	out.store_buffer(data)
	_remember(turn_id, res_path, true, dest)


func restore_last() -> Dictionary:
	if _index.is_empty():
		return {"ok": false, "error": "No snapshots."}
	var turn: Dictionary = _index.pop_back()
	_save_index()
	var restored: Array = []
	for entry in turn.get("files", []):
		var path := str(entry.get("path", ""))
		var existed := bool(entry.get("existed", false))
		if not existed:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(LumenPaths.to_abs(path))
				restored.append(path + " (removed)")
			continue
		var snap := str(entry.get("snap", ""))
		if snap == "" or not FileAccess.file_exists(snap):
			continue
		var bytes := FileAccess.get_file_as_bytes(snap)
		var out := FileAccess.open(path, FileAccess.WRITE)
		if out:
			out.store_buffer(bytes)
		restored.append(path)
	return {"ok": true, "id": turn.get("id", ""), "files": restored}


func list_turns() -> Array:
	return _index.duplicate(true)


func _remember(turn_id: String, path: String, existed: bool, snap: String = "") -> void:
	for turn in _index:
		if str(turn.get("id", "")) == turn_id:
			var files: Array = turn.get("files", [])
			files.append({"path": path, "existed": existed, "snap": snap})
			turn["files"] = files
			_save_index()
			return


func _trim() -> void:
	while _index.size() > MAX_TURNS:
		var old: Dictionary = _index.pop_front()
		var dir := LumenPaths.SNAPSHOT_DIR.path_join(str(old.get("id", "")))
		_rm_dir(ProjectSettings.globalize_path(dir))


func _save_index() -> void:
	LumenJson.write_file(LumenPaths.SNAPSHOT_DIR.path_join("index.json"), _index)


func _rm_dir(abs_path: String) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name != "." and name != "..":
			dir.remove(name)
		name = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(abs_path)

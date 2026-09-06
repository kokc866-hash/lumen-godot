@tool
class_name LumenPaths
extends RefCounted

const PROJECT_DIR := "res://.lumen"
const USER_DIR := "user://lumen"
const SNAPSHOT_DIR := "user://lumen/snapshots"
const LOG_DIR := "user://lumen/logs"
const CACHE_DIR := "user://lumen/cache"
const PROJECT_CONFIG := "res://.lumen/project.json"
const USER_SECRETS := "user://lumen/secrets.json"
const CHAT_DIR := "user://lumen/chats"
const HARNESS_SIDECAR := "res://.godot/lumen_playtest.json"
const HARNESS_SCRIPT := "res://.godot/lumen_playtest_io.gd"
const AGENTS_CANDIDATES := [
	"res://AGENTS.md",
	"res://.lumen/AGENTS.md",
	"res://.agents/AGENTS.md",
]


static func ensure_dirs() -> void:
	for path in [PROJECT_DIR, USER_DIR, SNAPSHOT_DIR, LOG_DIR, CACHE_DIR, CHAT_DIR]:
		_mkdir(path)


static func _mkdir(path: String) -> void:
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path))


static func project_root() -> String:
	return ProjectSettings.globalize_path("res://")


static func to_res(path: String) -> String:
	var abs_root := project_root().trim_suffix("/")
	var abs_path := path
	if path.begins_with("res://"):
		return path.replace("\\", "/")
	abs_path = path.replace("\\", "/")
	if abs_path.begins_with(abs_root):
		return "res://" + abs_path.substr(abs_root.length()).lstrip("/")
	return path


static func to_abs(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path


static func is_inside_project(path: String) -> bool:
	var abs_path := to_abs(path).simplify_path()
	var root := project_root().simplify_path()
	return abs_path == root or abs_path.begins_with(root + "/")

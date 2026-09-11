@tool
class_name LumenCliAuth
extends RefCounted

## Discovers official coding-agent CLIs on this machine and starts their login.
## Lumen never opens a Ziva / vendor wallet. Tokens stay in the CLI's own files.

const CODEX_CLIENT_ID := "app_EMoamEEZ73f0CkXaXp7hrann"
const CODEX_REFRESH_URL := "https://auth.openai.com/oauth/token"

var log: LumenLogger


func _init(p_log: LumenLogger) -> void:
	log = p_log


func home_dir() -> String:
	var home := OS.get_environment("HOME")
	if home == "":
		home = OS.get_environment("USERPROFILE")
	return home


func scan() -> Dictionary:
	return {
		"codex": _scan_codex(),
		"claude": _scan_claude(),
		"gemini": _scan_gemini(),
	}


func status_line() -> String:
	var s := scan()
	var bits: Array = []
	for key in ["codex", "claude", "gemini"]:
		var row: Dictionary = s[key]
		if bool(row.get("session", false)):
			bits.append("%s: signed in" % key)
		elif bool(row.get("cli", false)):
			bits.append("%s: CLI, no session" % key)
		else:
			bits.append("%s: not installed" % key)
	return " · ".join(bits)


func start_login(kind: String) -> Dictionary:
	var cmd := ""
	match kind:
		"codex":
			cmd = "codex login"
		"claude":
			cmd = "claude /login"
		"gemini":
			cmd = "gemini"
		_:
			return {"ok": false, "error": "Unknown CLI %s" % kind}
	if not _which(_bin(kind)):
		return {
			"ok": false,
			"error": "%s CLI not on PATH. Install the official tool, then try again." % kind,
		}
	var err := _open_terminal(cmd)
	if err != OK:
		return {"ok": false, "error": "Could not open a terminal (%s)." % error_string(err)}
	return {
		"ok": true,
		"message": "Finish login in the terminal. Then press Scan.",
	}


func _bin(kind: String) -> String:
	match kind:
		"codex":
			return "codex"
		"claude":
			return "claude"
		"gemini":
			return "gemini"
		_:
			return kind


func _which(bin: String) -> bool:
	if bin == "":
		return false
	var path := OS.get_environment("PATH")
	var sep := ";" if OS.get_name() == "Windows" else ":"
	for folder in path.split(sep):
		if folder == "":
			continue
		var candidate := folder.path_join(bin)
		if FileAccess.file_exists(candidate) or FileAccess.file_exists(candidate + ".exe") or FileAccess.file_exists(candidate + ".cmd"):
			return true
	return false


func _open_terminal(command: String) -> Error:
	var os_name := OS.get_name()
	var args: PackedStringArray
	var exe := ""
	match os_name:
		"Windows":
			exe = "cmd.exe"
			args = PackedStringArray(["/c", "start", "cmd", "/k", command])
		"macOS":
			exe = "osascript"
			args = PackedStringArray(["-e", "tell application \"Terminal\" to do script \"%s\"" % command.replace("\"", "\\\"")])
		_:
			if FileAccess.file_exists("/usr/bin/x-terminal-emulator"):
				exe = "x-terminal-emulator"
				args = PackedStringArray(["-e", "bash", "-lc", "%s; echo; read -n 1 -s -r -p 'Done. Press any key.';" % command])
			elif FileAccess.file_exists("/usr/bin/gnome-terminal"):
				exe = "gnome-terminal"
				args = PackedStringArray(["--", "bash", "-lc", "%s; exec bash" % command])
			else:
				exe = "xterm"
				args = PackedStringArray(["-e", "bash", "-lc", command])
	var pid := OS.create_process(exe, args)
	return OK if pid > 0 else ERR_CANT_OPEN


func _scan_codex() -> Dictionary:
	var path := _codex_auth_path()
	var raw := _read_json(path)
	var tokens: Dictionary = raw.get("tokens", {})
	if typeof(tokens) != TYPE_DICTIONARY:
		tokens = {}
	var access := str(tokens.get("access_token", raw.get("OPENAI_API_KEY", "")))
	return {
		"cli": _which("codex"),
		"session": access != "",
		"mode": str(raw.get("auth_mode", "")),
		"path": path,
		"account_id": _codex_account_id(tokens, access),
		"has_api_key": str(raw.get("OPENAI_API_KEY", "")) != "",
	}


func _scan_claude() -> Dictionary:
	var path := home_dir().path_join(".claude").path_join(".credentials.json")
	var raw := _read_json(path)
	var oauth: Dictionary = raw.get("claudeAiOauth", {})
	if typeof(oauth) != TYPE_DICTIONARY:
		oauth = {}
	var token := str(oauth.get("accessToken", ""))
	if token == "":
		token = OS.get_environment("CLAUDE_CODE_OAUTH_TOKEN")
	return {
		"cli": _which("claude"),
		"session": token != "",
		"path": path,
		"subscription": str(oauth.get("subscriptionType", "")),
	}


func _scan_gemini() -> Dictionary:
	var creds := load_gemini_token()
	return {
		"cli": _which("gemini"),
		"session": bool(creds.get("ok", false)),
		"path": str(creds.get("path", "")),
		"mode": str(creds.get("mode", "")),
	}


func load_codex_tokens() -> Dictionary:
	var path := _codex_auth_path()
	var raw := _read_json(path)
	var tokens: Dictionary = raw.get("tokens", {})
	if typeof(tokens) != TYPE_DICTIONARY:
		tokens = {}
	var access := str(tokens.get("access_token", ""))
	var api_key := str(raw.get("OPENAI_API_KEY", ""))
	return {
		"ok": access != "" or api_key != "",
		"path": path,
		"raw": raw,
		"access_token": access,
		"refresh_token": str(tokens.get("refresh_token", "")),
		"id_token": str(tokens.get("id_token", "")),
		"account_id": _codex_account_id(tokens, access if access != "" else str(tokens.get("id_token", ""))),
		"api_key": api_key,
		"auth_mode": str(raw.get("auth_mode", "")),
	}


func write_codex_tokens(updated: Dictionary) -> void:
	var path := _codex_auth_path()
	var raw := _read_json(path)
	if typeof(raw) != TYPE_DICTIONARY:
		raw = {}
	var tokens: Dictionary = raw.get("tokens", {})
	if typeof(tokens) != TYPE_DICTIONARY:
		tokens = {}
	if str(updated.get("access_token", "")) != "":
		tokens["access_token"] = updated["access_token"]
	if str(updated.get("refresh_token", "")) != "":
		tokens["refresh_token"] = updated["refresh_token"]
	if str(updated.get("id_token", "")) != "":
		tokens["id_token"] = updated["id_token"]
	raw["tokens"] = tokens
	raw["last_refresh"] = Time.get_datetime_string_from_system(true, true)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(raw, "\t"))


func load_gemini_token() -> Dictionary:
	var path := home_dir().path_join(".gemini").path_join("oauth_creds.json")
	var raw := _read_json(path)
	var access := str(raw.get("access_token", raw.get("accessToken", "")))
	var api_key := OS.get_environment("GEMINI_API_KEY")
	if api_key == "":
		api_key = OS.get_environment("GOOGLE_API_KEY")
	var mode := ""
	if access != "":
		mode = "oauth"
	elif api_key != "":
		mode = "api_key"
	return {
		"ok": access != "" or api_key != "",
		"path": path,
		"access_token": access,
		"refresh_token": str(raw.get("refresh_token", raw.get("refreshToken", ""))),
		"api_key": api_key,
		"mode": mode,
	}


func load_claude_token() -> Dictionary:
	var path := home_dir().path_join(".claude").path_join(".credentials.json")
	var raw := _read_json(path)
	var oauth: Dictionary = raw.get("claudeAiOauth", {})
	if typeof(oauth) != TYPE_DICTIONARY:
		oauth = {}
	var token := str(oauth.get("accessToken", ""))
	if token == "":
		token = OS.get_environment("CLAUDE_CODE_OAUTH_TOKEN")
	return {
		"ok": token != "",
		"access_token": token,
		"refresh_token": str(oauth.get("refreshToken", "")),
		"expires_at": oauth.get("expiresAt", 0),
	}




## Sync discovery via official CLI. Returns { ok, names: PackedStringArray, error?, seed_fallback? }.
func list_codex_models() -> Dictionary:
	if not _which("codex"):
		return {"ok": false, "names": PackedStringArray(), "error": "codex CLI not on PATH", "seed_fallback": true}
	var attempts: Array = [
		PackedStringArray(["debug", "models"]),
		PackedStringArray(["--bundled", "debug", "models"]),
	]
	var last_err := "codex debug models failed"
	for args in attempts:
		var output: Array = []
		var code := OS.execute("codex", args, output, true, false)
		var chunks := PackedStringArray()
		for line in output:
			chunks.append(str(line))
		var text := "\n".join(chunks)
		var names := _parse_model_list_text(text)
		if not names.is_empty():
			return {"ok": true, "names": names, "seed_fallback": false}
		if code != 0:
			last_err = "codex debug models failed (%d): %s" % [code, LumenJson.clamp_text(text, 300)]
		else:
			last_err = "codex returned no models"
	return {"ok": false, "names": PackedStringArray(), "error": last_err, "seed_fallback": true}


func _parse_model_list_text(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	var stripped := text.strip_edges()
	if stripped == "":
		return out
	# Prefer JSON (array or {data|models:[...]})
	var parsed: Variant = JSON.parse_string(stripped)
	if typeof(parsed) == TYPE_DICTIONARY:
		var rows: Variant = parsed.get("data", parsed.get("models", parsed.get("items", [])))
		if typeof(rows) == TYPE_ARRAY:
			for row in rows:
				var id := ""
				if typeof(row) == TYPE_DICTIONARY:
					id = str(row.get("slug", row.get("id", row.get("name", row.get("model", "")))))
				else:
					id = str(row)
				id = id.strip_edges()
				if id != "" and out.find(id) < 0:
					out.append(id)
			return out
	if typeof(parsed) == TYPE_ARRAY:
		for row in parsed:
			var id := ""
			if typeof(row) == TYPE_DICTIONARY:
				id = str(row.get("slug", row.get("id", row.get("name", ""))))
			else:
				id = str(row)
			id = id.strip_edges()
			if id != "" and out.find(id) < 0:
				out.append(id)
		return out
	# Line / whitespace tokens that look like model ids
	for line in text.split("\n"):
		var s := line.strip_edges()
		if s == "" or s.begins_with("#") or s.begins_with("["):
			continue
		# Drop common log prefixes
		if s.to_lower().begins_with("error") or s.to_lower().begins_with("warn"):
			continue
		# Take first token if tabular
		var token := s.split("\t")[0].split(" ")[0].strip_edges()
		if token.find("/") >= 0 or token.find("-") >= 0 or token.find(".") >= 0:
			if token.length() >= 3 and out.find(token) < 0:
				out.append(token)
	return out

func _codex_auth_path() -> String:
	var custom := OS.get_environment("CODEX_HOME")
	if custom != "":
		return custom.path_join("auth.json")
	return home_dir().path_join(".codex").path_join("auth.json")


func _codex_account_id(tokens: Dictionary, access_or_id: String) -> String:
	var stored := str(tokens.get("account_id", ""))
	if stored != "":
		return stored
	return _jwt_account_id(access_or_id)


func _jwt_account_id(token: String) -> String:
	var parts := token.split(".")
	if parts.size() < 2:
		return ""
	var payload := _b64url(parts[1])
	var parsed: Variant = JSON.parse_string(payload)
	if typeof(parsed) != TYPE_DICTIONARY:
		return ""
	var auth: Variant = parsed.get("https://api.openai.com/auth", {})
	if typeof(auth) == TYPE_DICTIONARY:
		return str(auth.get("chatgpt_account_id", ""))
	return str(parsed.get("chatgpt_account_id", ""))


func jwt_expired(token: String, skew_sec: int = 60) -> bool:
	var parts := token.split(".")
	if parts.size() < 2:
		return true
	var parsed: Variant = JSON.parse_string(_b64url(parts[1]))
	if typeof(parsed) != TYPE_DICTIONARY:
		return true
	var exp := int(parsed.get("exp", 0))
	if exp <= 0:
		return false
	return Time.get_unix_time_from_system() + skew_sec >= exp


func _b64url(chunk: String) -> String:
	var padded := chunk.replace("-", "+").replace("_", "/")
	while padded.length() % 4 != 0:
		padded += "="
	var bytes := Marshalls.base64_to_raw(padded)
	return bytes.get_string_from_utf8()


func _read_json(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var text := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(text)
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}

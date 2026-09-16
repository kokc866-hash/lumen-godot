@tool
class_name LumenHttp
extends RefCounted

## Blocking HTTP for editor tools. Loopback and public HTTPS only.


static func request_json(method: String, url: String, headers: PackedStringArray, body: String = "", timeout_ms: int = 60000) -> Dictionary:
	var raw := request_bytes(method, url, headers, body.to_utf8_buffer() if body != "" else PackedByteArray(), timeout_ms)
	if not bool(raw.get("ok", false)):
		return raw
	var text := (raw.get("bytes") as PackedByteArray).get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(text)
	return {
		"ok": true,
		"status": raw.get("status", 0),
		"json": parsed,
		"text": LumenJson.clamp_text(text, 800),
	}


static func request_bytes(method: String, url: String, headers: PackedStringArray, body: PackedByteArray = PackedByteArray(), timeout_ms: int = 90000) -> Dictionary:
	var tls := url.begins_with("https://")
	var stripped := url.trim_prefix("https://").trim_prefix("http://")
	var slash := stripped.find("/")
	var hostport := stripped if slash < 0 else stripped.substr(0, slash)
	var path := "/" if slash < 0 else stripped.substr(slash)
	var host := hostport
	var port := 443 if tls else 80
	if ":" in hostport:
		var hp := hostport.split(":")
		host = hp[0]
		port = int(hp[1])
	var http := HTTPClient.new()
	var err := http.connect_to_host(host, port, TLSOptions.client() if tls else null)
	if err != OK:
		return {"ok": false, "error": "Connect failed: %s" % error_string(err)}
	var waited := 0
	while http.get_status() == HTTPClient.STATUS_CONNECTING or http.get_status() == HTTPClient.STATUS_RESOLVING:
		http.poll()
		OS.delay_msec(25)
		waited += 25
		if waited > 20000:
			return {"ok": false, "error": "Connect timeout for %s" % host}
	if http.get_status() != HTTPClient.STATUS_CONNECTED:
		return {"ok": false, "error": "Not connected (%d)." % http.get_status()}
	var verb := HTTPClient.METHOD_GET
	if method == "POST":
		verb = HTTPClient.METHOD_POST
	elif method == "PUT":
		verb = HTTPClient.METHOD_PUT
	err = http.request(verb, path, headers, body.get_string_from_utf8() if body.size() > 0 else "")
	if err != OK:
		return {"ok": false, "error": "Request failed: %s" % error_string(err)}
	waited = 0
	while http.get_status() == HTTPClient.STATUS_REQUESTING:
		http.poll()
		OS.delay_msec(25)
		waited += 25
		if waited > timeout_ms:
			return {"ok": false, "error": "Request timeout."}
	var out := PackedByteArray()
	waited = 0
	while http.get_status() == HTTPClient.STATUS_BODY:
		http.poll()
		var chunk := http.read_response_body_chunk()
		if chunk.size() > 0:
			out.append_array(chunk)
		else:
			OS.delay_msec(20)
		waited += 20
		if waited > timeout_ms:
			break
	var status := http.get_response_code()
	if status >= 400:
		return {
			"ok": false,
			"status": status,
			"error": "HTTP %d" % status,
			"text": LumenJson.clamp_text(out.get_string_from_utf8(), 500),
		}
	return {"ok": true, "status": status, "bytes": out}

@tool
class_name LumenMcpServer
extends Node

## Local-only JSON-RPC surface for MCP-style clients. Binds 127.0.0.1.
## External clients decide what to call; Lumen still runs the same tools.

var server := TCPServer.new()
var peers: Array = []
var registry: LumenToolRegistry
var log: LumenLogger
var port := 8765
var enabled := false


func configure(p_registry: LumenToolRegistry, p_log: LumenLogger, p_port: int) -> void:
	registry = p_registry
	log = p_log
	port = p_port


func start() -> Error:
	stop()
	var err := server.listen(port, "127.0.0.1")
	if err != OK:
		log.error("MCP listen failed on 127.0.0.1:%d (%s)" % [port, error_string(err)])
		return err
	enabled = true
	set_process(true)
	log.info("MCP listening on 127.0.0.1:%d" % port)
	return OK


func stop() -> void:
	enabled = false
	set_process(false)
	for peer in peers:
		if peer is StreamPeerTCP:
			(peer as StreamPeerTCP).disconnect_from_host()
	peers.clear()
	if server.is_listening():
		server.stop()


func _process(_delta: float) -> void:
	if not enabled:
		return
	if server.is_connection_available():
		var peer := server.take_connection()
		if peer:
			peers.append(peer)
	var keep: Array = []
	for peer in peers:
		var tcp := peer as StreamPeerTCP
		tcp.poll()
		if tcp.get_status() != StreamPeerTCP.STATUS_CONNECTED:
			continue
		if tcp.get_available_bytes() > 0:
			var incoming := tcp.get_utf8_string(tcp.get_available_bytes())
			_handle(tcp, incoming)
		keep.append(tcp)
	peers = keep


func _handle(tcp: StreamPeerTCP, raw: String) -> void:
	var split := raw.split("\r\n\r\n", true, 1)
	var body := split[1] if split.size() > 1 else raw
	var parsed: Variant = JSON.parse_string(body)
	var response: Dictionary
	if typeof(parsed) != TYPE_DICTIONARY:
		response = _rpc_error(null, -32700, "Parse error")
	else:
		response = _dispatch(parsed)
	var payload := JSON.stringify(response)
	var http := "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s" % [payload.length(), payload]
	tcp.put_data(http.to_utf8_buffer())
	tcp.disconnect_from_host()


func _dispatch(req: Dictionary) -> Dictionary:
	var id: Variant = req.get("id", null)
	var method := str(req.get("method", ""))
	var params: Dictionary = req.get("params", {})
	if typeof(params) != TYPE_DICTIONARY:
		params = {}
	match method:
		"initialize":
			return _ok(id, {
				"protocolVersion": "2024-11-05",
				"serverInfo": {"name": "lumen-godot", "version": "1.0.0"},
				"capabilities": {"tools": {}},
			})
		"tools/list", "notifications/initialized":
			if method == "notifications/initialized":
				return _ok(id, {})
			var tools: Array = []
			for spec_name in registry.names():
				var spec := registry.get_tool(spec_name)
				tools.append({
					"name": spec.name,
					"description": spec.description,
					"inputSchema": spec.parameters,
				})
			return _ok(id, {"tools": tools})
		"tools/call":
			var name := str(params.get("name", ""))
			var arguments: Dictionary = params.get("arguments", {})
			if typeof(arguments) != TYPE_DICTIONARY:
				arguments = {}
			var result := registry.run(name, arguments)
			return _ok(id, {"content": [{"type": "text", "text": JSON.stringify(result)}]})
		_:
			return _rpc_error(id, -32601, "Unknown method %s" % method)


func _ok(id: Variant, result: Dictionary) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "result": result}


func _rpc_error(id: Variant, code: int, message: String) -> Dictionary:
	return {"jsonrpc": "2.0", "id": id, "error": {"code": code, "message": message}}

#!/usr/bin/env python3
"""stdio MCP client -> Lumen HTTP loopback.

Point Claude Code / Cursor / Codex at this script. Godot must be open with
Lumen MCP enabled (127.0.0.1:8765 by default).

  { "command": "python3", "args": ["addons/lumen/mcp/stdio_bridge.py"] }
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request

PORT = int(os.environ.get("LUMEN_MCP_PORT", "8765"))
URL = f"http://127.0.0.1:{PORT}/"


def post(payload: dict) -> dict:
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        URL,
        data=data,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw)
    except urllib.error.URLError as exc:
        return {
            "jsonrpc": "2.0",
            "id": payload.get("id"),
            "error": {
                "code": -32000,
                "message": f"Lumen MCP not reachable on {URL}: {exc}. Enable Local MCP in the dock.",
            },
        }


def main() -> None:
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except json.JSONDecodeError:
            continue
        out = post(req)
        sys.stdout.write(json.dumps(out) + "\n")
        sys.stdout.flush()


if __name__ == "__main__":
    main()

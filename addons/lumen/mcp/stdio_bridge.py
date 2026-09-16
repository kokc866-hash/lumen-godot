#!/usr/bin/env python3
"""stdio MCP <-> Lumen HTTP on 127.0.0.1.

Godot must be open, Lumen MCP enabled.

Claude Code / Cursor example:
  { "command": "python3", "args": ["addons/lumen/mcp/stdio_bridge.py"] }

Speaks newline JSON and Content-Length frames.
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
                "message": f"Lumen MCP not reachable on {URL}: {exc}. Enable MCP in the dock.",
            },
        }


def write_out(msg: dict, framed: bool) -> None:
    blob = json.dumps(msg)
    if framed:
        sys.stdout.write(f"Content-Length: {len(blob.encode('utf-8'))}\r\n\r\n{blob}")
    else:
        sys.stdout.write(blob + "\n")
    sys.stdout.flush()


def read_frames():
    buf = b""
    framed = None
    while True:
        chunk = sys.stdin.buffer.read(1)
        if not chunk:
            return
        buf += chunk
        if framed is None:
            if buf.startswith(b"Content-Length:") or buf.startswith(b"content-length:"):
                framed = True
            elif b"\n" in buf:
                framed = False
        if framed is False:
            if b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                text = line.decode("utf-8", "replace").strip()
                if text:
                    yield json.loads(text), False
        elif framed is True:
            header_end = buf.find(b"\r\n\r\n")
            if header_end < 0:
                continue
            header = buf[:header_end].decode("utf-8", "replace")
            length = 0
            for raw in header.split("\r\n"):
                if raw.lower().startswith("content-length:"):
                    length = int(raw.split(":", 1)[1].strip())
            body = buf[header_end + 4 :]
            if len(body) < length:
                rest = sys.stdin.buffer.read(length - len(body))
                if not rest:
                    return
                body += rest
            buf = body[length:]
            yield json.loads(body[:length].decode("utf-8")), True
            framed = None


def main() -> None:
    for req, framed in read_frames():
        if req.get("method", "").startswith("notifications/"):
            continue
        write_out(post(req), framed)


if __name__ == "__main__":
    main()

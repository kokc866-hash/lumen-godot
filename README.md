# Lumen

Local-first AI agent **inside** the Godot 4.2+ editor.

Lumen reads the project, edits scenes and scripts, playtests a scene, and can expose the same tools to an MCP client on `127.0.0.1`. It does **not** ship a subscription, an account, hosted models, telemetry, or a multiplayer relay.

Not affiliated with Ziva or Zivash Inc. This is original software.

## Install

1. Copy `addons/lumen` into your Godot project.
2. Project → Project Settings → Plugins → enable **Lumen**.
3. Open the **Lumen** dock on the right.

## Providers

- Ollama: `http://127.0.0.1:11434/v1`
- LM Studio: `http://127.0.0.1:1234/v1`
- OpenAI-compatible: your `/v1` endpoint + key in `user://lumen/secrets.json`
- Anthropic: official API + key

No Ziva account. No hosted multiplayer.

MIT. See LICENSE.

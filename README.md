# Lumen

Local-first AI agent **inside** the Godot 4.7+ editor.

Lumen reads the project, edits scenes and scripts, playtests a scene, and can expose the same tools to an MCP client on `127.0.0.1`. It does **not** ship a subscription, an account, hosted models, telemetry, or a multiplayer relay.

Not affiliated with Ziva or Zivash Inc. This is original software.

## Why this exists

A useful Godot agent needs the editor, not only files. Lumen keeps that part and drops the parts that lock you to a vendor:

| Capability | Lumen |
|---|---|
| Scene tree, nodes, files, TileMapLayer | yes |
| Plan mode + per-turn file undo | yes |
| Play current/custom scene + batch input sidecar | yes |
| Viewport screenshot | yes |
| Local models (Ollama / LM Studio) | yes |
| Your own OpenAI-compatible or Anthropic key | yes |
| Existing Codex / Claude Code CLI subscription | yes (local session) |
| MCP on localhost | yes |
| AGENTS.md + skills | yes |
| Hosted multiplayer relay | **no** |
| Paid seat / usage wallet | **no** |
| Closed native sidecar / bundled Chromium | **no** — GDScript only |

The improvement is not “more magic”. It is **auditable code, smaller install, keys that never leave your machine unless you point them at an API you chose**.

## Install

1. Copy `addons/lumen` into your Godot project.
2. Project → Project Settings → Plugins → enable **Lumen**.
3. Open the **Lumen** dock on the right.

Or clone this repository next to a project and symlink `addons/lumen`.

## Configure a model

Settings live in `res://.lumen/project.json`. The API key lives in `user://lumen/secrets.json` so it is **not** committed.

| Provider | Base URL | Key |
|---|---|---|
| Ollama | `http://127.0.0.1:11434/v1` | empty |
| LM Studio | `http://127.0.0.1:1234/v1` | empty |
| OpenAI-compatible | your endpoint `/v1` | your key |
| Anthropic | `https://api.anthropic.com` | `sk-ant-…` |

Ollama for a local agent. Lumen talks to Ollama over native `/api/chat` — the OpenAI `/v1` shim cannot set context size.

Current local coders (Qwen3.6 27B, Qwen3-Coder 30B) are **256k native**. Ollama’s own agent guidance is **at least 64k**. Lumen therefore asks for 64k, not the old 4k/32k VRAM-tier default.

| Setting | Default | Why |
|---|---|---|
| Context (`num_ctx`) | `65536` | Agent floor. Raise toward 128k/256k if `ollama ps` stays 100% GPU. |
| Keep alive | `-1` | Large-model reload costs minutes. Stay resident. |
| Max tokens | `4096` | Generation cap, not the window. |
| Compact tools | on | Core tools in the prompt. Extras via `list_more_tools`. |

**Test** loads the model with the current context so the first turn is not a cold start. **Models** asks the runtime for installed ids. **Stop** on the send button cancels an in-flight turn.

```bash
ollama pull qwen3.6:27b
```

`qwen3-coder:30b` is the coding-specialist alternative (~19 GB Q4, 256k). Drop Context to `32768` only when `ollama ps` shows CPU offload.

## Existing CLI subscriptions

Lumen can use an account you already pay for **if that vendor’s official CLI is logged in on this machine**. There is no Lumen account and no Ziva wallet.

| Button | Official CLI | Session file | What Lumen does |
|---|---|---|---|
| Login Codex | `codex login` | `~/.codex/auth.json` | ChatGPT Codex backend with that session |
| Login Claude | `claude /login` | `~/.claude/.credentials.json` | Anthropic Messages with the CLI OAuth token |
| Login Gemini | `gemini` | `~/.gemini/oauth_creds.json` | Detect / login only |

Install the CLI first, click **Login …**, finish the browser flow in the terminal, then **Scan** and **Use … session**.

Usage is billed by that provider. Tokens stay in the CLI files. Lumen does not copy them into the Godot project. `codex login` refresh writes back into `~/.codex/auth.json` the same way the CLI does.

Gemini login is detected, but inference still needs an API-compatible endpoint. Codex and Claude Code sessions run the agent loop directly.

## Commands

- `/new` new chat
- `/plan` plan mode on
- `/default` plan mode off
- `/model <id>` switch model
- `/undo` restore the last snapshot this agent wrote
- `/stop` cancel the in-flight request

`@res://path/to/file.gd` attaches that file to the next message.

Ctrl+Enter sends. Send becomes **Stop** while a turn is running.

## Plan mode and undo

Plan mode blocks write tools until you approve the plan.

Every turn snapshots files **before** a write. **Undo turn** copies those bytes back. It does not use git. It will not invent history that was never captured.

## Skills and AGENTS.md

Loaded in this order (first name wins):

- `res://.lumen/skills/<name>/SKILL.md`
- `res://.agents/skills/<name>/SKILL.md`
- `user://lumen/skills/<name>/SKILL.md`

Project instructions:

- `res://AGENTS.md` or `res://.lumen/AGENTS.md`

Skills can tell the agent to do anything the tools allow. Read them before you drop them into a project.

## Playtest

`playtest_batch` writes `res://.godot/lumen_playtest.json` and plays the scene.

To replay keys inside the running game, add `addons/lumen/playtest/harness.gd` as an Autoload named `LumenPlaytestIO`. If the sidecar is missing, the harness frees itself.

## MCP

Enable “Local MCP” in the dock. Lumen listens on `127.0.0.1:8765` only.

Point a client at that HTTP JSON-RPC endpoint. Methods: `initialize`, `tools/list`, `tools/call`. There is no hosted MCP URL.

## What Lumen will not do

- Talk to a billing API
- Upload your project for training
- Spin up a hosted relay or embed `user_id` / `game_id` into Project Settings
- Execute arbitrary GDScript inside the editor (on purpose: too easy to trash a project)

`generate_image` writes `res://assets/lumen/`. With `image_base_url` it calls an OpenAI-compatible `/images/generations` endpoint. Without it, Lumen writes a local placeholder PNG so the path exists.

## Layout

```
addons/lumen/
  plugin.gd              editor entry
  core/                  paths, settings, snapshots, skills
  providers/             OpenAI-compatible + Anthropic
  agent/                 tool registry + loop + plan mode
  tools/builtin_tools.gd editor actions
  playtest/harness.gd    optional runtime IO
  mcp/mcp_server.gd      localhost JSON-RPC
  ui/                    dock
```

## Requirements

Godot **4.7.1 or newer**. Uses the 4.7 `EditorDock` + `add_dock` API and the `EditorInterface` singleton. No extra native libraries.

## License

MIT. See `LICENSE`.

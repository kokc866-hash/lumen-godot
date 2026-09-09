# Lumen 1.7.3

Godot editor agent. Drop `addons/lumen` into a project, enable the plugin, restart.

## Fixes
- Parse-safe settings profiles (no read-only Dictionary write)
- CLI scan no longer spawns missing `claude`/`gemini --version`
- Model list works for Codex / Claude / Gemini CLI, not only HTTP APIs
- Cloud/subscription default max tokens 32768; local context default 131072 (Qwen 3.6/3.8: 262144)

## Chat / agent
- Queue messages while a turn runs
- Refresh system prompt every step (scene, selection, play state)
- Compact keeps tool pairs; drops whole old turns
- Auto-save chat with provider/model; search preview; Delete key removes a chat
- Retry once on timeout / 429

## Install
Delete old `addons/lumen`, unpack this tree, enable plugin, restart editor.

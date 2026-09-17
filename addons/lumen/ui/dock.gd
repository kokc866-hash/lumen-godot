@tool
extends Control

signal send_pressed(text: String, mentions: PackedStringArray)
signal new_chat
signal undo_pressed
signal approve_plan
signal reject_plan
signal settings_changed
signal cli_scan
signal cli_login(kind: String)
signal cli_use(kind: String)
signal test_pressed
signal stop_pressed
signal models_pressed
signal chat_open(id: String)
signal chat_delete(id: String)

const PROVIDERS := [
	{"id": "ollama", "label": "Ollama", "url": "http://127.0.0.1:11434/v1", "model": "qwen3.6:27b"},
	{"id": "lmstudio", "label": "LM Studio", "url": "http://127.0.0.1:1234/v1", "model": ""},
	{"id": "openai", "label": "OpenAI", "url": "https://api.openai.com/v1", "model": "gpt-4.1"},
	{"id": "anthropic", "label": "Anthropic", "url": "https://api.anthropic.com", "model": "claude-sonnet-4-5"},
	{"id": "custom", "label": "Custom", "url": "", "model": ""},
	{"id": "codex_cli", "label": "Codex CLI", "url": "", "model": "gpt-5.3-codex"},
	{"id": "claude_cli", "label": "Claude CLI", "url": "", "model": "claude-sonnet-4-5"},
	{"id": "gemini_cli", "label": "Gemini CLI", "url": "", "model": "gemini-2.5-flash"},
]

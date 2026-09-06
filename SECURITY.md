# Security

Lumen runs inside the Godot editor with access to the open project.

- The MCP server binds `127.0.0.1` only.
- Write tools stay inside `res://` and refuse `addons/lumen`.
- API keys are stored under `user://lumen/secrets.json`, not in the project.
- There is no execute-arbitrary-GDScript tool.
- Skills are instructions. Read them before enabling a skill pack.

Report issues via GitHub. Do not send project files unless you intend to.

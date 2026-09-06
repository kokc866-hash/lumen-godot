---
name: godot-conventions
description: Default Godot 4 style rules when writing or refactoring GDScript.
---

# Godot conventions

- Use typed GDScript (`:=`, argument and return types) on new code.
- Prefer signals over frame-polling when a node already emits the event.
- `_ready` for wiring, `_process` only when the value must change every frame.
- Keep scene-unique node names. Look up nodes with `%Unique` or exported NodePaths, not deep `get_node("A/B/C")` chains in new code.
- Do not attach new Autoloads unless the user asked for a singleton.

@tool
extends EditorPlugin

var _dock_scene: PackedScene

var dock: Control
var editor_dock: Node
var log: LumenLogger
var settings: LumenSettings
var snapshots: LumenSnapshotStore
var skills: LumenSkillLoader
var context: LumenContextBuilder
var registry: LumenToolRegistry
var builtins: LumenBuiltinTools
var plan: LumenPlanMode
var openai: LumenOpenAICompatible
var anthropic: LumenAnthropic
var cli_auth: LumenCliAuth
var codex: LumenCodexSubscription
var gemini: LumenGemini
var loop: LumenAgentLoop
var mcp: LumenMcpServer
var _debugger: EditorDebuggerPlugin

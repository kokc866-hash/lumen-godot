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

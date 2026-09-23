# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Small, deterministic action log shared by local saves, replays, and servers.

const CommandSchema = preload("res://rules/command_schema.gd")

static func append(log: Array, actor_team: int, kind: String, payload: Dictionary) -> Array:
	var next_log := log.duplicate(true)
	next_log.append({
		"sequence": next_log.size(),
		"team": actor_team,
		"kind": kind,
		"payload": payload.duplicate(true)
	})
	return next_log

static func validate(log: Array) -> String:
	for index in range(log.size()):
		if not (log[index] is Dictionary):
			return "INVALID ENTRY"
		var entry: Dictionary = log[index]
		if int(entry.get("sequence", -1)) != index:
			return "SEQUENCE GAP"
		var error := CommandSchema.validate_entry(entry)
		if not error.is_empty():
			return error
	return ""

static func encode(log: Array) -> String:
	return JSON.stringify(log)

static func decode(text: String) -> Array:
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Array else []

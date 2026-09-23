# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Small authoritative session facade for local play and a future network server.

const CommandLog = preload("res://rules/command_log.gd")
const CommandSchema = preload("res://rules/command_schema.gd")
const Replay = preload("res://rules/replay.gd")
const RulesetCatalog = preload("res://rules/ruleset_catalog.gd")
const TurnState = preload("res://rules/turn_state.gd")
const ModelState = preload("res://rules/model_state.gd")

const SCHEMA_VERSION := 1

static func create(models: Array, edition: int = 11, first_team: int = 0) -> Dictionary:
	var ruleset := RulesetCatalog.get_ruleset(edition)
	if ruleset.is_empty() or first_team not in [0, 1]:
		return {}
	return {
		"schema_version": SCHEMA_VERSION,
		"edition": edition,
		"ruleset_id": str(ruleset.get("id", "")),
		"round": 1,
		"active_team": first_team,
		"phase": "COMMAND",
		"phase_index": 0,
		"command_points": [0, 0],
		"models": models.duplicate(true),
		"command_log": [],
		"events": []
	}

static func submit(state: Dictionary, team: int, kind: String, payload: Dictionary) -> Dictionary:
	var snapshot_error := validate_snapshot(state)
	if not snapshot_error.is_empty():
		return {"ok": false, "reason": snapshot_error, "state": state}
	var entry := {"sequence": state.command_log.size(), "team": team, "kind": kind, "payload": payload.duplicate(true)}
	var contract_error := CommandSchema.validate_for_state(entry, state)
	if not contract_error.is_empty():
		return {"ok": false, "reason": contract_error, "state": state}
	var applied := Replay.apply_entry(state, entry)
	if not bool(applied.get("ok", false)):
		return applied
	var next: Dictionary = applied.state
	next.command_log = state.command_log.duplicate(true)
	next.command_log.append(entry)
	return {"ok": true, "reason": "", "entry": entry, "state": next}

static func advance_phase(state: Dictionary) -> Dictionary:
	var snapshot_error := validate_snapshot(state)
	if not snapshot_error.is_empty():
		return {"ok": false, "reason": snapshot_error, "state": state}
	var phase_state := {
		"round": int(state.round),
		"active_team": int(state.active_team),
		"phase": str(state.phase),
		"phase_index": int(state.phase_index),
		"command_points": state.command_points.duplicate(true)
	}
	var advanced := TurnState.advance(phase_state)
	return submit(state, int(state.active_team), "PHASE_ADVANCE", {"from": str(state.phase), "to": str(advanced.phase)})

static func validate_snapshot(state: Dictionary) -> String:
	for field in ["schema_version", "edition", "ruleset_id", "round", "active_team", "phase", "phase_index", "models", "command_log"]:
		if not state.has(field):
			return "MISSING " + field.to_upper()
	if int(state.schema_version) != SCHEMA_VERSION:
		return "UNSUPPORTED SNAPSHOT VERSION"
	var ruleset := RulesetCatalog.get_ruleset(int(state.edition))
	if ruleset.is_empty() or str(state.ruleset_id) != str(ruleset.get("id", "")):
		return "RULESET MISMATCH"
	if int(state.round) < 1 or int(state.active_team) not in [0, 1] or not (state.models is Array) or not (state.command_log is Array):
		return "INVALID SNAPSHOT"
	var model_errors := ModelState.validate_models(state.models)
	if not model_errors.is_empty():
		return model_errors[0]
	var phase_state := {"round": int(state.round), "active_team": int(state.active_team), "phase": str(state.phase), "phase_index": int(state.phase_index), "command_points": state.get("command_points", [0, 0])}
	if not TurnState.is_valid(phase_state):
		return "INVALID TURN STATE"
	return CommandLog.validate(state.command_log)

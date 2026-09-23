# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Deterministic command-log replay for local verification and future servers.

const CommandSchema = preload("res://rules/command_schema.gd")
const TurnState = preload("res://rules/turn_state.gd")

static func initial_state(models: Array, phase: String = "MOVEMENT", active_team: int = 0) -> Dictionary:
	return {"models": models.duplicate(true), "phase": phase, "phase_index": TurnState.phase_index(phase), "active_team": active_team, "round": 1, "command_points": [0, 0], "events": []}

static func apply_entry(state: Dictionary, entry: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	var kind := str(entry.get("kind", ""))
	var contract_error := CommandSchema.validate_for_state(entry, next)
	if not contract_error.is_empty():
		return {"ok": false, "reason": contract_error, "state": state}
	var payload: Dictionary = entry.payload
	match kind:
		"MOVE":
			var delta: Array = payload.delta
			var unit_id := str(payload.get("unit_id", ""))
			var found := false
			for model in next.models:
				if str(model.get("unit_id", "")) == unit_id:
					model.position += Vector2(float(delta[0]), float(delta[1]))
					found = true
			if not found:
				return {"ok": false, "reason": "UNKNOWN UNIT", "state": state}
		"CHARGE":
			var model_index := _index_for(next.models, payload, "model_id", "model")
			var destination: Array = payload.get("to", [])
			if model_index < 0 or model_index >= next.models.size():
				return {"ok": false, "reason": "INVALID CHARGE", "state": state}
			next.models[model_index].position = Vector2(float(destination[0]), float(destination[1]))
		"END_TURN":
			next.active_team = 1 - int(next.active_team)
			next.phase = "MOVEMENT"
			next.phase_index = TurnState.phase_index("MOVEMENT")
			next.round = int(next.round) + (1 if next.active_team == 0 else 0)
		"PHASE_ADVANCE":
			var phase_state := {
				"round": int(next.get("round", 1)),
				"active_team": int(next.get("active_team", 0)),
				"phase": str(next.get("phase", "")),
				"phase_index": int(next.get("phase_index", -1)),
				"command_points": next.get("command_points", [0, 0]).duplicate(true)
			}
			var advanced := TurnState.advance(phase_state)
			next.round = advanced.round
			next.active_team = advanced.active_team
			next.phase = advanced.phase
			next.phase_index = advanced.phase_index
			next.command_points = advanced.command_points.duplicate(true)
		"BATTLE_SHOCK":
			var unit_id := str(payload.get("unit_id", ""))
			var found := false
			for model in next.models:
				if str(model.get("unit_id", "")) == unit_id:
					model.battle_shocked = not bool(payload.get("passed", false))
					model.can_control = bool(payload.get("passed", false))
					found = true
			if not found:
				return {"ok": false, "reason": "UNKNOWN UNIT", "state": state}
		"SHOOT", "FIGHT":
			var target_index := _index_for(next.models, payload, "target_id", "target")
			var damage := int(payload.get("damage", -1))
			if target_index < 0 or target_index >= next.models.size():
				return {"ok": false, "reason": "INVALID DAMAGE EVENT", "state": state}
			var damage_result := _apply_damage(next.models[target_index], damage)
			if bool(damage_result.get("destroyed", false)):
				next.models.remove_at(target_index)
			else:
				next.models[target_index] = damage_result
		"HAZARDOUS":
			var attacker_index := _index_for(next.models, payload, "attacker_id", "attacker")
			var hazardous_damage := int(payload.get("damage", -1))
			if attacker_index < 0 or attacker_index >= next.models.size():
				return {"ok": false, "reason": "INVALID HAZARDOUS EVENT", "state": state}
			var hazardous_result := _apply_damage(next.models[attacker_index], hazardous_damage)
			if bool(hazardous_result.get("destroyed", false)):
				next.models.remove_at(attacker_index)
			else:
				next.models[attacker_index] = hazardous_result
		"STRATAGEM":
			pass
		_:
			return {"ok": false, "reason": "UNKNOWN COMMAND", "state": state}
	next.events.append(kind)
	return {"ok": true, "reason": "", "state": next}

static func _apply_damage(model: Dictionary, damage: int) -> Dictionary:
	var next := model.duplicate(true)
	next.wounds = maxi(0, int(next.get("wounds", 0)) - damage)
	if int(next.wounds) <= 0:
		next.destroyed = true
		next.can_control = false
	return next

static func _index_for(models: Array, payload: Dictionary, id_key: String, index_key: String) -> int:
	var model_id := str(payload.get(id_key, ""))
	if not model_id.is_empty():
		for index in range(models.size()):
			if str(models[index].get("model_id", "")) == model_id:
				return index
		return -1
	return int(payload.get(index_key, -1))

static func replay(initial: Dictionary, log: Array) -> Dictionary:
	var validation := _validate_sequence(log)
	if not validation.is_empty():
		return {"ok": false, "reason": validation, "state": initial}
	var state := initial.duplicate(true)
	for entry in log:
		var result := apply_entry(state, entry)
		if not result.ok:
			return result
		state = result.state
	return {"ok": true, "reason": "", "state": state}

static func _validate_sequence(log: Array) -> String:
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

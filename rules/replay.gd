# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Deterministic command-log replay for local verification and future servers.

const CommandSchema = preload("res://rules/command_schema.gd")

static func initial_state(models: Array, phase: String = "MOVEMENT", active_team: int = 0) -> Dictionary:
	return {"models": models.duplicate(true), "phase": phase, "active_team": active_team, "round": 1, "events": []}

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
			var model_index := int(payload.get("model", -1))
			var destination: Array = payload.get("to", [])
			if model_index >= next.models.size():
				return {"ok": false, "reason": "INVALID CHARGE", "state": state}
			next.models[model_index].position = Vector2(float(destination[0]), float(destination[1]))
		"END_TURN":
			next.active_team = 1 - int(next.active_team)
			next.phase = "MOVEMENT"
			next.round = int(next.round) + (1 if next.active_team == 0 else 0)
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
			var target_index := int(payload.get("target", -1))
			var damage := int(payload.get("damage", -1))
			if target_index >= next.models.size():
				return {"ok": false, "reason": "INVALID DAMAGE EVENT", "state": state}
			var damage_result := _apply_damage(next.models[target_index], damage)
			next.models[target_index] = damage_result
		"HAZARDOUS":
			var attacker_index := int(payload.get("attacker", -1))
			var hazardous_damage := int(payload.get("damage", -1))
			if attacker_index >= next.models.size():
				return {"ok": false, "reason": "INVALID HAZARDOUS EVENT", "state": state}
			next.models[attacker_index] = _apply_damage(next.models[attacker_index], hazardous_damage)
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

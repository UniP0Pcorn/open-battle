# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Deterministic command-log replay for local verification and future servers.

const CommandSchema = preload("res://rules/command_schema.gd")
const Engagement = preload("res://rules/engagement.gd")
const Stratagems = preload("res://rules/stratagems.gd")
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
	var reference_error := _validate_references(next.models, entry, kind, payload)
	if not reference_error.is_empty():
		return {"ok": false, "reason": reference_error, "state": state}
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
		"FALL_BACK":
			var fall_back_delta: Array = payload.delta
			var fall_back_unit_id := str(payload.get("unit_id", ""))
			var fall_back_found := false
			for model in next.models:
				if str(model.get("unit_id", "")) == fall_back_unit_id:
					model.position += Vector2(float(fall_back_delta[0]), float(fall_back_delta[1]))
					model.fell_back = true
					fall_back_found = true
			if not fall_back_found:
				return {"ok": false, "reason": "UNKNOWN UNIT", "state": state}
		"ADVANCE":
			var advance_unit_id := str(payload.get("unit_id", ""))
			var advance_roll := int(payload.get("roll", 0))
			var advanced_found := false
			for model in next.models:
				if str(model.get("unit_id", "")) == advance_unit_id:
					model.advanced = true
					model.advance_bonus = advance_roll
					advanced_found = true
			if not advanced_found:
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
			var points: Array = next.get("command_points", [0, 0]).duplicate(true)
			points[next.active_team] = mini(10, int(points[next.active_team]) + 1)
			next.command_points = points
			for model in next.models:
				if int(model.get("team", -1)) == int(next.active_team):
					model.spent = 0.0
					model.advanced = false
					model.advance_bonus = 0
					model.fell_back = false
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
			if str(next.phase) == "MOVEMENT":
				for model in next.models:
					if int(model.get("team", -1)) == int(next.active_team):
						model.spent = 0.0
						model.advanced = false
						model.advance_bonus = 0
						model.fell_back = false
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
			if bool(payload.get("one_shot", false)):
				var one_shot_attacker := _index_for(next.models, payload, "attacker_id", "attacker")
				var one_shot_name := str(payload.get("weapon", ""))
				if one_shot_attacker < 0 or one_shot_name.is_empty() or next.models[one_shot_attacker].get("used_weapon_names", []).has(one_shot_name):
					return {"ok": false, "reason": "ONE SHOT ALREADY USED", "state": state}
				var used_names: Array = next.models[one_shot_attacker].get("used_weapon_names", []).duplicate(true)
				used_names.append(one_shot_name)
				next.models[one_shot_attacker].used_weapon_names = used_names
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
			var stratagem_id := str(payload.get("id", ""))
			var stratagem: Dictionary = Stratagems.command_reroll() if stratagem_id == "command_reroll" else {}
			if stratagem.is_empty():
				return {"ok": false, "reason": "UNKNOWN STRATAGEM", "state": state}
			var stratagem_result := Stratagems.use(stratagem, str(next.phase), int(entry.team), next.get("command_points", [0, 0]))
			if not bool(stratagem_result.get("ok", false)):
				return {"ok": false, "reason": str(stratagem_result.get("reason", "STRATAGEM REJECTED")), "state": state}
			next.command_points = stratagem_result.points
		_:
			return {"ok": false, "reason": "UNKNOWN COMMAND", "state": state}
	next.events.append(kind)
	return {"ok": true, "reason": "", "state": next}

static func _validate_references(models: Array, entry: Dictionary, kind: String, payload: Dictionary) -> String:
	var actor_team := int(entry.get("team", -1))
	match kind:
		"MOVE", "FALL_BACK":
			var found := false
			for model in models:
				if str(model.get("unit_id", "")) == str(payload.get("unit_id", "")):
					found = true
					if int(model.get("team", -1)) != actor_team:
						return "NOT ACTIVE TEAM"
			if not found:
				return "UNKNOWN UNIT"
			return _movement_reference_error(models, str(payload.get("unit_id", "")), payload.delta, str(kind) == "FALL_BACK")
		"ADVANCE", "FALL_BACK":
			var advance_found := false
			for model in models:
				if str(model.get("unit_id", "")) == str(payload.get("unit_id", "")):
					advance_found = true
					if int(model.get("team", -1)) != actor_team:
						return "NOT ACTIVE TEAM"
			return "" if advance_found else "UNKNOWN UNIT"
		"CHARGE":
			var charger := _index_for(models, payload, "model_id", "model")
			var charge_target := _index_for(models, payload, "target_id", "target")
			if charger < 0 or charger >= models.size() or charge_target < 0 or charge_target >= models.size():
				return "INVALID CHARGE"
			if int(models[charger].get("team", -1)) != actor_team:
				return "NOT ACTIVE TEAM"
			if int(models[charge_target].get("team", -1)) == actor_team:
				return "FRIENDLY TARGET"
		"SHOOT", "FIGHT":
			var attacker := _index_for(models, payload, "attacker_id", "attacker")
			var target := _index_for(models, payload, "target_id", "target")
			if attacker < 0 or attacker >= models.size() or target < 0 or target >= models.size() or attacker == target:
				return "INVALID DAMAGE EVENT"
			if int(models[attacker].get("team", -1)) != actor_team:
				return "NOT ACTIVE TEAM"
			if int(models[target].get("team", -1)) == actor_team:
				return "FRIENDLY TARGET"
			if bool(payload.get("one_shot", false)):
				if str(payload.get("weapon", "")).is_empty():
					return "INVALID DAMAGE EVENT"
				if models[attacker].get("used_weapon_names", []).has(str(payload.get("weapon", ""))):
					return "ONE SHOT ALREADY USED"
		"HAZARDOUS":
			var hazardous_attacker := _index_for(models, payload, "attacker_id", "attacker")
			if hazardous_attacker < 0 or hazardous_attacker >= models.size():
				return "INVALID HAZARDOUS EVENT"
			if int(models[hazardous_attacker].get("team", -1)) != actor_team:
				return "NOT ACTIVE TEAM"
		"BATTLE_SHOCK":
			var found_unit := false
			for model in models:
				if str(model.get("unit_id", "")) == str(payload.get("unit_id", "")):
					found_unit = true
					if int(model.get("team", -1)) != actor_team:
						return "NOT ACTIVE TEAM"
			return "" if found_unit else "UNKNOWN UNIT"
	return ""

static func _apply_damage(model: Dictionary, damage: int) -> Dictionary:
	var next := model.duplicate(true)
	next.wounds = maxi(0, int(next.get("wounds", 0)) - damage)
	if int(next.wounds) <= 0:
		next.destroyed = true
		next.can_control = false
	return next

static func _movement_reference_error(models: Array, unit_id: String, delta: Array, falling_back: bool) -> String:
	var unit_models: Array = []
	var enemies: Array = []
	var unit_team := -1
	for model in models:
		if str(model.get("unit_id", "")) == unit_id:
			unit_models.append(model)
			unit_team = int(model.get("team", -1))
	for model in models:
		if int(model.get("team", -1)) != unit_team:
			enemies.append(model)
	var engaged := false
	var remains_engaged := false
	var movement_delta := Vector2(float(delta[0]), float(delta[1]))
	for model in unit_models:
		for enemy in enemies:
			if Engagement.in_engagement(model, enemy):
				engaged = true
			var moved: Dictionary = model.duplicate(true)
			moved.position = model.position + movement_delta
			if Engagement.in_engagement(moved, enemy):
				remains_engaged = true
	if falling_back:
		if not engaged:
			return "UNIT NOT ENGAGED"
		return "FALL BACK MUST END OUT OF ENGAGEMENT" if remains_engaged else ""
	if engaged:
		return "ENGAGED UNIT MUST FALL BACK"
	return "CANNOT END IN ENGAGEMENT" if remains_engaged else ""

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

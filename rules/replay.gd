# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Deterministic command-log replay for local verification and future servers.

const CommandSchema = preload("res://rules/command_schema.gd")
const Charge = preload("res://rules/charge.gd")
const Combat = preload("res://rules/combat.gd")
const Damage = preload("res://rules/damage.gd")
const Engagement = preload("res://rules/engagement.gd")
const Melee = preload("res://rules/melee.gd")
const Movement = preload("res://rules/movement.gd")
const Stratagems = preload("res://rules/stratagems.gd")
const TurnState = preload("res://rules/turn_state.gd")
const UnitAbilities = preload("res://rules/unit_abilities.gd")
const Reserves = preload("res://rules/reserves.gd")
const Transports = preload("res://rules/transports.gd")
const Attachments = preload("res://rules/attachments.gd")
const WeaponRules = preload("res://rules/weapon_rules.gd")
const MissionRules = preload("res://rules/mission.gd")

static func initial_state(models: Array, phase: String = "MOVEMENT", active_team: int = 0, terrain: Array = [], objectives: Array = [], control_radius: float = 3.0, score_to_win: int = 5) -> Dictionary:
	var initial_models: Array = models.duplicate(true)
	for model in initial_models:
		if not model.has("reserve_status"):
			model.reserve_status = Reserves.DEPLOYED
	if phase == "FIGHT":
		for model in initial_models:
			model.fought = false
	return {"models": initial_models, "phase": phase, "phase_index": TurnState.phase_index(phase), "active_team": active_team, "round": 1, "command_points": [0, 0], "terrain": terrain.duplicate(true), "objectives": objectives.duplicate(true), "control_radius": control_radius, "score_to_win": score_to_win, "score": [0, 0], "winner": -1, "stratagem_effects": [], "events": []}

static func apply_entry(state: Dictionary, entry: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	var kind := str(entry.get("kind", ""))
	var contract_error := CommandSchema.validate_for_state(entry, next)
	if not contract_error.is_empty():
		return {"ok": false, "reason": contract_error, "state": state}
	if kind == "SCOUT" and int(next.get("round", 1)) != 1:
		return {"ok": false, "reason": "SCOUT WINDOW CLOSED", "state": state}
	var payload: Dictionary = entry.payload
	var reference_error := _validate_references(next.models, entry, kind, payload, next.get("terrain", []), next.get("stratagem_effects", []))
	if not reference_error.is_empty():
		return {"ok": false, "reason": reference_error, "state": state}
	match kind:
		"REACTION_PASS":
			next.erase("reaction_window")
		"MOVE":
			var delta: Array = payload.delta
			var unit_id := str(payload.get("unit_id", ""))
			var move_distance := Vector2(float(delta[0]), float(delta[1])).length()
			var found := false
			for model in next.models:
				if Attachments.group_id(model) == unit_id:
					model.position += Vector2(float(delta[0]), float(delta[1]))
					model.spent = float(model.get("spent", 0.0)) + move_distance
					found = true
			if not found:
				return {"ok": false, "reason": "UNKNOWN UNIT", "state": state}
		"FALL_BACK":
			var fall_back_delta: Array = payload.delta
			var fall_back_unit_id := str(payload.get("unit_id", ""))
			var fall_back_distance := Vector2(float(fall_back_delta[0]), float(fall_back_delta[1])).length()
			var fall_back_found := false
			for model in next.models:
				if Attachments.group_id(model) == fall_back_unit_id:
					model.position += Vector2(float(fall_back_delta[0]), float(fall_back_delta[1]))
					model.spent = float(model.get("spent", 0.0)) + fall_back_distance
					model.fell_back = true
					fall_back_found = true
			if not fall_back_found:
				return {"ok": false, "reason": "UNKNOWN UNIT", "state": state}
		"ADVANCE":
			var advance_unit_id := str(payload.get("unit_id", ""))
			var advance_roll := int(payload.get("roll", 0))
			var advanced_found := false
			for model in next.models:
				if Attachments.group_id(model) == advance_unit_id:
					model.advanced = true
					model.advance_bonus = advance_roll
					advanced_found = true
			if not advanced_found:
				return {"ok": false, "reason": "UNKNOWN UNIT", "state": state}
		"DEPLOY_RESERVE":
			var reserve_unit_id := str(payload.get("unit_id", ""))
			var positions: Array = payload.get("positions", [])
			var reserve_error := Reserves.arrival_reason(next.models, reserve_unit_id, int(entry.team), positions)
			if not reserve_error.is_empty():
				return {"ok": false, "reason": reserve_error, "state": state}
			var position_index := 0
			for model in next.models:
				if str(model.get("unit_id", "")) != reserve_unit_id:
					continue
				var destination: Array = positions[position_index]
				model.position = Vector2(float(destination[0]), float(destination[1]))
				model.reserve_status = Reserves.DEPLOYED
				model.spent = 0.0
				model.advanced = false
				model.advance_bonus = 0
				model.fell_back = false
				position_index += 1
		"SCOUT":
			var scout_unit_id := str(payload.get("unit_id", ""))
			var scout_delta: Array = payload.get("delta", [])
			var scout_vector := Vector2(float(scout_delta[0]), float(scout_delta[1]))
			for model in next.models:
				if Attachments.group_id(model) == scout_unit_id:
					model.position += scout_vector
					model.scouted = true
		"ATTACH":
			var leader_unit_id := str(payload.get("leader_unit_id", ""))
			var bodyguard_unit_id := str(payload.get("bodyguard_unit_id", ""))
			for model in next.models:
				if str(model.get("unit_id", "")) == leader_unit_id:
					model.attached_to = bodyguard_unit_id
				if str(model.get("unit_id", "")) == bodyguard_unit_id:
					model.attached_leader_id = leader_unit_id
		"DETACH":
			var detach_leader_id := str(payload.get("leader_unit_id", ""))
			var detach_bodyguard_id := ""
			for model in next.models:
				if str(model.get("unit_id", "")) == detach_leader_id:
					detach_bodyguard_id = str(model.get("attached_to", ""))
			for model in next.models:
				if str(model.get("unit_id", "")) == detach_leader_id:
					model.attached_to = ""
				if not detach_bodyguard_id.is_empty() and str(model.get("unit_id", "")) == detach_bodyguard_id:
					model.attached_leader_id = ""
		"EMBARK":
			var embark_unit_id := str(payload.get("unit_id", ""))
			var embark_transport_id := str(payload.get("transport_id", ""))
			for model in next.models:
				if Attachments.group_id(model) == embark_unit_id:
					model.embarked_in = embark_transport_id
					model.spent = 0.0
					model.advanced = false
					model.advance_bonus = 0
					model.fell_back = false
		"DISEMBARK":
			var disembark_unit_id := str(payload.get("unit_id", ""))
			var disembark_positions: Array = payload.get("positions", [])
			var disembark_index := 0
			for model in next.models:
				if Attachments.group_id(model) != disembark_unit_id or not Transports.is_embarked(model):
					continue
				var disembark_destination: Array = disembark_positions[disembark_index]
				model.position = Vector2(float(disembark_destination[0]), float(disembark_destination[1]))
				model.embarked_in = ""
				model.spent = 0.0
				model.disembarked = true
				disembark_index += 1
		"TRANSPORT_MOVE":
			var transport_id := str(payload.get("transport_id", ""))
			var transport_delta: Array = payload.get("delta", [])
			var transport_vector := Vector2(float(transport_delta[0]), float(transport_delta[1]))
			for model in next.models:
				if str(model.get("model_id", "")) == transport_id or str(model.get("embarked_in", "")) == transport_id:
					model.position += transport_vector
					if str(model.get("model_id", "")) == transport_id:
						model.spent = float(model.get("spent", 0.0)) + transport_vector.length()
						model.transport_moved = true
		"CHARGE":
			var model_index := _index_for(next.models, payload, "model_id", "model")
			var destination: Array = payload.get("to", [])
			if model_index < 0 or model_index >= next.models.size():
				return {"ok": false, "reason": "INVALID CHARGE", "state": state}
			next.models[model_index].position = Vector2(float(destination[0]), float(destination[1]))
			var charged_unit_id := Attachments.group_id(next.models[model_index])
			for charged_model in next.models:
				if Attachments.group_id(charged_model) == charged_unit_id:
					charged_model.charged = true
		"END_TURN":
			_expire_grants(next.models, ["PHASE", "TURN"])
			var objective_data: Array = next.get("objectives", []).duplicate(true)
			if not objective_data.is_empty():
				var scored := MissionRules.score_objectives(objective_data, next.models, float(next.get("control_radius", 3.0)))
				var score: Array = next.get("score", [0, 0]).duplicate(true)
				for score_team in range(mini(score.size(), scored.score.size())):
					score[score_team] = int(score[score_team]) + int(scored.score[score_team])
				next.score = score
				next.winner = MissionRules.winner(score, int(next.get("score_to_win", 5)))
			next.active_team = 1 - int(next.active_team)
			next.phase = "COMMAND"
			next.phase_index = TurnState.phase_index("COMMAND")
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
					model.charged = false
					model.erase("temporary_cover_bonus")
					model.transport_moved = false
					model.disembarked = false
		"PHASE_ADVANCE":
			_expire_grants(next.models, ["PHASE", "TURN"] if str(next.phase) == "FIGHT" else ["PHASE"])
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
						model.charged = false
						model.erase("temporary_cover_bonus")
						model.transport_moved = false
						model.disembarked = false
			if str(next.phase) == "FIGHT":
				for model in next.models:
					if int(model.get("team", -1)) == int(next.active_team):
						model.fought = false
		"BATTLE_SHOCK":
			var unit_id := str(payload.get("unit_id", ""))
			if _has_active_effect(next.get("stratagem_effects", []), "PASS_BATTLE_SHOCK", int(entry.team), unit_id) and not bool(payload.get("passed", false)):
				return {"ok": false, "reason": "STRATAGEM REQUIRES PASS", "state": state}
			var found := false
			for model in next.models:
				if Attachments.group_id(model) == unit_id:
					model.battle_shocked = not bool(payload.get("passed", false))
					model.can_control = bool(payload.get("passed", false))
					found = true
			if not found:
				return {"ok": false, "reason": "UNKNOWN UNIT", "state": state}
			for effect in next.get("stratagem_effects", []):
				var effect_payload: Variant = effect.get("payload", {}) if effect is Dictionary else {}
				if effect is Dictionary and str(effect.get("effect", "")) == "PASS_BATTLE_SHOCK" and int(effect.get("team", -1)) == int(entry.team) and effect_payload is Dictionary and str(effect_payload.get("unit_id", "")) == unit_id:
					effect.consumed = true
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
			var damage_result := _apply_damage(next.models[target_index], damage, payload.get("feel_no_pain_rolls", []))
			if bool(damage_result.get("destroyed", false)):
				next.models.remove_at(target_index)
			else:
				next.models[target_index] = damage_result
			var hazardous_damage := int(payload.get("hazardous_damage", 0))
			if hazardous_damage > 0:
				var hazardous_attacker_index := _index_for(next.models, payload, "attacker_id", "attacker")
				if hazardous_attacker_index < 0 or hazardous_attacker_index >= next.models.size():
					return {"ok": false, "reason": "INVALID HAZARDOUS EVENT", "state": state}
				var hazardous_result := _apply_damage(next.models[hazardous_attacker_index], hazardous_damage, payload.get("hazardous_feel_no_pain_rolls", []))
				if bool(hazardous_result.get("destroyed", false)):
					next.models.remove_at(hazardous_attacker_index)
				else:
					next.models[hazardous_attacker_index] = hazardous_result
			if kind == "FIGHT":
				var fought_attacker_index := _index_for(next.models, payload, "attacker_id", "attacker")
				if fought_attacker_index >= 0 and fought_attacker_index < next.models.size():
					var fought_unit_id := Attachments.group_id(next.models[fought_attacker_index])
					for model in next.models:
						if Attachments.group_id(model) == fought_unit_id:
							model.fought = true
				for effect in next.get("stratagem_effects", []):
					if effect is Dictionary and str(effect.get("effect", "")) == "FIGHT_NEXT" and int(effect.get("team", -1)) == int(entry.team) and not bool(effect.get("consumed", false)):
						effect.consumed = true
			for effect in next.get("stratagem_effects", []):
				if effect is Dictionary and str(effect.get("effect", "")) == "REROLL_HIT" and int(effect.get("team", -1)) == int(entry.team) and not bool(effect.get("consumed", false)):
					effect.consumed = true
					break
		"HAZARDOUS":
			var attacker_index := _index_for(next.models, payload, "attacker_id", "attacker")
			var hazardous_damage := int(payload.get("damage", -1))
			if attacker_index < 0 or attacker_index >= next.models.size():
				return {"ok": false, "reason": "INVALID HAZARDOUS EVENT", "state": state}
			var hazardous_result := _apply_damage(next.models[attacker_index], hazardous_damage, payload.get("feel_no_pain_rolls", []))
			if bool(hazardous_result.get("destroyed", false)):
				next.models.remove_at(attacker_index)
			else:
				next.models[attacker_index] = hazardous_result
		"STRATAGEM":
			var stratagem_id := str(payload.get("id", ""))
			var stratagem: Dictionary = _stratagem_for(next, int(entry.team), stratagem_id)
			if stratagem.is_empty():
				return {"ok": false, "reason": "UNKNOWN STRATAGEM", "state": state}
			var window: Dictionary = next.get("reaction_window", {})
			if not window.is_empty():
				if str(stratagem.timing) != str(window.get("timing", "")) or stratagem_id not in window.get("stratagem_ids", []):
					return {"ok": false, "reason": "INVALID REACTION STRATAGEM", "state": state}
			elif str(stratagem.get("timing", "")) == "AFTER_ENEMY_MOVE":
				return {"ok": false, "reason": "REACTION WINDOW REQUIRED", "state": state}
			var stratagem_result := Stratagems.use(stratagem, str(next.phase), int(entry.team), next.get("command_points", [0, 0]))
			if not bool(stratagem_result.get("ok", false)):
				return {"ok": false, "reason": str(stratagem_result.get("reason", "STRATAGEM REJECTED")), "state": state}
			var effect_id := str(stratagem_result.get("effect", ""))
			if effect_id == "GRANT_ABILITY":
				var grant_unit := str(payload.get("unit_id", ""))
				var recipients: Array = []
				if grant_unit.is_empty():
					return {"ok": false, "reason": "UNIT REQUIRED", "state": state}
				for model in next.models:
					if Attachments.group_id(model) != grant_unit:
						continue
					if int(model.get("team", -1)) != int(entry.team):
						return {"ok": false, "reason": "NOT ACTIVE TEAM", "state": state}
					if not Reserves.active(model) or Transports.is_embarked(model):
						return {"ok": false, "reason": "TARGET NOT DEPLOYED", "state": state}
					recipients.append(model)
				if recipients.is_empty():
					return {"ok": false, "reason": "UNKNOWN UNIT", "state": state}
				for model in recipients:
					var abilities: Array = model.get("ability_ids", []).duplicate(true)
					var grants: Dictionary = model.get("ability_grants", {}).duplicate(true)
					var ability_id := str(stratagem.ability)
					if not grants.has(ability_id):
						grants[ability_id] = {"native": abilities.has(ability_id), "durations": []}
					var duration := str(stratagem.duration)
					if not grants[ability_id].durations.has(duration):
						grants[ability_id].durations.append(duration)
					model.ability_grants = grants
					if not abilities.has(stratagem.ability):
						abilities.append(stratagem.ability)
					model.ability_ids = abilities
			if effect_id in ["TEMPORARY_COVER", "PASS_BATTLE_SHOCK"]:
				var effect_unit_id := str(payload.get("unit_id", ""))
				if effect_unit_id.is_empty():
					return {"ok": false, "reason": "UNIT REQUIRED", "state": state}
				var effect_unit_found := false
				for model in next.models:
					if Attachments.group_id(model) != effect_unit_id:
						continue
					if int(model.get("team", -1)) != int(entry.team):
						return {"ok": false, "reason": "NOT ACTIVE TEAM", "state": state}
					effect_unit_found = true
					if effect_id == "TEMPORARY_COVER":
						model.temporary_cover_bonus = maxi(1, int(model.get("temporary_cover_bonus", 0)))
				if not effect_unit_found:
					return {"ok": false, "reason": "UNKNOWN UNIT", "state": state}
			next.command_points = stratagem_result.points
			var effects: Array = next.get("stratagem_effects", []).duplicate(true)
			effects.append({
				"sequence": int(entry.get("sequence", -1)),
				"team": int(entry.team),
				"id": str(stratagem_result.get("stratagem_id", stratagem.id)),
				"effect": str(stratagem_result.get("effect", "")),
				"timing": str(stratagem_result.get("timing", "")),
				"round": int(next.get("round", 1)),
				"phase": str(next.get("phase", "")),
				"consumed": effect_id == "GRANT_ABILITY",
				"payload": payload.duplicate(true)
			})
			next.stratagem_effects = effects
			next.erase("reaction_window")
		_:
			return {"ok": false, "reason": "UNKNOWN COMMAND", "state": state}
	if kind in ["MOVE", "FALL_BACK"] and Vector2(float(payload.delta[0]), float(payload.delta[1])).length() > 0.00001:
		_open_move_reaction(next, entry)
	next.events.append(kind)
	return {"ok": true, "reason": "", "state": next}

static func _expire_grants(models: Array, expired: Array) -> void:
	for model in models:
		var grants: Dictionary = model.get("ability_grants", {})
		for ability_id in grants.keys():
			var grant: Dictionary = grants[ability_id]
			for duration in expired:
				grant.durations.erase(duration)
			if grant.durations.is_empty():
				if not bool(grant.native):
					model.ability_ids.erase(ability_id)
				grants.erase(ability_id)
		if grants.is_empty():
			model.erase("ability_grants")

static func _open_move_reaction(state: Dictionary, entry: Dictionary) -> void:
	var responder := 1 - int(entry.team)
	var available: Array = []
	for model in state.models:
		if int(model.get("team", -1)) != responder or not Reserves.active(model) or Transports.is_embarked(model):
			continue
		for definition in model.get("faction_stratagems", []):
			if not (definition is Dictionary) or not Stratagems.validate(definition).is_empty():
				continue
			if str(definition.timing) != "AFTER_ENEMY_MOVE" or int(definition.cost) > int(state.get("command_points", [0, 0])[responder]):
				continue
			if not available.has(str(definition.id)):
				available.append(str(definition.id))
	if not available.is_empty():
		state.reaction_window = {"id": "move:%d" % int(entry.sequence), "team": responder, "timing": "AFTER_ENEMY_MOVE", "trigger_unit_id": str(entry.payload.unit_id), "stratagem_ids": available}

static func _validate_references(models: Array, entry: Dictionary, kind: String, payload: Dictionary, terrain: Array = [], effects: Array = []) -> String:
	var actor_team := int(entry.get("team", -1))
	match kind:
		"MOVE", "FALL_BACK":
			var found := false
			for model in models:
				if Attachments.group_id(model) == str(payload.get("unit_id", "")):
					if Transports.is_embarked(model):
						return "UNIT EMBARKED"
					if Reserves.in_reserve(model):
						return "UNIT IN RESERVE"
					found = true
					if int(model.get("team", -1)) != actor_team:
						return "NOT ACTIVE TEAM"
			if not found:
				return "UNKNOWN UNIT"
			return _movement_reference_error(models, str(payload.get("unit_id", "")), payload.delta, str(kind) == "FALL_BACK", terrain)
		"ADVANCE":
			var advance_found := false
			for model in models:
				if Attachments.group_id(model) == str(payload.get("unit_id", "")):
					if Transports.is_embarked(model):
						return "UNIT EMBARKED"
					if Reserves.in_reserve(model):
						return "UNIT IN RESERVE"
					advance_found = true
					if int(model.get("team", -1)) != actor_team:
						return "NOT ACTIVE TEAM"
			if not advance_found:
				return "UNKNOWN UNIT"
			return _advance_reference_error(models, str(payload.get("unit_id", "")))
		"DEPLOY_RESERVE":
			return Reserves.arrival_reason(models, str(payload.get("unit_id", "")), actor_team, payload.get("positions", []))
		"SCOUT":
			return _scout_reference_error(models, str(payload.get("unit_id", "")), payload.delta, actor_team)
		"ATTACH":
			return Attachments.attach_reason(models, str(payload.get("leader_unit_id", "")), str(payload.get("bodyguard_unit_id", "")), actor_team)
		"DETACH":
			return Attachments.detach_reason(models, str(payload.get("leader_unit_id", "")), actor_team)
		"EMBARK":
			return Transports.embark_reason(models, str(payload.get("unit_id", "")), str(payload.get("transport_id", "")), actor_team)
		"DISEMBARK":
			return Transports.disembark_reason(models, str(payload.get("unit_id", "")), payload.get("positions", []), actor_team)
		"TRANSPORT_MOVE":
			return Transports.move_reason(models, str(payload.get("transport_id", "")), payload.get("delta", []), actor_team, terrain)
		"CHARGE":
			var charger := _index_for(models, payload, "model_id", "model")
			var charge_target := _index_for(models, payload, "target_id", "target")
			if charger < 0 or charger >= models.size() or charge_target < 0 or charge_target >= models.size():
				return "INVALID CHARGE"
			if Reserves.in_reserve(models[charger]) or Reserves.in_reserve(models[charge_target]):
				return "UNIT IN RESERVE"
			if Transports.is_embarked(models[charger]) or Transports.is_embarked(models[charge_target]):
				return "UNIT EMBARKED"
			if int(models[charger].get("team", -1)) != actor_team:
				return "NOT ACTIVE TEAM"
			if int(models[charge_target].get("team", -1)) == actor_team:
				return "FRIENDLY TARGET"
			return _charge_reference_error(models, charger, charge_target, payload, terrain)
		"SHOOT", "FIGHT":
			var attacker := _index_for(models, payload, "attacker_id", "attacker")
			var target := _index_for(models, payload, "target_id", "target")
			if attacker < 0 or attacker >= models.size() or target < 0 or target >= models.size() or attacker == target:
				return "INVALID DAMAGE EVENT"
			if Reserves.in_reserve(models[attacker]) or Reserves.in_reserve(models[target]):
				return "UNIT IN RESERVE"
			if Transports.is_embarked(models[attacker]) or Transports.is_embarked(models[target]):
				return "UNIT EMBARKED"
			if int(models[attacker].get("team", -1)) != actor_team:
				return "NOT ACTIVE TEAM"
			if int(models[target].get("team", -1)) == actor_team:
				return "FRIENDLY TARGET"
			var weapon_error := _attack_reference_error(models, attacker, target, payload, kind, actor_team)
			if not weapon_error.is_empty():
				return weapon_error
			var fnp_error := _feel_no_pain_reference_error(models[target], int(payload.get("damage", 0)), payload)
			if not fnp_error.is_empty():
				return fnp_error
			var hazardous_damage := int(payload.get("hazardous_damage", 0))
			if hazardous_damage > 0:
				var hazardous_fnp_error := _feel_no_pain_reference_error(models[attacker], hazardous_damage, payload, "hazardous_feel_no_pain_rolls")
				if not hazardous_fnp_error.is_empty():
					return hazardous_fnp_error
			if bool(payload.get("one_shot", false)):
				if str(payload.get("weapon", "")).is_empty():
					return "INVALID DAMAGE EVENT"
				if models[attacker].get("used_weapon_names", []).has(str(payload.get("weapon", ""))):
					return "ONE SHOT ALREADY USED"
			if kind == "FIGHT" and _group_fought(models, Attachments.group_id(models[attacker])):
				return "UNIT ALREADY FOUGHT"
			if kind == "FIGHT" and _fights_first_blocked(models, attacker, effects, actor_team):
				return "FIGHTS FIRST UNIT MUST ACTIVATE"
		"HAZARDOUS":
			var hazardous_attacker := _index_for(models, payload, "attacker_id", "attacker")
			if hazardous_attacker < 0 or hazardous_attacker >= models.size():
				return "INVALID HAZARDOUS EVENT"
			if Reserves.in_reserve(models[hazardous_attacker]):
				return "UNIT IN RESERVE"
			if Transports.is_embarked(models[hazardous_attacker]):
				return "UNIT EMBARKED"
			if int(models[hazardous_attacker].get("team", -1)) != actor_team:
				return "NOT ACTIVE TEAM"
			var hazardous_fnp_error := _feel_no_pain_reference_error(models[hazardous_attacker], int(payload.get("damage", 0)), payload)
			if not hazardous_fnp_error.is_empty():
				return hazardous_fnp_error
		"BATTLE_SHOCK":
			var found_unit := false
			for model in models:
				if Attachments.group_id(model) == str(payload.get("unit_id", "")) and not Reserves.in_reserve(model) and not Transports.is_embarked(model):
					found_unit = true
					if int(model.get("team", -1)) != actor_team:
						return "NOT ACTIVE TEAM"
			if not found_unit:
				return "UNKNOWN UNIT"
			return _battle_shock_reference_error(models, str(payload.get("unit_id", "")), payload)
	return ""

static func _apply_damage(model: Dictionary, damage: int, feel_no_pain_rolls: Array = []) -> Dictionary:
	var next := model.duplicate(true)
	var result := Damage.apply_to_model(next, damage, feel_no_pain_rolls)
	next.wounds = int(result.wounds_after)
	next.last_damage = int(result.damage)
	next.feel_no_pain_ignored = int(result.feel_no_pain_ignored)
	if int(next.wounds) <= 0:
		next.destroyed = true
		next.can_control = false
	return next

static func _movement_reference_error(models: Array, unit_id: String, delta: Array, falling_back: bool, terrain: Array = []) -> String:
	var unit_models: Array = []
	var enemies: Array = []
	var unit_team := -1
	for model in models:
		if Attachments.group_id(model) == unit_id and not Reserves.in_reserve(model) and not Transports.is_embarked(model):
			unit_models.append(model)
			unit_team = int(model.get("team", -1))
	for model in models:
		if int(model.get("team", -1)) != unit_team and not Reserves.in_reserve(model) and not Transports.is_embarked(model):
			enemies.append(model)
	var engaged := false
	var remains_engaged := false
	var movement_delta := Vector2(float(delta[0]), float(delta[1]))
	var movement_distance := movement_delta.length()
	var external_models: Array = []
	for model in models:
		if Attachments.group_id(model) != unit_id and not Reserves.in_reserve(model) and not Transports.is_embarked(model):
			external_models.append(model)
	for model in unit_models:
		if bool(model.get("fell_back", false)):
			return "FELL BACK"
		var allowance := float(model.get("movement_inches", INF))
		if bool(model.get("advanced", false)):
			allowance += float(model.get("advance_bonus", 0))
		if not is_inf(allowance) and float(model.get("spent", 0.0)) + movement_distance > allowance + Engagement.EPSILON:
			return "MOVE LIMIT EXCEEDED"
		var origin := _position_of(model)
		var destination := origin + movement_delta
		var path_error := Movement.movement_reason_for_model(model, destination, allowance, external_models, -1, terrain)
		if not path_error.is_empty():
			return path_error
		for enemy in enemies:
			if Engagement.in_engagement(model, enemy):
				engaged = true
			var moved: Dictionary = model.duplicate(true)
			moved.position = destination
			if Engagement.in_engagement(moved, enemy):
				remains_engaged = true
	if falling_back:
		if not engaged:
			return "UNIT NOT ENGAGED"
		return "FALL BACK MUST END OUT OF ENGAGEMENT" if remains_engaged else ""
	if engaged:
		return "ENGAGED UNIT MUST FALL BACK"
	return "CANNOT END IN ENGAGEMENT" if remains_engaged else ""

static func _advance_reference_error(models: Array, unit_id: String) -> String:
	var unit_models: Array = []
	var enemies: Array = []
	var unit_team := -1
	for model in models:
		if Attachments.group_id(model) == unit_id and not Reserves.in_reserve(model) and not Transports.is_embarked(model):
			unit_models.append(model)
			unit_team = int(model.get("team", -1))
	for model in models:
		if int(model.get("team", -1)) != unit_team and not Reserves.in_reserve(model) and not Transports.is_embarked(model):
			enemies.append(model)
	for model in unit_models:
		if float(model.get("spent", 0.0)) > Engagement.EPSILON:
			return "UNIT ALREADY MOVED"
		if bool(model.get("advanced", false)):
			return "UNIT ALREADY ADVANCED"
		if bool(model.get("fell_back", false)):
			return "FELL BACK"
		for enemy in enemies:
			if Engagement.in_engagement(model, enemy):
				return "ENGAGED UNIT MUST FALL BACK"
	return ""

static func _scout_reference_error(models: Array, unit_id: String, delta: Array, actor_team: int) -> String:
	var unit_models: Array = []
	var enemies: Array = []
	var allowance := 0.0
	for model in models:
		if Attachments.group_id(model) == unit_id:
			if int(model.get("team", -1)) != actor_team:
				return "NOT ACTIVE TEAM"
			if Reserves.in_reserve(model):
				return "UNIT IN RESERVE"
			if bool(model.get("scouted", false)) or float(model.get("spent", 0.0)) > Engagement.EPSILON:
				return "UNIT ALREADY SCOUTED"
			unit_models.append(model)
			allowance = maxf(allowance, float(UnitAbilities.modifiers(model.get("ability_ids", [])).get("prebattle_move_inches", 0.0)))
		elif int(model.get("team", -1)) != actor_team and Reserves.active(model):
			enemies.append(model)
	if unit_models.is_empty():
		return "UNKNOWN UNIT"
	if allowance <= 0.0:
		return "UNIT LACKS SCOUT"
	var movement_delta := Vector2(float(delta[0]), float(delta[1]))
	if movement_delta.length() > allowance + Engagement.EPSILON:
		return "SCOUT LIMIT EXCEEDED"
	var external: Array = []
	for model in models:
		if Attachments.group_id(model) != unit_id and Reserves.active(model):
			external.append(model)
	for model in unit_models:
		var destination := _position_of(model) + movement_delta
		var move_error := Movement.movement_reason_for_model(model, destination, allowance, external, -1, [])
		if not move_error.is_empty():
			return move_error
		var moved: Dictionary = model.duplicate(true)
		moved.position = destination
		for enemy in enemies:
			if Engagement.separation(moved, enemy) < 9.0 - Engagement.EPSILON:
				return "SCOUT TOO CLOSE TO ENEMY"
	return ""

static func _battle_shock_reference_error(models: Array, unit_id: String, payload: Dictionary) -> String:
	var unit_models: Array = []
	for model in models:
		if Attachments.group_id(model) == unit_id:
			unit_models.append(model)
	if not payload.has("rolls") or not (payload.get("rolls") is Array) or payload.rolls.is_empty():
		return ""
	var rolls: Array = payload.rolls
	if rolls.size() != 2:
		return "INVALID BATTLE SHOCK RESULT"
	var total := 0
	for roll in rolls:
		if typeof(roll) not in [TYPE_INT, TYPE_FLOAT] or float(roll) != float(int(roll)) or int(roll) < 1 or int(roll) > 6:
			return "INVALID BATTLE SHOCK RESULT"
		total += int(roll)
	var modifier := int(payload.get("modifier", 0))
	var expected_total := total + modifier
	if payload.has("total") and int(payload.get("total", expected_total)) != expected_total:
		return "INVALID BATTLE SHOCK RESULT"
	var leadership := int(unit_models[0].get("leadership", 7))
	var expected_passed := expected_total <= leadership
	return "" if bool(payload.get("passed", false)) == expected_passed else "INVALID BATTLE SHOCK RESULT"

static func _feel_no_pain_reference_error(model: Dictionary, damage: int, payload: Dictionary, rolls_key: String = "feel_no_pain_rolls") -> String:
	var target := int(model.get("feel_no_pain", 0))
	if target <= 0:
		return ""
	var incoming := maxi(0, damage - maxi(0, int(model.get("damage_reduction", 0))))
	var rolls: Variant = payload.get(rolls_key, [])
	if not (rolls is Array) or rolls.size() != incoming:
		return "INVALID FEEL NO PAIN RESULT"
	for roll in rolls:
		if typeof(roll) not in [TYPE_INT, TYPE_FLOAT] or int(roll) < 1 or int(roll) > 6 or float(roll) != float(int(roll)):
			return "INVALID FEEL NO PAIN RESULT"
	return ""

static func _has_active_effect(effects: Array, effect: String, team: int, unit_id: String) -> bool:
	for entry in effects:
		if not (entry is Dictionary) or bool(entry.get("consumed", false)) or str(entry.get("effect", "")) != effect or int(entry.get("team", -1)) != team:
			continue
		var payload: Variant = entry.get("payload", {})
		if payload is Dictionary and str(payload.get("unit_id", "")) == unit_id:
			return true
	return false

static func _stratagem_for(state: Dictionary, team: int, stratagem_id: String) -> Dictionary:
	var builtin := Stratagems.definition(stratagem_id)
	if not builtin.is_empty():
		return builtin
	for model in state.get("models", []):
		if int(model.get("team", -1)) != team:
			continue
		for declared in model.get("faction_stratagems", []):
			if declared is Dictionary and str(declared.get("id", "")) == stratagem_id:
				return declared.duplicate(true)
	return {}

static func _charge_reference_error(models: Array, charger_index: int, target_index: int, payload: Dictionary, terrain: Array) -> String:
	var charger: Dictionary = models[charger_index]
	var target: Dictionary = models[target_index]
	var charger_abilities := UnitAbilities.modifiers(charger.get("ability_ids", []))
	if bool(charger.get("advanced", false)) and not bool(charger_abilities.advance_and_charge):
		return "ADVANCED CANNOT CHARGE"
	if bool(charger.get("fell_back", false)) and not bool(charger_abilities.get("fall_back_and_charge", false)):
		return "FELL BACK"
	var charge_distance := INF
	if payload.has("roll"):
		var rolls: Variant = payload.get("roll", [])
		if not (rolls is Array) or rolls.size() != 2:
			return "INVALID CHARGE ROLL"
		charge_distance = 0.0
		for roll in rolls:
			if typeof(roll) not in [TYPE_INT, TYPE_FLOAT] or int(roll) < 1 or int(roll) > 6 or float(roll) != float(int(roll)):
				return "INVALID CHARGE ROLL"
			charge_distance += float(roll)
	var starting_distance := _position_of(charger).distance_to(_position_of(target))
	if not is_inf(charge_distance):
		var target_error := Charge.target_reason(charger, target, int(charger.get("team", -1)), starting_distance, int(charge_distance), 1.0, bool(charger_abilities.advance_and_charge), bool(charger_abilities.fall_back_and_charge))
		if not target_error.is_empty():
			return target_error
	var destination_value: Variant = payload.get("to", [])
	if not (destination_value is Array) or destination_value.size() != 2:
		return "INVALID CHARGE"
	var destination := Vector2(float(destination_value[0]), float(destination_value[1]))
	var external_models: Array = []
	for index in range(models.size()):
		if index != charger_index:
			external_models.append(models[index])
	var movement_error := Movement.movement_reason_for_model(charger, destination, charge_distance, external_models, -1, terrain, 0.0)
	if not movement_error.is_empty():
		return "CHARGE " + movement_error
	var end_error := Charge.end_reason(destination, _position_of(target), 1.0, float(charger.get("radius", charger.get("base_radius", 0.0))), float(target.get("radius", target.get("base_radius", 0.0))))
	return end_error

static func _attack_reference_error(models: Array, attacker_index: int, target_index: int, payload: Dictionary, kind: String, actor_team: int) -> String:
	var attacker: Dictionary = models[attacker_index]
	var target: Dictionary = models[target_index]
	var weapons: Variant = attacker.get("weapons", [])
	var weapon_name := str(payload.get("weapon", ""))
	# Older prototype logs did not carry a weapon table. They remain replayable;
	# once a model has a table, every attack must name a resolvable weapon.
	if not (weapons is Array) or weapons.is_empty():
		return ""
	if weapon_name.is_empty():
		return "MISSING WEAPON"
	var weapon: Dictionary = {}
	for candidate in weapons:
		if candidate is Dictionary and str(candidate.get("name", "")) == weapon_name:
			weapon = candidate
			break
	if weapon.is_empty():
		return "UNKNOWN WEAPON"
	if not str(target.get("attached_to", "")).is_empty() and not WeaponRules.ids_from_weapon(weapon).has("precision"):
		return "PRECISION REQUIRED"
	var distance := _position_of(attacker).distance_to(_position_of(target))
	if kind == "FIGHT":
		return Melee.target_reason(attacker, target, actor_team)
	var attacker_engaged := _engaged_with_enemy(models, attacker_index)
	var target_engaged := _engaged_with_enemy(models, target_index)
	return Combat.target_reason(attacker, target, distance, weapon, actor_team, attacker_engaged, target_engaged)

static func _engaged_with_enemy(models: Array, model_index: int) -> bool:
	var model: Dictionary = models[model_index]
	if Reserves.in_reserve(model) or Transports.is_embarked(model):
		return false
	for index in range(models.size()):
		if index == model_index or Reserves.in_reserve(models[index]) or Transports.is_embarked(models[index]) or int(models[index].get("team", -1)) == int(model.get("team", -1)):
			continue
		if Engagement.in_engagement(model, models[index]):
			return true
	return false

static func _fights_first_blocked(models: Array, attacker_index: int, effects: Array = [], team: int = -1) -> bool:
	var attacker: Dictionary = models[attacker_index]
	if bool(UnitAbilities.modifiers(attacker.get("ability_ids", [])).get("fights_first", false)):
		return false
	for effect in effects:
		if effect is Dictionary and str(effect.get("effect", "")) == "FIGHT_NEXT" and int(effect.get("team", -1)) == team and not bool(effect.get("consumed", false)):
			return false
	for index in range(models.size()):
		var candidate: Dictionary = models[index]
		if int(candidate.get("team", -1)) != int(attacker.get("team", -1)) or Reserves.in_reserve(candidate) or _group_fought(models, Attachments.group_id(candidate)):
			continue
		if not bool(UnitAbilities.modifiers(candidate.get("ability_ids", [])).get("fights_first", false)):
			continue
		if _engaged_with_enemy(models, index):
			return true
	return false

static func _group_fought(models: Array, unit_id: String) -> bool:
	for model in models:
		if Attachments.group_id(model) == unit_id and bool(model.get("fought", false)):
			return true
	return false

static func _position_of(model: Dictionary) -> Vector2:
	var position: Variant = model.get("position", Vector2.ZERO)
	if position is Vector2:
		return position
	if position is Array and position.size() == 2:
		return Vector2(float(position[0]), float(position[1]))
	return Vector2.ZERO

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


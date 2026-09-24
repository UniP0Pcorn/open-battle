# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Deterministic single-player opponent. It only emits commands through the
## same BattleSession authority used by a human or a future network peer.

const BattleSession = preload("res://rules/battle_session.gd")
const Combat = preload("res://rules/combat.gd")
const Charge = preload("res://rules/charge.gd")
const Damage = preload("res://rules/damage.gd")
const Engagement = preload("res://rules/engagement.gd")
const Melee = preload("res://rules/melee.gd")
const Movement = preload("res://rules/movement.gd")
const TurnState = preload("res://rules/turn_state.gd")
const WeaponRules = preload("res://rules/weapon_rules.gd")
const UnitAbilities = preload("res://rules/unit_abilities.gd")
const Reserves = preload("res://rules/reserves.gd")
const Transports = preload("res://rules/transports.gd")
const Attachments = preload("res://rules/attachments.gd")

const EPSILON := 0.0001

static func play_turn(state: Dictionary, team: int, seed: int = 1, max_commands: int = 64) -> Dictionary:
	if int(state.get("active_team", -1)) != team:
		return {"ok": false, "reason": "NOT ACTIVE TEAM", "state": state, "commands": []}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var next := state.duplicate(true)
	var commands: Array = []
	var guard := 0
	while int(next.get("active_team", -1)) == team and guard < max_commands:
		guard += 1
		var phase := str(next.get("phase", ""))
		if phase == "COMMAND":
			var attachment := _attachment_command(next, team)
			if not attachment.is_empty():
				var attachment_result := _submit(next, team, str(attachment.kind), attachment.payload)
				if attachment_result.ok:
					next = attachment_result.state
					commands.append(attachment_result.entry)
					continue
			var scout := _scout_command(next, team)
			if not scout.is_empty():
				var scout_result := _submit(next, team, "SCOUT", scout)
				if scout_result.ok:
					next = scout_result.state
					commands.append(scout_result.entry)
					continue
			var command_result := _submit(next, team, "PHASE_ADVANCE", {"from": "COMMAND", "to": "MOVEMENT"})
			if not command_result.ok:
				return {"ok": false, "reason": command_result.reason, "state": next, "commands": commands}
			next = command_result.state
			commands.append(command_result.entry)
			continue
		if phase == "MOVEMENT":
			var reserve := _reserve_command(next, team)
			if not reserve.is_empty():
				var reserve_result := _submit(next, team, "DEPLOY_RESERVE", reserve)
				if reserve_result.ok:
					next = reserve_result.state
					commands.append(reserve_result.entry)
					continue
			var transport_action := _transport_command(next, team)
			if not transport_action.is_empty():
				var transport_result := _submit(next, team, str(transport_action.kind), transport_action.payload)
				if transport_result.ok:
					next = transport_result.state
					commands.append(transport_result.entry)
					continue
			var movement := _movement_command(next, team)
			if not movement.is_empty():
				var movement_result := _submit(next, team, "MOVE", movement)
				if movement_result.ok:
					next = movement_result.state
					commands.append(movement_result.entry)
					continue
			var movement_advance := _advance_phase(next, team)
			if not movement_advance.ok:
				return {"ok": false, "reason": movement_advance.reason, "state": next, "commands": commands}
			next = movement_advance.state
			commands.append(movement_advance.entry)
			continue
		if phase == "SHOOTING":
			var shooting := _shooting_command(next, team, rng)
			if not shooting.is_empty():
				var shooting_result := _submit(next, team, "SHOOT", shooting)
				if shooting_result.ok:
					next = shooting_result.state
					commands.append(shooting_result.entry)
					continue
			var shooting_advance := _advance_phase(next, team)
			if not shooting_advance.ok:
				return {"ok": false, "reason": shooting_advance.reason, "state": next, "commands": commands}
			next = shooting_advance.state
			commands.append(shooting_advance.entry)
			continue
		if phase == "CHARGE":
			var charge := _charge_command(next, team, rng)
			if not charge.is_empty():
				var charge_result := _submit(next, team, "CHARGE", charge)
				if charge_result.ok:
					next = charge_result.state
					commands.append(charge_result.entry)
					continue
			var charge_advance := _advance_phase(next, team)
			if not charge_advance.ok:
				return {"ok": false, "reason": charge_advance.reason, "state": next, "commands": commands}
			next = charge_advance.state
			commands.append(charge_advance.entry)
			continue
		if phase == "FIGHT":
			var fight := _fight_command(next, team, rng)
			if not fight.is_empty():
				var fight_result := _submit(next, team, "FIGHT", fight)
				if fight_result.ok:
					next = fight_result.state
					commands.append(fight_result.entry)
					continue
			# A player ends the turn after the Fight phase.  Advancing through
			# COMMAND would hand control over with the wrong phase and would
			# bypass the command-point/cleanup path shared by the tabletop UI.
			var end_result := _submit(next, team, "END_TURN", {})
			if not end_result.ok:
				return {"ok": false, "reason": end_result.reason, "state": next, "commands": commands}
			next = end_result.state
			commands.append(end_result.entry)
			continue
		if phase == "COMMAND":
			continue
		return {"ok": false, "reason": "INVALID PHASE", "state": next, "commands": commands}
	if int(next.get("active_team", -1)) == team:
		return {"ok": false, "reason": "AI COMMAND LIMIT", "state": next, "commands": commands}
	return {"ok": true, "reason": "", "state": next, "commands": commands}

static func _advance_phase(state: Dictionary, team: int) -> Dictionary:
	var phase := str(state.get("phase", ""))
	var advanced := TurnState.advance({
		"round": int(state.get("round", 1)),
		"active_team": int(state.get("active_team", team)),
		"phase": phase,
		"phase_index": int(state.get("phase_index", -1)),
		"command_points": state.get("command_points", [0, 0]).duplicate(true)
	})
	return _submit(state, team, "PHASE_ADVANCE", {"from": phase, "to": str(advanced.phase)})

static func _submit(state: Dictionary, team: int, kind: String, payload: Dictionary) -> Dictionary:
	return BattleSession.submit(state, team, kind, payload)

static func _attachment_command(state: Dictionary, team: int) -> Dictionary:
	for leader in state.get("models", []):
		if int(leader.get("team", -1)) != team or not Attachments.is_leader(leader) or not str(leader.get("attached_to", "")).is_empty():
			continue
		for bodyguard in state.get("models", []):
			if int(bodyguard.get("team", -1)) != team or str(bodyguard.get("unit_id", "")) == str(leader.get("unit_id", "")):
				continue
			var reason := Attachments.attach_reason(state.models, str(leader.get("unit_id", "")), str(bodyguard.get("unit_id", "")), team)
			if reason.is_empty():
				return {"kind": "ATTACH", "payload": {"leader_unit_id": str(leader.get("unit_id", "")), "bodyguard_unit_id": str(bodyguard.get("unit_id", ""))}}
	return {}

static func _movement_command(state: Dictionary, team: int) -> Dictionary:
	var unit_ids: Array = []
	for model in state.get("models", []):
		if int(model.get("team", -1)) == team and not Transports.is_embarked(model) and not unit_ids.has(Attachments.group_id(model)):
			unit_ids.append(Attachments.group_id(model))
	for unit_id in unit_ids:
		var unit_models: Array = []
		for model in state.models:
			if Attachments.group_id(model) == unit_id and not Transports.is_embarked(model):
				unit_models.append(model)
		if unit_models.is_empty() or _unit_engaged(unit_models, state.models):
			continue
		var target := _nearest_enemy(unit_models[0], state.models, team)
		if target.is_empty():
			continue
		var direction := (_position(target) - _position(unit_models[0])).normalized()
		if direction.is_zero_approx():
			continue
		var allowance := INF
		for model in unit_models:
			allowance = minf(allowance, float(model.get("movement_inches", 0.0)) + float(model.get("advance_bonus", 0)) - float(model.get("spent", 0.0)))
		var distance := minf(maxf(0.0, allowance), 6.0)
		for fraction in [1.0, 0.5, 0.25]:
			var delta: Vector2 = direction * distance * float(fraction)
			if delta.length() <= EPSILON:
				continue
			if _unit_move_is_legal(unit_models, delta, state.models, state.get("terrain", [])):
				return {"unit_id": unit_id, "delta": [delta.x, delta.y]}
	return {}

static func _unit_move_is_legal(unit_models: Array, delta: Vector2, all_models: Array, terrain: Array) -> bool:
	var external: Array = []
	var unit_ids: Dictionary = {}
	for model in unit_models:
		unit_ids[Attachments.group_id(model)] = true
	for model in all_models:
		if not unit_ids.has(Attachments.group_id(model)):
			external.append(model)
	for model in unit_models:
		var allowance := float(model.get("movement_inches", 0.0)) + float(model.get("advance_bonus", 0))
		var reason := Movement.movement_reason_for_model(model, _position(model) + delta, allowance, external, -1, terrain)
		if not reason.is_empty():
			return false
	return true

static func _shooting_command(state: Dictionary, team: int, rng: RandomNumberGenerator) -> Dictionary:
	for attacker_index in range(state.models.size()):
		var attacker: Dictionary = state.models[attacker_index]
		if int(attacker.get("team", -1)) != team or Transports.is_embarked(attacker):
			continue
		for weapon in attacker.get("weapons", []):
			var distance_limit := float(weapon.get("range_inches", weapon.get("range", 0.0)))
			for target_index in range(state.models.size()):
				var target: Dictionary = state.models[target_index]
				if int(target.get("team", -1)) == team or Transports.is_embarked(target):
					continue
				var distance := _position(attacker).distance_to(_position(target))
				if distance > distance_limit + EPSILON:
					continue
				var reason := Combat.target_reason(attacker, target, distance, weapon, team, _model_engaged(attacker, state.models), _model_engaged(target, state.models))
				if not reason.is_empty():
					continue
				var target_abilities := UnitAbilities.modifiers(target.get("ability_ids", []))
				var context := WeaponRules.context(weapon, distance, int(target_abilities.get("cover_bonus", 0)) + int(target.get("temporary_cover_bonus", 0)), 1, target.get("keywords", []), float(attacker.get("spent", 0.0)) <= EPSILON, true)
				var result := Combat.resolve_ranged_attack(context.weapon, target, rng, 0, UnitAbilities.event_modifiers(attacker.get("ability_ids", []), "before_attack", {"phase": "SHOOTING", "kind": "SHOOT"}))
				return _attack_payload(attacker_index, attacker, target_index, target, weapon, context.weapon, result, rng)
	return {}

static func _charge_command(state: Dictionary, team: int, rng: RandomNumberGenerator) -> Dictionary:
	for attacker_index in range(state.models.size()):
		var attacker: Dictionary = state.models[attacker_index]
		if int(attacker.get("team", -1)) != team or Transports.is_embarked(attacker) or bool(attacker.get("fell_back", false)):
			continue
		var attacker_abilities := UnitAbilities.modifiers(attacker.get("ability_ids", []))
		for target_index in range(state.models.size()):
			var target: Dictionary = state.models[target_index]
			if int(target.get("team", -1)) == team or Transports.is_embarked(target):
				continue
			var roll := Charge.charge_distance(rng)
			var starting := _position(attacker).distance_to(_position(target))
			if not Charge.target_reason(attacker, target, team, starting, int(roll.distance), 1.0, bool(attacker_abilities.advance_and_charge)).is_empty():
				continue
			var direction := (_position(target) - _position(attacker)).normalized()
			var destination := _position(target) - direction * (float(attacker.get("radius", 0.0)) + float(target.get("radius", 0.0)) + 0.5)
			return {"model": attacker_index, "model_id": attacker.get("model_id", ""), "target": target_index, "target_id": target.get("model_id", ""), "roll": roll.rolls, "to": [destination.x, destination.y]}
	return {}

static func _fight_command(state: Dictionary, team: int, rng: RandomNumberGenerator) -> Dictionary:
	for priority in [true, false]:
		for attacker_index in range(state.models.size()):
			var attacker: Dictionary = state.models[attacker_index]
			if int(attacker.get("team", -1)) != team or not Reserves.active(attacker) or Transports.is_embarked(attacker):
				continue
			if _group_fought(state.models, Attachments.group_id(attacker)) or bool(UnitAbilities.modifiers(attacker.get("ability_ids", [])).get("fights_first", false)) != priority:
				continue
			for target_index in range(state.models.size()):
				var target: Dictionary = state.models[target_index]
				if not Reserves.active(target) or Transports.is_embarked(target) or not Melee.target_reason(attacker, target, team).is_empty():
					continue
				for weapon in attacker.get("weapons", []):
					if float(weapon.get("range_inches", weapon.get("range", 0.0))) > 0.0:
						continue
					var context := WeaponRules.context(weapon, INF, 0, 1, target.get("keywords", []), false)
					var result := Melee.resolve_attack(context.weapon, target, rng, 0, target.get("keywords", []), UnitAbilities.event_modifiers(attacker.get("ability_ids", []), "before_attack", {"phase": "FIGHT", "kind": "FIGHT"}))
					return _attack_payload(attacker_index, attacker, target_index, target, weapon, context.weapon, result, rng)
	return {}

static func _attack_payload(attacker_index: int, attacker: Dictionary, target_index: int, target: Dictionary, weapon: Dictionary, resolved_weapon: Dictionary, result: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var payload := {"attacker": attacker_index, "attacker_id": attacker.get("model_id", ""), "target": target_index, "target_id": target.get("model_id", ""), "weapon": str(weapon.get("name", "")), "one_shot": WeaponRules.ids_from_weapon(resolved_weapon).has("one_shot"), "hits": int(result.get("hits", 0)), "damage": int(result.get("damage", 0))}
	var target_preview: Array = [target.duplicate(true)]
	var target_damage := Damage.allocate_to_unit(target_preview, int(result.get("damage", 0)), 0, rng)
	if not target_damage.feel_no_pain_rolls.is_empty():
		payload.feel_no_pain_rolls = target_damage.feel_no_pain_rolls
	var hazardous_damage := int(result.get("hazardous_failures", 0)) * int(resolved_weapon.get("hazardous_damage", 0))
	payload.hazardous_damage = maxi(0, hazardous_damage)
	if hazardous_damage > 0:
		var attacker_preview: Array = [attacker.duplicate(true)]
		var attacker_damage := Damage.allocate_to_unit(attacker_preview, hazardous_damage, 0, rng)
		if not attacker_damage.feel_no_pain_rolls.is_empty():
			payload.hazardous_feel_no_pain_rolls = attacker_damage.feel_no_pain_rolls
	return payload

static func _unit_engaged(unit_models: Array, all_models: Array) -> bool:
	for model in unit_models:
		if _model_engaged(model, all_models):
			return true
	return false

static func _group_fought(all_models: Array, unit_id: String) -> bool:
	for model in all_models:
		if Attachments.group_id(model) == unit_id and bool(model.get("fought", false)):
			return true
	return false

static func _model_engaged(model: Dictionary, all_models: Array) -> bool:
	for other in all_models:
		if int(other.get("team", -1)) != int(model.get("team", -1)) and Engagement.in_engagement(model, other):
			return true
	return false

static func _nearest_enemy(model: Dictionary, all_models: Array, team: int) -> Dictionary:
	var nearest := INF
	var result: Dictionary = {}
	for other in all_models:
		if int(other.get("team", -1)) == team:
			continue
		var distance := _position(model).distance_to(_position(other))
		if distance < nearest:
			nearest = distance
			result = other
	return result

static func _position(model: Dictionary) -> Vector2:
	var value: Variant = model.get("position", Vector2.ZERO)
	if value is Vector2:
		return value
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

static func _reserve_command(state: Dictionary, team: int) -> Dictionary:
	var unit_ids: Array = []
	for model in state.get("models", []):
		if int(model.get("team", -1)) == team and Reserves.in_reserve(model) and not unit_ids.has(str(model.get("unit_id", ""))):
			unit_ids.append(str(model.get("unit_id", "")))
	var anchors := [Vector2(10, 10), Vector2(30, 10), Vector2(50, 10), Vector2(10, 34), Vector2(30, 34), Vector2(50, 34)]
	for unit_id in unit_ids:
		var unit_models: Array = []
		for model in state.models:
			if str(model.get("unit_id", "")) == unit_id:
				unit_models.append(model)
		if unit_models.is_empty() or not Reserves.has_deep_strike(unit_models[0]):
			continue
		var radius := float(unit_models[0].get("radius", 0.5))
		for anchor in anchors:
			var positions: Array = []
			for index in range(unit_models.size()):
				positions.append([anchor.x + index * (radius * 2.0 + 0.1), anchor.y])
			if Reserves.arrival_reason(state.models, unit_id, team, positions).is_empty():
				return {"unit_id": unit_id, "positions": positions}
	return {}

static func _scout_command(state: Dictionary, team: int) -> Dictionary:
	var unit_ids: Array = []
	for model in state.get("models", []):
		if int(model.get("team", -1)) == team and Reserves.active(model) and not unit_ids.has(str(model.get("unit_id", ""))):
			unit_ids.append(str(model.get("unit_id", "")))
	for unit_id in unit_ids:
		var unit_models: Array = []
		for model in state.models:
			if str(model.get("unit_id", "")) == unit_id:
				unit_models.append(model)
		if unit_models.is_empty() or bool(unit_models[0].get("scouted", false)):
			continue
		var modifiers := UnitAbilities.modifiers(unit_models[0].get("ability_ids", []))
		var allowance := float(modifiers.get("prebattle_move_inches", 0.0))
		if allowance <= 0.0:
			continue
		var nearest := _nearest_enemy(unit_models[0], state.models, team)
		if nearest.is_empty():
			continue
		var direction := (_position(nearest) - _position(unit_models[0])).normalized()
		if direction.is_zero_approx():
			continue
		return {"unit_id": unit_id, "delta": [direction.x * allowance, direction.y * allowance]}
	return {}

static func _transport_command(state: Dictionary, team: int) -> Dictionary:
	for transport in state.get("models", []):
		if int(transport.get("team", -1)) != team or not Transports.is_transport(transport) or not Transports.active(transport) or bool(transport.get("transport_moved", false)):
			continue
		for model in state.get("models", []):
			if int(model.get("team", -1)) != team or Transports.is_transport(model) or Transports.is_embarked(model):
				continue
			var embark_reason := Transports.embark_reason(state.models, Attachments.group_id(model), str(transport.get("model_id", "")), team)
			if embark_reason.is_empty():
				return {"kind": "EMBARK", "payload": {"unit_id": Attachments.group_id(model), "transport_id": str(transport.get("model_id", ""))}}
	for transport in state.get("models", []):
		if int(transport.get("team", -1)) != team or not Transports.is_transport(transport) or not Transports.active(transport) or bool(transport.get("transport_moved", false)):
			continue
		var has_passengers := false
		for model in state.get("models", []):
			if str(model.get("embarked_in", "")) == str(transport.get("model_id", "")):
				has_passengers = true
				break
		if not has_passengers:
			continue
		var target := _nearest_enemy(transport, state.models, team)
		if target.is_empty():
			continue
		var direction := (_position(target) - _position(transport)).normalized()
		var allowance := float(transport.get("movement_inches", 0.0)) - float(transport.get("spent", 0.0))
		var distance := minf(maxf(0.0, allowance), 6.0)
		var delta := direction * distance
		if not delta.is_zero_approx() and Transports.move_reason(state.models, str(transport.get("model_id", "")), [delta.x, delta.y], team, state.get("terrain", [])).is_empty():
			return {"kind": "TRANSPORT_MOVE", "payload": {"transport_id": str(transport.get("model_id", "")), "delta": [delta.x, delta.y]}}
	return {}


# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Deterministic single-player opponent. It only emits commands through the
## same BattleSession authority used by a human or a future network peer.

const BattleSession = preload("res://rules/battle_session.gd")
const Combat = preload("res://rules/combat.gd")
const Charge = preload("res://rules/charge.gd")
const Engagement = preload("res://rules/engagement.gd")
const Melee = preload("res://rules/melee.gd")
const Movement = preload("res://rules/movement.gd")
const TurnState = preload("res://rules/turn_state.gd")
const WeaponRules = preload("res://rules/weapon_rules.gd")

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
			var command_result := _submit(next, team, "PHASE_ADVANCE", {"from": "COMMAND", "to": "MOVEMENT"})
			if not command_result.ok:
				return {"ok": false, "reason": command_result.reason, "state": next, "commands": commands}
			next = command_result.state
			commands.append(command_result.entry)
			continue
		if phase == "MOVEMENT":
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

static func _movement_command(state: Dictionary, team: int) -> Dictionary:
	var unit_ids: Array = []
	for model in state.get("models", []):
		if int(model.get("team", -1)) == team and not unit_ids.has(str(model.get("unit_id", ""))):
			unit_ids.append(str(model.get("unit_id", "")))
	for unit_id in unit_ids:
		var unit_models: Array = []
		for model in state.models:
			if str(model.get("unit_id", "")) == unit_id:
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
		unit_ids[str(model.get("unit_id", ""))] = true
	for model in all_models:
		if not unit_ids.has(str(model.get("unit_id", ""))):
			external.append(model)
	for model in unit_models:
		var allowance := float(model.get("movement_inches", 0.0)) + float(model.get("advance_bonus", 0))
		var reason := Movement.movement_reason(_position(model), _position(model) + delta, float(model.get("spent", 0.0)), allowance, float(model.get("radius", 0.0)), external, -1, terrain)
		if not reason.is_empty():
			return false
	return true

static func _shooting_command(state: Dictionary, team: int, rng: RandomNumberGenerator) -> Dictionary:
	for attacker_index in range(state.models.size()):
		var attacker: Dictionary = state.models[attacker_index]
		if int(attacker.get("team", -1)) != team:
			continue
		for weapon in attacker.get("weapons", []):
			var distance_limit := float(weapon.get("range_inches", weapon.get("range", 0.0)))
			for target_index in range(state.models.size()):
				var target: Dictionary = state.models[target_index]
				if int(target.get("team", -1)) == team:
					continue
				var distance := _position(attacker).distance_to(_position(target))
				if distance > distance_limit + EPSILON:
					continue
				var reason := Combat.target_reason(attacker, target, distance, weapon, team, _model_engaged(attacker, state.models), _model_engaged(target, state.models))
				if not reason.is_empty():
					continue
				var context := WeaponRules.context(weapon, distance, 0, 1, target.get("keywords", []), float(attacker.get("spent", 0.0)) <= EPSILON, true)
				var result := Combat.resolve_ranged_attack(context.weapon, target, rng, 0)
				return {"attacker": attacker_index, "attacker_id": attacker.get("model_id", ""), "target": target_index, "target_id": target.get("model_id", ""), "weapon": str(weapon.get("name", "")), "one_shot": WeaponRules.ids_from_weapon(weapon).has("one_shot"), "hits": result.hits, "damage": result.damage}
	return {}

static func _charge_command(state: Dictionary, team: int, rng: RandomNumberGenerator) -> Dictionary:
	for attacker_index in range(state.models.size()):
		var attacker: Dictionary = state.models[attacker_index]
		if int(attacker.get("team", -1)) != team or bool(attacker.get("advanced", false)) or bool(attacker.get("fell_back", false)):
			continue
		for target_index in range(state.models.size()):
			var target: Dictionary = state.models[target_index]
			if int(target.get("team", -1)) == team:
				continue
			var roll := Charge.charge_distance(rng)
			var starting := _position(attacker).distance_to(_position(target))
			if not Charge.target_reason(attacker, target, team, starting, int(roll.distance)).is_empty():
				continue
			var direction := (_position(target) - _position(attacker)).normalized()
			var destination := _position(target) - direction * (float(attacker.get("radius", 0.0)) + float(target.get("radius", 0.0)) + 0.5)
			return {"model": attacker_index, "model_id": attacker.get("model_id", ""), "target": target_index, "target_id": target.get("model_id", ""), "roll": roll.rolls, "to": [destination.x, destination.y]}
	return {}

static func _fight_command(state: Dictionary, team: int, rng: RandomNumberGenerator) -> Dictionary:
	for attacker_index in range(state.models.size()):
		var attacker: Dictionary = state.models[attacker_index]
		if int(attacker.get("team", -1)) != team:
			continue
		for target_index in range(state.models.size()):
			var target: Dictionary = state.models[target_index]
			if not Melee.target_reason(attacker, target, team).is_empty():
				continue
			for weapon in attacker.get("weapons", []):
				if float(weapon.get("range_inches", weapon.get("range", 0.0))) > 0.0:
					continue
				var context := WeaponRules.context(weapon, INF, 0, 1, target.get("keywords", []), false)
				var result := Melee.resolve_attack(context.weapon, target, rng, 0, target.get("keywords", []))
				return {"attacker": attacker_index, "attacker_id": attacker.get("model_id", ""), "target": target_index, "target_id": target.get("model_id", ""), "weapon": str(weapon.get("name", "")), "one_shot": WeaponRules.ids_from_weapon(weapon).has("one_shot"), "hits": result.hits, "damage": result.damage}
	return {}

static func _unit_engaged(unit_models: Array, all_models: Array) -> bool:
	for model in unit_models:
		if _model_engaged(model, all_models):
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


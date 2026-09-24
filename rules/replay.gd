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

static func initial_state(models: Array, phase: String = "MOVEMENT", active_team: int = 0, terrain: Array = []) -> Dictionary:
	return {"models": models.duplicate(true), "phase": phase, "phase_index": TurnState.phase_index(phase), "active_team": active_team, "round": 1, "command_points": [0, 0], "terrain": terrain.duplicate(true), "stratagem_effects": [], "events": []}

static func apply_entry(state: Dictionary, entry: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	var kind := str(entry.get("kind", ""))
	var contract_error := CommandSchema.validate_for_state(entry, next)
	if not contract_error.is_empty():
		return {"ok": false, "reason": contract_error, "state": state}
	var payload: Dictionary = entry.payload
	var reference_error := _validate_references(next.models, entry, kind, payload, next.get("terrain", []))
	if not reference_error.is_empty():
		return {"ok": false, "reason": reference_error, "state": state}
	match kind:
		"MOVE":
			var delta: Array = payload.delta
			var unit_id := str(payload.get("unit_id", ""))
			var move_distance := Vector2(float(delta[0]), float(delta[1])).length()
			var found := false
			for model in next.models:
				if str(model.get("unit_id", "")) == unit_id:
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
				if str(model.get("unit_id", "")) == fall_back_unit_id:
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
			var stratagem: Dictionary = Stratagems.definition(stratagem_id)
			if stratagem.is_empty():
				return {"ok": false, "reason": "UNKNOWN STRATAGEM", "state": state}
			var stratagem_result := Stratagems.use(stratagem, str(next.phase), int(entry.team), next.get("command_points", [0, 0]))
			if not bool(stratagem_result.get("ok", false)):
				return {"ok": false, "reason": str(stratagem_result.get("reason", "STRATAGEM REJECTED")), "state": state}
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
				"payload": payload.duplicate(true)
			})
			next.stratagem_effects = effects
		_:
			return {"ok": false, "reason": "UNKNOWN COMMAND", "state": state}
	next.events.append(kind)
	return {"ok": true, "reason": "", "state": next}

static func _validate_references(models: Array, entry: Dictionary, kind: String, payload: Dictionary, terrain: Array = []) -> String:
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
			return _movement_reference_error(models, str(payload.get("unit_id", "")), payload.delta, str(kind) == "FALL_BACK", terrain)
		"ADVANCE":
			var advance_found := false
			for model in models:
				if str(model.get("unit_id", "")) == str(payload.get("unit_id", "")):
					advance_found = true
					if int(model.get("team", -1)) != actor_team:
						return "NOT ACTIVE TEAM"
			if not advance_found:
				return "UNKNOWN UNIT"
			return _advance_reference_error(models, str(payload.get("unit_id", "")))
		"CHARGE":
			var charger := _index_for(models, payload, "model_id", "model")
			var charge_target := _index_for(models, payload, "target_id", "target")
			if charger < 0 or charger >= models.size() or charge_target < 0 or charge_target >= models.size():
				return "INVALID CHARGE"
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
		"HAZARDOUS":
			var hazardous_attacker := _index_for(models, payload, "attacker_id", "attacker")
			if hazardous_attacker < 0 or hazardous_attacker >= models.size():
				return "INVALID HAZARDOUS EVENT"
			if int(models[hazardous_attacker].get("team", -1)) != actor_team:
				return "NOT ACTIVE TEAM"
			var hazardous_fnp_error := _feel_no_pain_reference_error(models[hazardous_attacker], int(payload.get("damage", 0)), payload)
			if not hazardous_fnp_error.is_empty():
				return hazardous_fnp_error
		"BATTLE_SHOCK":
			var found_unit := false
			for model in models:
				if str(model.get("unit_id", "")) == str(payload.get("unit_id", "")):
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
		if str(model.get("unit_id", "")) == unit_id:
			unit_models.append(model)
			unit_team = int(model.get("team", -1))
	for model in models:
		if int(model.get("team", -1)) != unit_team:
			enemies.append(model)
	var engaged := false
	var remains_engaged := false
	var movement_delta := Vector2(float(delta[0]), float(delta[1]))
	var movement_distance := movement_delta.length()
	var external_models: Array = []
	for model in models:
		if str(model.get("unit_id", "")) != unit_id:
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
		var path_error := Movement.movement_reason(origin, destination, float(model.get("spent", 0.0)), allowance, float(model.get("radius", 0.0)), external_models, -1, terrain)
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
		if str(model.get("unit_id", "")) == unit_id:
			unit_models.append(model)
			unit_team = int(model.get("team", -1))
	for model in models:
		if int(model.get("team", -1)) != unit_team:
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

static func _battle_shock_reference_error(models: Array, unit_id: String, payload: Dictionary) -> String:
	var unit_models: Array = []
	for model in models:
		if str(model.get("unit_id", "")) == unit_id:
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

static func _charge_reference_error(models: Array, charger_index: int, target_index: int, payload: Dictionary, terrain: Array) -> String:
	var charger: Dictionary = models[charger_index]
	var target: Dictionary = models[target_index]
	var charger_abilities := UnitAbilities.modifiers(charger.get("ability_ids", []))
	if bool(charger.get("advanced", false)) and not bool(charger_abilities.advance_and_charge):
		return "ADVANCED CANNOT CHARGE"
	if bool(charger.get("fell_back", false)):
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
		var target_error := Charge.target_reason(charger, target, int(charger.get("team", -1)), starting_distance, int(charge_distance), 1.0, bool(charger_abilities.advance_and_charge))
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
	var movement_error := Movement.movement_reason(_position_of(charger), destination, 0.0, charge_distance, float(charger.get("radius", charger.get("base_radius", 0.0))), external_models, -1, terrain)
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
	var distance := _position_of(attacker).distance_to(_position_of(target))
	if kind == "FIGHT":
		return Melee.target_reason(attacker, target, actor_team)
	var attacker_engaged := _engaged_with_enemy(models, attacker_index)
	var target_engaged := _engaged_with_enemy(models, target_index)
	return Combat.target_reason(attacker, target, distance, weapon, actor_team, attacker_engaged, target_engaged)

static func _engaged_with_enemy(models: Array, model_index: int) -> bool:
	var model: Dictionary = models[model_index]
	for index in range(models.size()):
		if index == model_index or int(models[index].get("team", -1)) == int(model.get("team", -1)):
			continue
		if Engagement.in_engagement(model, models[index]):
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

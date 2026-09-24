# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Minimal authoritative model snapshot validation shared by sessions and transports.

static func validate_models(models: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not (models is Array) or models.is_empty():
		return ["INVALID MODELS"]
	var ids: Dictionary = {}
	for index in range(models.size()):
		var error := validate_model(models[index], index, ids)
		if not error.is_empty():
			errors.append(error)
	return errors

static func validate_model(model: Variant, index: int = 0, ids: Dictionary = {}) -> String:
	if not (model is Dictionary):
		return "INVALID MODEL %d" % index
	var model_id := str(model.get("model_id", ""))
	if model_id.is_empty():
		return "MISSING MODEL ID %d" % index
	if ids.has(model_id):
		return "DUPLICATE MODEL ID " + model_id
	ids[model_id] = true
	if str(model.get("unit_id", "")).is_empty():
		return "MISSING UNIT ID " + model_id
	if model.has("ability_grants"):
		if not (model.ability_grants is Dictionary):
			return "INVALID ABILITY GRANTS " + model_id
		for ability in model.ability_grants:
			var grant: Variant = model.ability_grants[ability]
			if not (grant is Dictionary) or typeof(grant.get("native", null)) != TYPE_BOOL or not (grant.get("durations", null) is Array):
				return "INVALID ABILITY GRANTS " + model_id
			if not (model.get("ability_ids", null) is Array) or not model.ability_ids.has(ability) or grant.durations.is_empty():
				return "INVALID ABILITY GRANTS " + model_id
			for duration in grant.durations:
				if duration not in ["PHASE", "TURN", "BATTLE"]:
					return "INVALID ABILITY GRANTS " + model_id
	if int(model.get("team", -1)) not in [0, 1]:
		return "INVALID MODEL TEAM " + model_id
	var position: Variant = model.get("position", null)
	if position is Vector2:
		if not is_finite(position.x) or not is_finite(position.y):
			return "INVALID MODEL POSITION " + model_id
	elif position is Array and position.size() == 2:
		if not is_finite(float(position[0])) or not is_finite(float(position[1])):
			return "INVALID MODEL POSITION " + model_id
	else:
		return "MISSING MODEL POSITION " + model_id
	for field in ["radius", "wounds", "spent", "advance_bonus"]:
		if model.has(field) and (typeof(model[field]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(model[field])) or float(model[field]) < 0.0):
			return "INVALID MODEL " + field.to_upper() + " " + model_id
	if model.has("used_weapon_names") and not (model.used_weapon_names is Array):
		return "INVALID MODEL USED_WEAPON_NAMES " + model_id
	if model.has("charge_attempted") and typeof(model.charge_attempted) != TYPE_BOOL:
		return "INVALID MODEL CHARGE_ATTEMPTED " + model_id
	if model.has("fell_back") and typeof(model.fell_back) != TYPE_BOOL:
		return "INVALID MODEL FELL_BACK " + model_id
	if model.has("scouted") and typeof(model.scouted) != TYPE_BOOL:
		return "INVALID MODEL SCOUTED " + model_id
	if model.has("transport_moved") and typeof(model.transport_moved) != TYPE_BOOL:
		return "INVALID MODEL TRANSPORT_MOVED " + model_id
	if model.has("transport_capacity") and (typeof(model.transport_capacity) not in [TYPE_INT, TYPE_FLOAT] or int(model.transport_capacity) < 0 or float(model.transport_capacity) != float(int(model.transport_capacity))):
		return "INVALID MODEL TRANSPORT_CAPACITY " + model_id
	if model.has("embarked_in") and typeof(model.embarked_in) != TYPE_STRING:
		return "INVALID MODEL EMBARKED_IN " + model_id
	for field in ["attached_to", "attached_leader_id"]:
		if model.has(field) and typeof(model[field]) != TYPE_STRING:
			return "INVALID MODEL " + field.to_upper() + " " + model_id
	if model.has("leader") and typeof(model.leader) != TYPE_BOOL:
		return "INVALID MODEL LEADER " + model_id
	if model.has("leader_for") and not (model.leader_for is Array):
		return "INVALID MODEL LEADER_FOR " + model_id
	if model.has("reserve_status") and str(model.reserve_status) not in ["deployed", "reserve", "destroyed"]:
		return "INVALID MODEL RESERVE_STATUS " + model_id
	return ""

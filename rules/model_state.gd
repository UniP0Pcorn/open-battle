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
	if model.has("fell_back") and typeof(model.fell_back) != TYPE_BOOL:
		return "INVALID MODEL FELL_BACK " + model_id
	if model.has("scouted") and typeof(model.scouted) != TYPE_BOOL:
		return "INVALID MODEL SCOUTED " + model_id
	if model.has("reserve_status") and str(model.reserve_status) not in ["deployed", "reserve", "destroyed"]:
		return "INVALID MODEL RESERVE_STATUS " + model_id
	return ""

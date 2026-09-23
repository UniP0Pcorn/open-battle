# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Pure roster editing helpers. UI code should call these instead of mutating JSON.

const ArmyBuilder = preload("res://rules/army_builder.gd")
const ArmyValidation = preload("res://rules/army_validation.gd")

static func create(display_name: String, edition: int, points_limit: int) -> Dictionary:
	return {"id": "local_roster", "display_name": display_name, "edition": edition, "points_limit": points_limit, "units": []}

static func add_unit(roster: Dictionary, profiles: Dictionary, unit_id: String, count: int = 1, models_per_unit: int = 0) -> Dictionary:
	var next := roster.duplicate(true)
	if not profiles.has(unit_id):
		return {"ok": false, "reason": "UNKNOWN UNIT " + unit_id, "roster": next}
	var profile: Dictionary = profiles[unit_id]
	if str(profile.get("import_status", "ready")) not in ["ready", "verified", "prototype"]:
		return {"ok": false, "reason": "PROFILE NOT READY " + unit_id, "roster": next}
	if int(next.get("edition", 0)) > 0 and int(profile.get("edition", 0)) != int(next.edition):
		return {"ok": false, "reason": "EDITION MISMATCH " + unit_id, "roster": next}
	if count <= 0:
		return {"ok": false, "reason": "INVALID COUNT", "roster": next}
	var selected_count := models_per_unit
	if selected_count <= 0:
		selected_count = int(profile.points[0].models if not profile.get("points", []).is_empty() else 1)
	var cost := ArmyBuilder.points_for_count(profile, selected_count)
	if cost < 0:
		return {"ok": false, "reason": "UNSUPPORTED COUNT", "roster": next}
	var units: Array = next.get("units", [])
	units.append({"unit_id": unit_id, "count": count, "models_per_unit": selected_count, "points_each": cost})
	next.units = units
	var errors := validate(next, profiles)
	return {"ok": errors.is_empty(), "reason": "" if errors.is_empty() else errors[0], "errors": errors, "roster": next}

static func remove_unit(roster: Dictionary, index: int) -> Dictionary:
	var next := roster.duplicate(true)
	var units: Array = next.get("units", [])
	if index < 0 or index >= units.size():
		return {"ok": false, "reason": "INVALID UNIT INDEX", "roster": next}
	units.remove_at(index)
	next.units = units
	return {"ok": true, "reason": "", "roster": next}

static func set_unit_count(roster: Dictionary, profiles: Dictionary, index: int, count: int) -> Dictionary:
	var next := roster.duplicate(true)
	var units: Array = next.get("units", [])
	if index < 0 or index >= units.size():
		return {"ok": false, "reason": "INVALID UNIT INDEX", "roster": roster}
	if count <= 0:
		return {"ok": false, "reason": "INVALID COUNT", "roster": roster}
	var unit_id := str(units[index].get("unit_id", ""))
	if not profiles.has(unit_id):
		return {"ok": false, "reason": "UNKNOWN UNIT " + unit_id, "roster": roster}
	var entry: Dictionary = units[index].duplicate(true)
	entry.count = count
	units[index] = entry
	next.units = units
	var errors := validate(next, profiles)
	if not errors.is_empty():
		return {"ok": false, "reason": errors[0], "errors": errors, "roster": roster}
	return {"ok": true, "reason": "", "roster": next}

static func set_points_limit(roster: Dictionary, profiles: Dictionary, points_limit: int) -> Dictionary:
	var next := roster.duplicate(true)
	if points_limit <= 0:
		return {"ok": false, "reason": "INVALID POINTS LIMIT", "roster": roster}
	next.points_limit = points_limit
	var errors := validate(next, profiles)
	if not errors.is_empty():
		return {"ok": false, "reason": errors[0], "errors": errors, "roster": roster}
	return {"ok": true, "reason": "", "roster": next}

static func set_faction(roster: Dictionary, profiles: Dictionary, faction: String) -> Dictionary:
	var next := roster.duplicate(true)
	var normalized := faction.strip_edges()
	if normalized.is_empty():
		next.erase("faction")
	else:
		next.faction = normalized
	var errors := validate(next, profiles)
	if not errors.is_empty():
		return {"ok": false, "reason": errors[0], "errors": errors, "roster": roster}
	return {"ok": true, "reason": "", "roster": next}

static func validate(roster: Dictionary, profiles: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	errors.append_array(ArmyValidation.validate_roster(roster, profiles))
	var built := ArmyBuilder.build(roster, profiles)
	errors.append_array(built.errors)
	return _unique(errors)

static func total_points(roster: Dictionary) -> int:
	return ArmyValidation.total_points(roster)

static func encode(roster: Dictionary) -> String:
	return JSON.stringify(roster, "  ")

static func decode(text: String) -> Dictionary:
	var parsed = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

static func _unique(values: Array[String]) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		if not result.has(value):
			result.append(value)
	return result

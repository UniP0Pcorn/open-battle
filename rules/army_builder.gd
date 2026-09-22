# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Converts validated unit profiles and roster entries into battle units.

static func build(roster: Dictionary, profiles: Dictionary, team: int = 0) -> Dictionary:
	var errors: Array = []
	var units: Array = []
	var total := 0
	var edition := int(roster.get("edition", 0))
	var entry_index := 0
	for entry in roster.get("units", []):
		var unit_id := str(entry.get("unit_id", ""))
		if not profiles.has(unit_id):
			errors.append("UNKNOWN UNIT " + unit_id)
			continue
		var profile: Dictionary = profiles[unit_id]
		var roster_faction := str(roster.get("faction", "")).strip_edges()
		var profile_faction := str(profile.get("faction", "")).strip_edges()
		if not roster_faction.is_empty() and not profile_faction.is_empty() and roster_faction != profile_faction:
			errors.append("FACTION MISMATCH " + unit_id)
			continue
		var import_status := str(profile.get("import_status", "ready"))
		if import_status not in ["ready", "verified", "prototype"]:
			errors.append("PROFILE NOT READY " + unit_id)
			continue
		if edition > 0 and int(profile.get("edition", 0)) != edition:
			errors.append("EDITION MISMATCH " + unit_id)
			continue
		var unit_count := int(entry.get("count", 0))
		if unit_count <= 0:
			errors.append("INVALID COUNT " + unit_id)
			continue
		if profile.get("models", []).is_empty() or profile.get("points", []).is_empty():
			errors.append("INCOMPLETE PROFILE " + unit_id)
			continue
		var models_per_unit := int(entry.get("models_per_unit", profile.points[0].models if not profile.get("points", []).is_empty() else 1))
		var point_cost := points_for_count(profile, models_per_unit)
		if point_cost < 0:
			errors.append("UNSUPPORTED COUNT " + unit_id)
			continue
		total += point_cost * unit_count
		var entry_suffix := "" if entry_index == 0 else "_e%02d" % (entry_index + 1)
		for unit_index in range(unit_count):
			units.append(expand_unit(profile, models_per_unit, team, "%s%s_t%d_%02d" % [unit_id, entry_suffix, team, unit_index + 1]))
		entry_index += 1
	if total > int(roster.get("points_limit", 0)):
		errors.append("POINTS LIMIT EXCEEDED")
	return {"valid": errors.is_empty(), "errors": errors, "points": total, "units": units}

static func points_for_count(profile: Dictionary, count: int) -> int:
	var selected := -1
	for option in profile.get("points", []):
		var models := int(option.get("models", 0))
		if models == count:
			selected = int(option.get("cost", -1))
	return selected

static func expand_unit(profile: Dictionary, count: int, team: int, unit_id: String) -> Dictionary:
	var model_template: Dictionary = profile.models[0]
	var ability_ids: Array = profile.get("abilities", []).duplicate(true)
	var models: Array = []
	for index in range(count):
		models.append({
			"unit_id": unit_id,
			"model_index": index,
			"team": team,
			"display_name": str(model_template.get("name", profile.display_name)),
			"movement_inches": float(model_template.get("movement_inches", 0.0)),
			"toughness": int(model_template.get("toughness", 0)),
			"wounds": int(model_template.get("wounds", 0)),
			"save_on": int(model_template.get("save_on", 7)),
			"invulnerable_save": int(model_template.get("invulnerable_save", 0)),
			"leadership": int(model_template.get("leadership", 7)),
			"objective_control": int(model_template.get("objective_control", 1)),
			"base_diameter_mm": float(model_template.get("base_diameter_mm", 0.0)),
			"coherency_inches": float(model_template.get("coherency_inches", 2.0)),
			"ability_ids": ability_ids.duplicate(true),
			"keywords": profile.get("keywords", []).duplicate(true),
			"faction_keywords": profile.get("faction_keywords", []).duplicate(true),
			"weapons": profile.get("weapons", []).duplicate(true)
		})
	return {"unit_id": unit_id, "team": team, "models": models, "profile": profile.id, "abilities": ability_ids, "keywords": profile.get("keywords", []).duplicate(true), "faction_keywords": profile.get("faction_keywords", []).duplicate(true)}

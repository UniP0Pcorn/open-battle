# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Generic roster validation. It intentionally knows nothing about proprietary faction rules.

static func validate_roster(roster: Dictionary, profiles: Dictionary = {}) -> Array[String]:
	var errors: Array[String] = []
	var limit := int(roster.get("points_limit", 0))
	var total := 0
	var units: Array = roster.get("units", [])
	if units.is_empty():
		errors.append("Army must contain at least one unit.")
	for unit in units:
		var count := int(unit.get("count", 0))
		var points := int(unit.get("points_each", 0))
		if count <= 0:
			errors.append("Unit count must be positive: %s" % unit.get("unit_id", "unknown"))
		if points < 0:
			errors.append("Unit points cannot be negative: %s" % unit.get("unit_id", "unknown"))
		total += count * points
	if limit <= 0:
		errors.append("Points limit must be positive.")
	elif total > limit:
		errors.append("Army exceeds points limit (%d/%d)." % [total, limit])
	errors.append_array(validate_organization(roster, profiles))
	return errors

static func validate_organization(roster: Dictionary, profiles: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	if profiles.is_empty():
		return errors
	var copies: Dictionary = {}
	var roles: Dictionary = {}
	for unit in roster.get("units", []):
		var unit_id := str(unit.get("unit_id", ""))
		var count := int(unit.get("count", 0))
		copies[unit_id] = int(copies.get(unit_id, 0)) + count
		var profile: Dictionary = profiles.get(unit_id, {})
		var organization: Dictionary = profile.get("organization", {}) if profile.get("organization", {}) is Dictionary else {}
		var role := str(organization.get("role", profile.get("role", "")))
		if not role.is_empty():
			roles[role] = int(roles.get(role, 0)) + count
		var max_copies := int(organization.get("max_copies", profile.get("max_copies", 0)))
		if bool(organization.get("unique", profile.get("unique", false))):
			max_copies = 1
		if max_copies > 0 and copies[unit_id] > max_copies:
			errors.append("UNIT COPY LIMIT %s (%d/%d)" % [unit_id, copies[unit_id], max_copies])
	var requirements: Dictionary = roster.get("organization", {}) if roster.get("organization", {}) is Dictionary else {}
	for role_name in requirements.get("minimum_roles", []):
		var role_id := str(role_name)
		if int(roles.get(role_id, 0)) < 1:
			errors.append("MISSING REQUIRED ROLE " + role_id)
	return errors

static func total_points(roster: Dictionary) -> int:
	var total := 0
	for unit in roster.get("units", []):
		total += int(unit.get("count", 0)) * int(unit.get("points_each", 0))
	return total

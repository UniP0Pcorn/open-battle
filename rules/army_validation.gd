# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Generic roster validation. It intentionally knows nothing about proprietary faction rules.

static func validate_roster(roster: Dictionary) -> Array[String]:
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
	return errors

static func total_points(roster: Dictionary) -> int:
	var total := 0
	for unit in roster.get("units", []):
		total += int(unit.get("count", 0)) * int(unit.get("points_each", 0))
	return total

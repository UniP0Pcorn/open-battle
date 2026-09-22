# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Generic multi-model unit checks. Positions are Vector2 values in inches.

static func coherency_reason(models: Array, coherency_inches: float = 2.0, max_distance_inches: float = 9.0) -> String:
	if models.is_empty():
		return "EMPTY UNIT"
	if models.size() == 1:
		return ""
	for index in range(models.size()):
		var has_nearby_model := false
		var has_unit_distance := false
		for other_index in range(models.size()):
			if index == other_index:
				continue
			var distance: float = models[index].position.distance_to(models[other_index].position)
			if distance <= coherency_inches:
				has_nearby_model = true
			if distance <= max_distance_inches:
				has_unit_distance = true
		if not has_nearby_model:
			return "MODEL OUT OF COHERENCY"
		if not has_unit_distance:
			return "MODEL TOO FAR FROM UNIT"
	return ""

static func group_by_unit(models: Array) -> Dictionary:
	var groups := {}
	for model in models:
		var unit_id := str(model.get("unit_id", "unassigned"))
		if not groups.has(unit_id):
			groups[unit_id] = []
		groups[unit_id].append(model)
	return groups

static func all_units_reason(models: Array, coherency_inches: float = 2.0, max_distance_inches: float = 9.0) -> String:
	for unit_id in group_by_unit(models):
		var reason := coherency_reason(group_by_unit(models)[unit_id], coherency_inches, max_distance_inches)
		if not reason.is_empty():
			return "%s: %s" % [unit_id, reason]
	return ""

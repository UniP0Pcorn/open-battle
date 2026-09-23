# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Deployment-zone checks kept separate from movement so deployment can be data-driven.

const Movement = preload("res://rules/movement.gd")

static func zone_reason(position: Vector2, radius: float, team: int, board_size: Vector2 = Movement.BOARD_SIZE, depth: float = 12.0) -> String:
	if team not in [0, 1] or depth <= 0.0 or depth * 2.0 > board_size.y:
		return "INVALID DEPLOYMENT ZONE"
	var lower := radius if team == 0 else board_size.y - depth + radius
	var upper := depth - radius if team == 0 else board_size.y - radius
	if position.y < lower - Movement.EPSILON or position.y > upper + Movement.EPSILON:
		return "OUTSIDE DEPLOYMENT ZONE"
	return ""

static func placement_reason(position: Vector2, radius: float, team: int, models: Array, ignored_index: int = -1, depth: float = 12.0) -> String:
	var geometry_error := Movement.placement_reason(position, radius, models, ignored_index)
	if not geometry_error.is_empty():
		return geometry_error
	return zone_reason(position, radius, team, Movement.BOARD_SIZE, depth)

static func validate(models: Array, depth: float = 12.0) -> String:
	for index in range(models.size()):
		var model: Dictionary = models[index]
		var reason := placement_reason(model.position, float(model.get("radius", 0.0)), int(model.get("team", -1)), models, index, depth)
		if not reason.is_empty():
			return reason
	return ""

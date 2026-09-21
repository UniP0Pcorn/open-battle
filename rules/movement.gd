# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Pure geometry, inches throughout. No scene or rendering dependency.
const BOARD_SIZE := Vector2(60.0, 44.0)
const EPSILON := 0.00001

static func radius_inches(diameter_mm: float) -> float:
	return diameter_mm / 25.4 / 2.0

static func inside_board(position: Vector2, radius: float) -> bool:
	return position.x >= radius - EPSILON and position.y >= radius - EPSILON and position.x <= BOARD_SIZE.x - radius + EPSILON and position.y <= BOARD_SIZE.y - radius + EPSILON

static func placement_reason(position: Vector2, radius: float, models: Array, ignored_index: int = -1) -> String:
	if not inside_board(position, radius):
		return "OUTSIDE TABLE"
	for i in range(models.size()):
		if i != ignored_index and position.distance_to(models[i].position) < radius + float(models[i].radius) - EPSILON:
			return "BASE OVERLAP"
	return ""

static func movement_reason(origin: Vector2, destination: Vector2, spent: float, allowance: float, radius: float, models: Array, ignored_index: int) -> String:
	if spent + origin.distance_to(destination) > allowance + EPSILON:
		return "MOVE LIMIT EXCEEDED"
	return placement_reason(destination, radius, models, ignored_index)

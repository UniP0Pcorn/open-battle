# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Pure geometry, inches throughout. No scene or rendering dependency.
const BOARD_SIZE := Vector2(60.0, 44.0)
const EPSILON := 0.00001
const Terrain = preload("res://rules/terrain.gd")
const UnitKeywords = preload("res://rules/unit_keywords.gd")

static func radius_inches(diameter_mm: float) -> float:
	return diameter_mm / 25.4 / 2.0

static func inside_board(position: Vector2, radius: float) -> bool:
	return position.x >= radius - EPSILON and position.y >= radius - EPSILON and position.x <= BOARD_SIZE.x - radius + EPSILON and position.y <= BOARD_SIZE.y - radius + EPSILON

static func placement_reason(position: Vector2, radius: float, models: Array, ignored_index: int = -1) -> String:
	if not inside_board(position, radius):
		return "OUTSIDE TABLE"
	for i in range(models.size()):
		var other: Dictionary = models[i]
		var other_position := _position_of(other)
		var other_radius := float(other.get("radius", 0.0))
		if i != ignored_index and position.distance_to(other_position) < radius + other_radius - EPSILON:
			return "BASE OVERLAP"
	return ""

static func _position_of(model: Dictionary) -> Vector2:
	var position: Variant = model.get("position", Vector2.ZERO)
	if position is Vector2:
		return position
	if position is Array and position.size() == 2:
		return Vector2(float(position[0]), float(position[1]))
	return Vector2.ZERO

static func path_reason(origin: Vector2, destination: Vector2, radius: float, models: Array, ignored_index: int = -1) -> String:
	var travel := origin.distance_to(destination)
	if travel <= EPSILON:
		return ""
	# Sample at half-base intervals so a straight move cannot pass through
	# another base between the endpoints. The moving base is ignored.
	var step_length := maxf(radius, 0.25)
	var steps := maxi(1, ceili(travel / step_length))
	for step in range(1, steps):
		var point := origin.lerp(destination, float(step) / float(steps))
		if not placement_reason(point, radius, models, ignored_index).is_empty():
			return "PATH BLOCKED"
	return ""

static func movement_reason(origin: Vector2, destination: Vector2, spent: float, allowance: float, radius: float, models: Array, ignored_index: int, terrain: Array = [], can_fly: bool = false) -> String:
	if spent + origin.distance_to(destination) > allowance + EPSILON:
		return "MOVE LIMIT EXCEEDED"
	var path_error := path_reason(origin, destination, radius, models, ignored_index)
	if not path_error.is_empty():
		return path_error
	if not can_fly:
		var terrain_path_error := Terrain.path_reason(origin, destination, radius, terrain)
		if not terrain_path_error.is_empty():
			return terrain_path_error
	var terrain_end_error := Terrain.circle_reason(destination, radius, terrain)
	if not terrain_end_error.is_empty():
		return terrain_end_error
	return placement_reason(destination, radius, models, ignored_index)

static func movement_reason_for_model(model: Dictionary, destination: Vector2, allowance: float, models: Array, ignored_index: int, terrain: Array = [], spent_override: float = -1.0) -> String:
	var keywords := UnitKeywords.normalize(model.get("keywords", []))
	var spent := float(model.get("spent", 0.0)) if spent_override < 0.0 else spent_override
	return movement_reason(_position_of(model), destination, spent, allowance, float(model.get("radius", 0.0)), models, ignored_index, terrain, keywords.has("fly"))

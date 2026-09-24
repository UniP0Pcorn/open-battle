# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Deterministic reserve and deep-strike placement checks.

const Movement = preload("res://rules/movement.gd")
const UnitAbilities = preload("res://rules/unit_abilities.gd")

const DEPLOYED := "deployed"
const RESERVE := "reserve"
const DESTROYED := "destroyed"
const MIN_ENEMY_DISTANCE := 9.0

static func status(model: Dictionary) -> String:
	return str(model.get("reserve_status", DEPLOYED))

static func in_reserve(model: Dictionary) -> bool:
	return status(model) == RESERVE

static func active(model: Dictionary) -> bool:
	return status(model) == DEPLOYED

static func has_deep_strike(model: Dictionary) -> bool:
	for ability_id in model.get("ability_ids", []):
		if UnitAbilities.canonical_id(ability_id) == "deep_strike":
			return true
	return false

static func arrival_reason(models: Array, unit_id: String, team: int, positions: Array, min_enemy_distance: float = MIN_ENEMY_DISTANCE) -> String:
	if unit_id.is_empty() or team not in [0, 1] or positions.is_empty():
		return "INVALID RESERVE ARRIVAL"
	var unit_models: Array = []
	for model in models:
		if str(model.get("unit_id", "")) == unit_id:
			unit_models.append(model)
	if unit_models.is_empty():
		return "UNKNOWN UNIT"
	for model in unit_models:
		if int(model.get("team", -1)) != team:
			return "NOT ACTIVE TEAM"
		if not in_reserve(model):
			return "UNIT NOT IN RESERVE"
		if not has_deep_strike(model):
			return "UNIT LACKS DEEP STRIKE"
	if positions.size() != unit_models.size():
		return "INVALID RESERVE ARRIVAL"
	var placed: Array = []
	for index in range(positions.size()):
		var value: Variant = positions[index]
		if not (value is Array) or value.size() != 2 or typeof(value[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(value[1]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value[0])) or not is_finite(float(value[1])):
			return "INVALID RESERVE ARRIVAL"
		var model: Dictionary = unit_models[index]
		var position := Vector2(float(value[0]), float(value[1]))
		var radius := float(model.get("radius", model.get("base_radius", 0.0)))
		if position.x < radius - Movement.EPSILON or position.x > Movement.BOARD_SIZE.x - radius + Movement.EPSILON or position.y < radius - Movement.EPSILON or position.y > Movement.BOARD_SIZE.y - radius + Movement.EPSILON:
			return "OUTSIDE TABLE"
		for other in placed:
			if position.distance_to(other.position) < radius + float(other.get("radius", 0.0)) - Movement.EPSILON:
				return "BASE OVERLAP"
		placed.append({"position": position, "radius": radius})
	for model in models:
		if str(model.get("unit_id", "")) == unit_id or not active(model):
			continue
		var enemy_position: Variant = model.get("position", Vector2.ZERO)
		if enemy_position is Array and enemy_position.size() == 2:
			enemy_position = Vector2(float(enemy_position[0]), float(enemy_position[1]))
		if not (enemy_position is Vector2):
			continue
		for index in range(placed.size()):
			var separation := float(placed[index].position.distance_to(enemy_position)) - float(placed[index].radius) - float(model.get("radius", 0.0))
			if separation < -Movement.EPSILON:
				return "BASE OVERLAP"
			if int(model.get("team", -1)) != team and separation < min_enemy_distance - Movement.EPSILON:
				return "TOO CLOSE TO ENEMY"
	return ""

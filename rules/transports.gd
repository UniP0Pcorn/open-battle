# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Deterministic embark, transport movement and disembark checks.

const Movement = preload("res://rules/movement.gd")

const EMBARK_RANGE := 3.0

static func is_transport(model: Dictionary) -> bool:
	return int(model.get("transport_capacity", 0)) > 0

static func is_embarked(model: Dictionary) -> bool:
	return not str(model.get("embarked_in", "")).is_empty()

static func active(model: Dictionary) -> bool:
	return not is_embarked(model) and str(model.get("reserve_status", "deployed")) == "deployed"

static func embark_reason(models: Array, unit_id: String, transport_id: String, team: int) -> String:
	if unit_id.is_empty() or transport_id.is_empty() or team not in [0, 1]:
		return "INVALID EMBARK"
	var unit_models: Array = []
	var transport: Dictionary = {}
	for model in models:
		if _belongs_to_group(model, unit_id):
			unit_models.append(model)
		if str(model.get("model_id", "")) == transport_id:
			transport = model
	if unit_models.is_empty() or transport.is_empty():
		return "UNKNOWN TRANSPORT OR UNIT"
	if not is_transport(transport) or int(transport.get("team", -1)) != team:
		return "INVALID TRANSPORT"
	if not active(transport) or bool(transport.get("transport_moved", false)):
		return "TRANSPORT ALREADY MOVED"
	var occupied := 0
	for model in models:
		if str(model.get("embarked_in", "")) == transport_id:
			occupied += 1
	if occupied + unit_models.size() > int(transport.get("transport_capacity", 0)):
		return "TRANSPORT CAPACITY EXCEEDED"
	for model in unit_models:
		if int(model.get("team", -1)) != team:
			return "NOT ACTIVE TEAM"
		if is_embarked(model) or not active(model):
			return "UNIT NOT AVAILABLE"
		if bool(model.get("advanced", false)) or bool(model.get("fell_back", false)) or float(model.get("spent", 0.0)) > Movement.EPSILON:
			return "UNIT ALREADY MOVED"
		if _base_separation(model, transport) > EMBARK_RANGE + Movement.EPSILON:
			return "TRANSPORT OUT OF RANGE"
	return ""

static func disembark_reason(models: Array, unit_id: String, positions: Array, team: int) -> String:
	if unit_id.is_empty() or positions.is_empty() or team not in [0, 1]:
		return "INVALID DISEMBARK"
	var unit_models: Array = []
	var transport_id := ""
	var transport: Dictionary = {}
	for model in models:
		if _belongs_to_group(model, unit_id) and is_embarked(model):
			unit_models.append(model)
			transport_id = str(model.get("embarked_in", ""))
	for model in models:
		if str(model.get("model_id", "")) == transport_id:
			transport = model
	if unit_models.is_empty() or transport.is_empty() or not is_transport(transport):
		return "UNIT NOT EMBARKED"
	if int(transport.get("team", -1)) != team:
		return "NOT ACTIVE TEAM"
	if bool(transport.get("transport_moved", false)):
		return "TRANSPORT ALREADY MOVED"
	if positions.size() != unit_models.size():
		return "INVALID DISEMBARK"
	var placed: Array = []
	for index in range(positions.size()):
		var value: Variant = positions[index]
		if not (value is Array) or value.size() != 2 or typeof(value[0]) not in [TYPE_INT, TYPE_FLOAT] or typeof(value[1]) not in [TYPE_INT, TYPE_FLOAT]:
			return "INVALID DISEMBARK"
		var destination := Vector2(float(value[0]), float(value[1]))
		var model: Dictionary = unit_models[index]
		var radius := float(model.get("radius", 0.0))
		if not Movement.inside_board(destination, radius):
			return "OUTSIDE TABLE"
		if _base_separation_position(destination, radius, transport) > EMBARK_RANGE + Movement.EPSILON:
			return "DISEMBARK TOO FAR"
		for other in placed:
			if destination.distance_to(other.position) < radius + float(other.radius) - Movement.EPSILON:
				return "BASE OVERLAP"
		placed.append({"position": destination, "radius": radius})
		for other in models:
			if _belongs_to_group(other, unit_id) or not active(other):
				continue
			if _position_of(other).distance_to(destination) < radius + float(other.get("radius", 0.0)) - Movement.EPSILON:
				return "BASE OVERLAP"
			if int(other.get("team", -1)) != team and _base_separation_position(destination, radius, other) <= 1.0 + Movement.EPSILON:
				return "DISEMBARK IN ENGAGEMENT"
	return ""

static func move_reason(models: Array, transport_id: String, delta: Array, team: int, terrain: Array = []) -> String:
	if transport_id.is_empty() or not (delta is Array) or delta.size() != 2:
		return "INVALID TRANSPORT MOVE"
	var transport_index := -1
	for index in range(models.size()):
		if str(models[index].get("model_id", "")) == transport_id:
			transport_index = index
			break
	if transport_index < 0:
		return "UNKNOWN TRANSPORT"
	var transport: Dictionary = models[transport_index]
	if not is_transport(transport) or int(transport.get("team", -1)) != team:
		return "INVALID TRANSPORT"
	if not active(transport):
		return "TRANSPORT NOT AVAILABLE"
	if bool(transport.get("transport_moved", false)):
		return "TRANSPORT ALREADY MOVED"
	var allowance := float(transport.get("movement_inches", 0.0))
	var movement_delta := Vector2(float(delta[0]), float(delta[1]))
	if movement_delta.length() > allowance - float(transport.get("spent", 0.0)) + Movement.EPSILON:
		return "MOVE LIMIT EXCEEDED"
	var external: Array = []
	for index in range(models.size()):
		if index != transport_index and active(models[index]):
			external.append(models[index])
	return Movement.movement_reason_for_model(transport, _position_of(transport) + movement_delta, allowance, external, -1, terrain)

static func _base_separation(model: Dictionary, other: Dictionary) -> float:
	return _base_separation_position(_position_of(model), float(model.get("radius", 0.0)), other)

static func _belongs_to_group(model: Dictionary, unit_id: String) -> bool:
	var attached_to := str(model.get("attached_to", ""))
	return (attached_to if not attached_to.is_empty() else str(model.get("unit_id", ""))) == unit_id

static func _base_separation_position(position: Vector2, radius: float, other: Dictionary) -> float:
	return position.distance_to(_position_of(other)) - radius - float(other.get("radius", 0.0))

static func _position_of(model: Dictionary) -> Vector2:
	var value: Variant = model.get("position", Vector2.ZERO)
	if value is Vector2:
		return value
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

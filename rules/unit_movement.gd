# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Group movement validation for multi-model units.

const Movement = preload("res://rules/movement.gd")
const UnitValidation = preload("res://rules/unit_validation.gd")

static func movement_reason(unit: Array, delta: Vector2, spent: float, allowance: float, all_models: Array, terrain: Array = []) -> String:
	if unit.is_empty():
		return "EMPTY UNIT"
	var unit_indexes: Array = []
	for model in unit:
		var index := all_models.find(model)
		if index >= 0:
			unit_indexes.append(index)
	var external_models: Array = []
	for index in range(all_models.size()):
		if not unit_indexes.has(index):
			external_models.append(all_models[index])
	for model in unit:
		var destination: Vector2 = model.position + delta
		var model_spent := float(model.get("spent", spent))
		var model_allowance := float(model.get("movement_inches", allowance))
		var reason := Movement.movement_reason_for_model(model, destination, model_allowance, external_models, -1, terrain, model_spent)
		if not reason.is_empty():
			return reason
	var moved: Array = []
	for model in unit:
		var copy: Dictionary = model.duplicate(true)
		copy.position = copy.position + delta
		moved.append(copy)
	return UnitValidation.coherency_reason(moved, float(unit[0].get("coherency_inches", 2.0)))

static func translate(unit: Array, delta: Vector2) -> Array:
	var moved: Array = []
	for model in unit:
		var copy: Dictionary = model.duplicate(true)
		copy.position = copy.position + delta
		moved.append(copy)
	return moved

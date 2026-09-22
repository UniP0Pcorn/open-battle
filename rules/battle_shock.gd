# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Configurable battle-shock test. Leadership values come from unit data.

static func test(leadership: int, rng: RandomNumberGenerator, modifier: int = 0) -> Dictionary:
	var first := rng.randi_range(1, 6)
	var second := rng.randi_range(1, 6)
	var total := first + second + modifier
	return {"rolls": [first, second], "modifier": modifier, "total": total, "passed": total <= leadership}

static func required(current_model_count: int, starting_model_count: int) -> bool:
	return starting_model_count > 0 and current_model_count > 0 and current_model_count * 2 <= starting_model_count

static func apply(unit: Dictionary, result: Dictionary) -> Dictionary:
	var next := unit.duplicate(true)
	next.battle_shocked = not bool(result.get("passed", false))
	return next

static func apply_to_models(models: Array, unit_id: String, result: Dictionary) -> Array:
	var next: Array = []
	var shocked := not bool(result.get("passed", false))
	for model in models:
		var copy: Dictionary = model.duplicate(true)
		if str(copy.get("unit_id", "")) == unit_id:
			copy.battle_shocked = shocked
			copy.can_control = not shocked
		next.append(copy)
	return next

static func can_control_objective(unit: Dictionary) -> bool:
	return not bool(unit.get("battle_shocked", false))

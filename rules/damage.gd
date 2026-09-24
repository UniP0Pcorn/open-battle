# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Damage allocation helpers shared by shooting and melee.

static func apply_to_model(model: Dictionary, damage: int) -> Dictionary:
	var before := int(model.get("wounds", 0))
	var reduction := maxi(0, int(model.get("damage_reduction", 0)))
	var applied := maxi(0, damage - reduction)
	var after := maxi(0, before - applied)
	return {"wounds_before": before, "damage": applied, "wounds_after": after, "destroyed": after <= 0}

static func allocate_to_unit(unit: Array, damage: int, model_index: int = -1) -> Dictionary:
	if unit.is_empty():
		return {"damage": 0, "destroyed": 0, "target_index": -1}
	var target_index := model_index
	if target_index < 0 or target_index >= unit.size():
		target_index = 0
	var result := apply_to_model(unit[target_index], damage)
	unit[target_index].wounds = result.wounds_after
	var destroyed := 0
	if result.destroyed:
		unit.remove_at(target_index)
		destroyed = 1
	return {"damage": result.damage, "destroyed": destroyed, "target_index": target_index, "wounds_after": result.wounds_after}

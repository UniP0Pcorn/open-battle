# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Damage allocation helpers shared by shooting and melee.

static func apply_to_model(model: Dictionary, damage: int, feel_no_pain_rolls: Array = []) -> Dictionary:
	var before := int(model.get("wounds", 0))
	var reduction := maxi(0, int(model.get("damage_reduction", 0)))
	var incoming := maxi(0, damage - reduction)
	var ignored := 0
	var fnp_target := int(model.get("feel_no_pain", 0))
	if fnp_target > 0 and feel_no_pain_rolls.size() >= incoming:
		for index in range(incoming):
			if int(feel_no_pain_rolls[index]) >= fnp_target:
				ignored += 1
	var applied := maxi(0, incoming - ignored)
	var after := maxi(0, before - applied)
	return {"wounds_before": before, "damage": applied, "incoming_damage": incoming, "feel_no_pain_ignored": ignored, "wounds_after": after, "destroyed": after <= 0}

static func allocate_to_unit(unit: Array, damage: int, model_index: int = -1, rng: RandomNumberGenerator = null) -> Dictionary:
	if unit.is_empty():
		return {"damage": 0, "destroyed": 0, "target_index": -1}
	var target_index := model_index
	if target_index < 0 or target_index >= unit.size():
		target_index = 0
	var fnp_rolls: Array = []
	var fnp_target := int(unit[target_index].get("feel_no_pain", 0))
	var incoming := maxi(0, damage - maxi(0, int(unit[target_index].get("damage_reduction", 0))))
	if rng != null and fnp_target > 0:
		for _index in range(incoming):
			fnp_rolls.append(rng.randi_range(1, 6))
	var result := apply_to_model(unit[target_index], damage, fnp_rolls)
	unit[target_index].wounds = result.wounds_after
	var destroyed := 0
	if result.destroyed:
		unit.remove_at(target_index)
		destroyed = 1
	return {"damage": result.damage, "destroyed": destroyed, "target_index": target_index, "wounds_after": result.wounds_after, "feel_no_pain_rolls": fnp_rolls, "feel_no_pain_ignored": result.feel_no_pain_ignored}

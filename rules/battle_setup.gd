# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Shared prototype setup used when the lobby starts a local/network battle.

const ArmyBuilder = preload("res://rules/army_builder.gd")
const Rules = preload("res://rules/movement.gd")

static func default_models() -> Array:
	var roster = JSON.parse_string(FileAccess.get_file_as_string("res://data/armies/prototype_gold.json"))
	var profile = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/custodian_guard_profile.json"))
	if not (roster is Dictionary) or not (profile is Dictionary):
		return []
	var profiles := {str(profile.get("id", "")): profile}
	var result: Array = []
	for side in range(2):
		var built := ArmyBuilder.build(roster, profiles, side)
		if not bool(built.get("valid", false)):
			return []
		var model_index := 0
		for unit in built.get("units", []):
			for model in unit.get("models", []):
				var instance: Dictionary = model.duplicate(true)
				var row := model_index / 5
				var column := model_index % 5
				instance.model_id = "%s_m%03d" % [str(instance.get("unit_id", "unit")), model_index + 1]
				instance.position = Vector2(6 + column * 3, 6 + row * 3 + side * 29)
				instance.radius = Rules.radius_inches(float(instance.get("base_diameter_mm", 40.0)))
				instance.spent = 0.0
				instance.advanced = false
				instance.advance_bonus = 0
				instance.fell_back = false
				instance.fought = false
				instance.battle_shocked = false
				instance.can_control = true
				result.append(instance)
				model_index += 1
	return result

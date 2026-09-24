# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Structural validation for versioned, external unit profiles.

const UnitAbilities = preload("res://rules/unit_abilities.gd")
const UnitKeywords = preload("res://rules/unit_keywords.gd")
const Dice = preload("res://rules/dice.gd")
const RulesetCatalog = preload("res://rules/ruleset_catalog.gd")

static func validate_profile(profile: Dictionary) -> String:
	for field in ["id", "display_name", "edition", "faction", "models", "weapons"]:
		if not profile.has(field):
			return "MISSING " + field.to_upper()
	if str(profile.id).is_empty() or str(profile.display_name).is_empty():
		return "EMPTY ID OR NAME"
	if not RulesetCatalog.supported(int(profile.edition)):
		return "UNSUPPORTED EDITION " + str(profile.edition)
	if not (profile.models is Array) or profile.models.is_empty():
		return "NO MODELS"
	if not (profile.weapons is Array):
		return "INVALID WEAPONS"
	if not (profile.get("abilities", []) is Array):
		return "INVALID ABILITIES"
	if profile.has("leader") and typeof(profile.leader) != TYPE_BOOL:
		return "INVALID LEADER"
	if profile.has("leader_for") and not (profile.leader_for is Array):
		return "INVALID LEADER_FOR"
	var ability_errors := UnitAbilities.validate(UnitAbilities.ids_from_profile(profile))
	if not ability_errors.is_empty():
		return ability_errors[0]
	if not (profile.get("keywords", []) is Array) or not (profile.get("faction_keywords", []) is Array):
		return "INVALID KEYWORDS"
	var keyword_errors := UnitKeywords.validate(profile.get("keywords", []))
	if not keyword_errors.is_empty():
		return keyword_errors[0]
	for model in profile.models:
		for field in ["name", "movement_inches", "toughness", "wounds"]:
			if not model.has(field):
				return "MODEL MISSING " + field.to_upper()
		if float(model.movement_inches) < 0 or int(model.toughness) < 1 or int(model.wounds) < 1:
			return "INVALID MODEL STAT"
		if model.has("leader") and typeof(model.leader) != TYPE_BOOL:
			return "MODEL INVALID LEADER"
		if model.has("leader_for") and not (model.leader_for is Array):
			return "MODEL INVALID LEADER_FOR"
	for weapon in profile.weapons:
		for field in ["name", "range_inches", "attacks", "hit_on", "strength", "damage"]:
			if not weapon.has(field):
				return "WEAPON MISSING " + field.to_upper()
		for expression_field in ["attacks", "damage"]:
			if not Dice.parse_expression(weapon.get(expression_field)).valid:
				return "INVALID DICE " + expression_field.to_upper()
	return ""

static func points_total(profile: Dictionary) -> int:
	var total := 0
	for option in profile.get("points", []):
		total += int(option.get("cost", 0))
	return total

# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Shared loader/validator for faction abilities and stratagem declarations.
##
## A profile may keep unit abilities in `abilities` and faction-wide rules in
## `faction_abilities` / `faction_stratagems`.  The engine consumes both through
## this module, so importing another faction remains a data-only change.

const UnitAbilities = preload("res://rules/unit_abilities.gd")
const Stratagems = preload("res://rules/stratagems.gd")

static func abilities(profile: Dictionary) -> Array:
	var result: Array = profile.get("abilities", []).duplicate(true) if profile.get("abilities", []) is Array else []
	var faction_abilities: Variant = profile.get("faction_abilities", [])
	if faction_abilities is Array:
		result.append_array(faction_abilities.duplicate(true))
	var detachment_abilities: Variant = profile.get("detachment_abilities", [])
	if detachment_abilities is Array:
		result.append_array(detachment_abilities.duplicate(true))
	return result

static func stratagems(profile: Dictionary) -> Array:
	var result: Array = []
	var declared: Variant = profile.get("faction_stratagems", [])
	if not (declared is Array):
		return result
	for value in declared:
		if value is Dictionary:
			result.append(value.duplicate(true))
		else:
			var definition := Stratagems.definition(str(value))
			if not definition.is_empty():
				result.append(definition)
	return result

static func validate(profile: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for field in ["abilities", "faction_abilities", "detachment_abilities", "faction_stratagems"]:
		if profile.has(field) and not (profile[field] is Array):
			errors.append("INVALID " + field.to_upper())
	errors.append_array(UnitAbilities.validate(abilities(profile)))
	var declared: Variant = profile.get("faction_stratagems", [])
	if declared is Array:
		for value in declared:
			var definition: Dictionary = value.duplicate(true) if value is Dictionary else Stratagems.definition(str(value))
			if definition.is_empty():
				errors.append("UNKNOWN STRATAGEM " + str(value))
				continue
			var error := Stratagems.validate(definition)
			if not error.is_empty():
				errors.append(error + " " + str(value))
	return errors

static func ids(profile: Dictionary) -> Array:
	var result: Array = []
	for ability in abilities(profile):
		result.append(ability)
	return result

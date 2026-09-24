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

## Auras are evaluated from the current snapshot, never cached on recipients.
## Identical aura IDs do not stack. Distances are measured base edge to edge.
static func combat_modifiers(models: Array, recipient: Dictionary, event: String, context: Dictionary = {}) -> Dictionary:
	var active_abilities: Array = recipient.get("ability_ids", []).duplicate(true)
	var seen: Dictionary = {}
	if not _on_table(recipient):
		return UnitAbilities.event_modifiers(active_abilities, event, context)
	for source in models:
		if not _on_table(source) or int(source.get("team", -1)) != int(recipient.get("team", -2)):
			continue
		for ability in source.get("ability_ids", []):
			if not (ability is Dictionary) or not ability.has("aura") or not UnitAbilities.validate([ability]).is_empty():
				continue
			var aura: Dictionary = ability.aura
			if not UnitAbilities._conditions_match(aura.get("when", {}), context):
				continue
			var aura_id := str(ability.id)
			if seen.has(aura_id) or str(aura.event) != event:
				continue
			if not bool(aura.get("include_self", true)) and str(source.get("model_id", "")) == str(recipient.get("model_id", "")):
				continue
			var eligible := true
			for keyword in aura.get("keywords", []):
				if keyword not in recipient.get("keywords", []) and keyword not in recipient.get("faction_keywords", []):
					eligible = false
			if not eligible:
				continue
			var gap := _position(source).distance_to(_position(recipient)) - float(source.get("radius", 0.0)) - float(recipient.get("radius", 0.0))
			if gap > float(aura.radius_inches) + 0.00001:
				continue
			seen[aura_id] = true
			active_abilities.append({"id": aura_id, "modifiers": aura.modifiers})
	return UnitAbilities.event_modifiers(active_abilities, event, context)

static func _on_table(model: Dictionary) -> bool:
	return str(model.get("reserve_status", "deployed")) == "deployed" and str(model.get("embarked_in", "")).is_empty() and float(model.get("wounds", 1)) > 0

static func _position(model: Dictionary) -> Vector2:
	var position: Variant = model.get("position", Vector2.ZERO)
	return position if position is Vector2 else Vector2(float(position[0]), float(position[1]))

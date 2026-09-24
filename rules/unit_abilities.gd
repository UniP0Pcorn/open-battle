# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Small, data-driven ability modifier layer. Text descriptions stay external.

const DEFINITIONS := {
	"stealth": {"cover_bonus": 1},
	"scout_6": {"prebattle_move_inches": 6.0},
	"scout_9": {"prebattle_move_inches": 9.0},
	"deep_strike": {},
	"lone_operator": {},
	"objective_control_plus_1": {"objective_control_bonus": 1},
	"leadership_plus_1": {"leadership_bonus": 1},
	"reroll_hit": {"hit_rerolls": 1},
	"reroll_hit_ones": {"hit_reroll_ones": 1},
	"reroll_wound": {"wound_rerolls": 1},
	"reroll_wound_ones": {"wound_reroll_ones": 1},
	"reroll_save": {"save_rerolls": 1},
	"reroll_save_ones": {"save_reroll_ones": 1},
	"invulnerable_4": {"invulnerable_save": 4},
	"invulnerable_5": {"invulnerable_save": 5},
	"feel_no_pain_5": {"feel_no_pain": 5},
	"feel_no_pain_6": {"feel_no_pain": 6},
	"damage_reduction_1": {"damage_reduction": 1},
	"fights_first": {"fights_first": true},
	"advance_and_charge": {"advance_and_charge": true},
	"fall_back_and_shoot": {"fall_back_and_shoot": true},
	"fall_back_and_charge": {"fall_back_and_charge": true},
	"shoot_after_advance": {"shoot_after_advance": true}
}

const ALIASES := {
	"隐匿": "stealth",
	"stealth": "stealth",
	"斥候6": "scout_6",
	"斥候6英寸": "scout_6",
	"scout 6\"": "scout_6",
	"斥候9": "scout_9",
	"斥候9英寸": "scout_9",
	"scout 9\"": "scout_9",
	"深入打击": "deep_strike",
	"deep strike": "deep_strike",
	"独行特工": "lone_operator",
	"lone operative": "lone_operator",
	"重掷命中": "reroll_hit",
	"重掷命中骰": "reroll_hit",
	"重掷命中1": "reroll_hit_ones",
	"重掷命中骰1": "reroll_hit_ones",
	"重掷伤害": "reroll_wound",
	"重掷伤害骰": "reroll_wound",
	"重掷伤害1": "reroll_wound_ones",
	"重掷伤害骰1": "reroll_wound_ones",
	"重掷豁免": "reroll_save",
	"重掷豁免骰": "reroll_save",
	"重掷豁免1": "reroll_save_ones",
	"重掷豁免骰1": "reroll_save_ones",
	"reroll hit": "reroll_hit",
	"reroll hit rolls": "reroll_hit",
	"reroll hit ones": "reroll_hit_ones",
	"reroll wound": "reroll_wound",
	"reroll wound rolls": "reroll_wound",
	"reroll wound ones": "reroll_wound_ones",
	"reroll save": "reroll_save",
	"reroll save rolls": "reroll_save",
	"reroll save ones": "reroll_save_ones",
	"无敌豁免4+": "invulnerable_4",
	"无敌豁免5+": "invulnerable_5",
	"feel no pain 5+": "feel_no_pain_5",
	"feel no pain 6+": "feel_no_pain_6",
	"伤害减免1": "damage_reduction_1",
	"首发": "fights_first",
	"先攻": "fights_first",
	"前进后可冲锋": "advance_and_charge",
	"撤退后可射击": "fall_back_and_shoot",
	"撤退后可冲锋": "fall_back_and_charge",
	"前进后可射击": "shoot_after_advance",
}

static func canonical_id(value: Variant) -> String:
	var text := str(value).strip_edges().to_lower()
	return str(ALIASES.get(text, text))

static func validate(ids: Array) -> Array[String]:
	var errors: Array[String] = []
	for ability_id in ids:
		var definition := _definition_for(ability_id)
		if definition.is_empty():
			errors.append("UNKNOWN ABILITY " + str(ability_id))
			continue
		for modifier in definition.get("modifiers", {}).keys():
			if str(modifier).is_empty():
				errors.append("INVALID ABILITY MODIFIER " + str(ability_id))
	return errors

static func modifiers(ids: Array) -> Dictionary:
	var result := {"cover_bonus": 0, "prebattle_move_inches": 0.0, "objective_control_bonus": 0, "leadership_bonus": 0, "hit_rerolls": 0, "hit_reroll_ones": 0, "wound_rerolls": 0, "wound_reroll_ones": 0, "save_rerolls": 0, "save_reroll_ones": 0, "invulnerable_save": 0, "feel_no_pain": 0, "damage_reduction": 0, "fights_first": false, "advance_and_charge": false, "fall_back_and_shoot": false, "fall_back_and_charge": false, "shoot_after_advance": false}
	for ability_id in ids:
		var definition := _definition_for(ability_id)
		if definition.is_empty():
			continue
		var values: Dictionary = definition.get("modifiers", definition)
		for field in values:
			if not result.has(field):
				result[field] = values[field]
			elif typeof(values[field]) == TYPE_BOOL:
				result[field] = bool(result[field]) or bool(values[field])
			else:
				result[field] += values[field]
	return result

static func event_modifiers(ids: Array, event: String, context: Dictionary = {}) -> Dictionary:
	var result := modifiers(ids)
	for ability in ids:
		var definition := _definition_for(ability)
		var event_data: Dictionary = definition.get("events", {}).get(event, {})
		if event_data is Dictionary:
			var conditions: Dictionary = event_data.get("when", {})
			if not _conditions_match(conditions, context):
				continue
			for field in event_data.get("modifiers", {}):
				if not result.has(field):
					result[field] = event_data.modifiers[field]
				elif typeof(event_data.modifiers[field]) == TYPE_BOOL:
					result[field] = bool(result[field]) or bool(event_data.modifiers[field])
				else:
					result[field] += event_data.modifiers[field]
	return result

static func event_effects(ids: Array, event: String, context: Dictionary = {}) -> Array:
	var result: Array = []
	for ability in ids:
		var definition := _definition_for(ability)
		var event_data: Dictionary = definition.get("events", {}).get(event, {})
		if event_data is Dictionary and _conditions_match(event_data.get("when", {}), context):
			result.append_array(event_data.get("effects", []))
	return result

static func ids_from_profile(profile: Dictionary) -> Array:
	var result: Array = []
	for ability in profile.get("abilities", []):
		if ability is String:
			result.append(canonical_id(ability))
		elif ability is Dictionary and ability.has("id"):
			result.append(canonical_id(ability.id))
	return result

static func _definition_for(value: Variant) -> Dictionary:
	if value is Dictionary:
		var inline: Dictionary = value.duplicate(true)
		var inline_id := canonical_id(inline.get("id", ""))
		if inline_id.is_empty():
			return {}
		if not inline.has("modifiers") and DEFINITIONS.has(inline_id):
			inline["modifiers"] = DEFINITIONS[inline_id].duplicate(true)
		return inline
	var canonical := canonical_id(value)
	if not DEFINITIONS.has(canonical):
		return {}
	return {"id": canonical, "modifiers": DEFINITIONS[canonical].duplicate(true)}

static func _conditions_match(conditions: Variant, context: Dictionary) -> bool:
	if not (conditions is Dictionary):
		return true
	for field in conditions:
		if not context.has(field) or context[field] != conditions[field]:
			return false
	return true

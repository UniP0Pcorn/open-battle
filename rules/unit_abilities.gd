# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Small, data-driven ability modifier layer. Text descriptions stay external.

const DEFINITIONS := {
	"stealth": {"cover_bonus": 1},
	"scout_6": {"prebattle_move_inches": 6.0},
	"deep_strike": {},
	"lone_operator": {},
	"objective_control_plus_1": {"objective_control_bonus": 1},
	"leadership_plus_1": {"leadership_bonus": 1},
	"reroll_hit_ones": {"hit_rerolls": 1}
}

const ALIASES := {
	"隐匿": "stealth",
	"stealth": "stealth",
	"斥候6": "scout_6",
	"斥候6英寸": "scout_6",
	"scout 6\"": "scout_6",
	"深入打击": "deep_strike",
	"deep strike": "deep_strike",
	"独行特工": "lone_operator",
	"lone operative": "lone_operator",
}

static func canonical_id(value: Variant) -> String:
	var text := str(value).strip_edges().to_lower()
	return str(ALIASES.get(text, text))

static func validate(ids: Array) -> Array[String]:
	var errors: Array[String] = []
	for ability_id in ids:
		var canonical := canonical_id(ability_id)
		if not DEFINITIONS.has(canonical):
			errors.append("UNKNOWN ABILITY " + str(ability_id))
	return errors

static func modifiers(ids: Array) -> Dictionary:
	var result := {"cover_bonus": 0, "prebattle_move_inches": 0.0, "objective_control_bonus": 0, "leadership_bonus": 0, "hit_rerolls": 0}
	for ability_id in ids:
		var canonical := canonical_id(ability_id)
		if not DEFINITIONS.has(canonical):
			continue
		for field in DEFINITIONS[canonical]:
			result[field] += DEFINITIONS[canonical][field]
	return result

static func ids_from_profile(profile: Dictionary) -> Array:
	var result: Array = []
	for ability in profile.get("abilities", []):
		if ability is String:
			result.append(canonical_id(ability))
		elif ability is Dictionary and ability.has("id"):
			result.append(canonical_id(ability.id))
	return result

# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Data-driven weapon keyword normalization and attack context.

const Dice = preload("res://rules/dice.gd")

const ALIASES := {
	"喷射": "torrent",
	"torrent": "torrent",
	"忽略掩体": "ignores_cover",
	"ignores cover": "ignores_cover",
	"速射": "rapid_fire",
	"rapid fire": "rapid_fire",
	"突击": "assault",
	"assault": "assault",
	"危险": "hazardous",
	"hazardous": "hazardous",
	"毁灭伤害": "devastating_wounds",
	"devastating wounds": "devastating_wounds",
	"爆炸": "blast",
	"blast": "blast"
}

static func canonical_id(value: Variant) -> String:
	var text := str(value).strip_edges().to_lower()
	if text.begins_with("速射") and text.substr(2).is_valid_int():
		return "rapid_fire_" + text.substr(2)
	if text.begins_with("rapid fire ") and text.substr(11).is_valid_int():
		return "rapid_fire_" + text.substr(11)
	if text.begins_with("热熔") and text.substr(2).is_valid_int():
		return "melta_" + text.substr(2)
	if text.begins_with("melta ") and text.substr(6).is_valid_int():
		return "melta_" + text.substr(6)
	return str(ALIASES.get(text, text))

static func ids_from_weapon(weapon: Dictionary) -> Array:
	var result: Array = []
	for value in weapon.get("abilities", []):
		result.append(canonical_id(value))
	return result

static func context(weapon: Dictionary, distance: float, cover_bonus: int = 0, target_models: int = 1) -> Dictionary:
	var result := weapon.duplicate(true)
	var ids := ids_from_weapon(result)
	if ids.has("torrent"):
		result.hit_on = 1
	if ids.has("ignores_cover"):
		cover_bonus = 0
	if distance <= float(result.get("range_inches", 0.0)) / 2.0:
		var rapid_bonus := -1
		for keyword in ids:
			if str(keyword).begins_with("rapid_fire_"):
				rapid_bonus = maxi(0, int(str(keyword).trim_prefix("rapid_fire_")))
				break
		if rapid_bonus >= 0:
			result.attacks = _add_expression(result.get("attacks", 1), rapid_bonus)
		elif ids.has("rapid_fire"):
			# Bare rapid fire remains the original prototype shorthand.
			result.attacks = int(result.get("attacks", 1)) * 2
		var melta_bonus := 0
		for keyword in ids:
			if str(keyword).begins_with("melta_"):
				melta_bonus = maxi(melta_bonus, int(str(keyword).trim_prefix("melta_")))
		if melta_bonus > 0:
			result.damage = _add_expression(result.get("damage", 1), melta_bonus)
	if ids.has("hazardous"):
		result.hazardous = true
		result.hazardous_damage = int(result.get("hazardous_damage", 3))
	if ids.has("devastating_wounds"):
		result.devastating_wounds = true
	if ids.has("blast") and target_models >= 5:
		result.attacks = int(result.get("attacks", 1)) + (target_models / 5)
	return {"weapon": result, "cover_bonus": cover_bonus, "keywords": ids}

static func _add_expression(value: Variant, modifier: int) -> Variant:
	var parsed := Dice.parse_expression(value)
	if not parsed.valid:
		return value
	if int(parsed.sides) == 0:
		return int(parsed.modifier) + modifier
	var expression := (str(parsed.count) if int(parsed.count) != 1 else "") + "D" + str(parsed.sides)
	var total_modifier := int(parsed.modifier) + modifier
	if total_modifier > 0:
		expression += "+" + str(total_modifier)
	elif total_modifier < 0:
		expression += str(total_modifier)
	return expression

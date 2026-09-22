# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Deterministic dice helpers. A seeded RandomNumberGenerator is supplied by callers.

static func d6(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(1, 6)

static func roll_d6(rng: RandomNumberGenerator, count: int, modifier: int = 0) -> Dictionary:
	var rolls: Array = []
	var total := modifier
	for _i in range(maxi(0, count)):
		var result := d6(rng)
		rolls.append(result)
		total += result
	return {"rolls": rolls, "modifier": modifier, "total": total}

static func succeeds(result: int, target: int) -> bool:
	return result >= clampi(target, 2, 6)

static func parse_expression(expression: Variant) -> Dictionary:
	if expression is int:
		return {"count": 0, "sides": 0, "modifier": int(expression), "valid": true}
	if expression is float and is_equal_approx(float(expression), round(float(expression))):
		return {"count": 0, "sides": 0, "modifier": int(expression), "valid": true}
	var text := str(expression).strip_edges().to_upper()
	if text.is_valid_int():
		return {"count": 0, "sides": 0, "modifier": int(text), "valid": true}
	var pattern := RegEx.new()
	pattern.compile("^(\\d*)D(3|6)([+-]\\d+)?$")
	var match := pattern.search(text)
	if match == null:
		return {"count": 0, "sides": 0, "modifier": 0, "valid": false}
	return {
		"count": maxi(1, int(match.get_string(1)) if not match.get_string(1).is_empty() else 1),
		"sides": int(match.get_string(2)),
		"modifier": int(match.get_string(3)) if not match.get_string(3).is_empty() else 0,
		"valid": true
	}

static func roll_expression(rng: RandomNumberGenerator, expression: Variant) -> Dictionary:
	var parsed := parse_expression(expression)
	if not parsed.valid:
		return {"rolls": [], "modifier": 0, "total": 0, "valid": false}
	if int(parsed.sides) == 0:
		return {"rolls": [], "modifier": int(parsed.modifier), "total": int(parsed.modifier), "valid": true}
	var rolls: Array = []
	var total := int(parsed.modifier)
	for _i in range(int(parsed.count)):
		var result := rng.randi_range(1, int(parsed.sides))
		rolls.append(result)
		total += result
	return {"rolls": rolls, "modifier": int(parsed.modifier), "total": total, "valid": true}

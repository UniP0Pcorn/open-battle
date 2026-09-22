# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Data-driven weapon keyword normalization and attack context.

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
	if ids.has("rapid_fire") and distance <= float(result.get("range_inches", 0.0)) / 2.0:
		result.attacks = int(result.get("attacks", 1)) * 2
	if ids.has("hazardous"):
		result.hazardous = true
		result.hazardous_damage = int(result.get("hazardous_damage", 3))
	if ids.has("devastating_wounds"):
		result.devastating_wounds = true
	if ids.has("blast") and target_models >= 5:
		result.attacks = int(result.get("attacks", 1)) + (target_models / 5)
	return {"weapon": result, "cover_bonus": cover_bonus, "keywords": ids}

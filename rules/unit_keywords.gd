# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Canonical unit keyword vocabulary used by profiles and filters.

const ALIASES := {
	"步兵": "infantry", "infantry": "infantry",
	"载具": "vehicle", "vehicle": "vehicle",
	"飞行": "fly", "飞行器": "fly", "fly": "fly",
	"人物": "character", "character": "character",
	"史诗英雄": "epic_hero", "epic hero": "epic_hero",
	"巨兽": "monster", "monster": "monster",
	"战斗服": "battlesuit", "battlesuit": "battlesuit",
	"手雷": "grenades", "grenades": "grenades",
	"兵蜂": "drone", "drone": "drone",
	"外壳": "vehicle_hull", "vehicle hull": "vehicle_hull",
	"坦克": "tank", "tank": "tank",
	"线列": "battleline", "battleline": "battleline"
}

static func canonical_id(value: Variant) -> String:
	var text := str(value).strip_edges().to_lower()
	return str(ALIASES.get(text, text))

static func normalize(values: Array) -> Array:
	var result: Array = []
	for value in values:
		var canonical := canonical_id(value)
		if not result.has(canonical):
			result.append(canonical)
	return result

static func validate(values: Array) -> Array[String]:
	var errors: Array[String] = []
	for value in values:
		if not ALIASES.has(str(value).strip_edges().to_lower()):
			errors.append("UNKNOWN KEYWORD " + str(value))
	return errors

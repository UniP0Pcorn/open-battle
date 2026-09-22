# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Versioned executable ruleset metadata. Datasheets refer to editions by number.

const RULESETS := {
	10: {"id": "wh40k_10e", "edition": 10, "phases": ["COMMAND", "MOVEMENT", "SHOOTING", "CHARGE", "FIGHT"]},
	11: {"id": "wh40k_11e", "edition": 11, "phases": ["COMMAND", "MOVEMENT", "SHOOTING", "CHARGE", "FIGHT"]}
}

static func get_ruleset(edition: int) -> Dictionary:
	return RULESETS.get(edition, {}).duplicate(true)

static func supported(edition: int) -> bool:
	return RULESETS.has(edition)

static func phases(edition: int) -> Array:
	return get_ruleset(edition).get("phases", []).duplicate(true)

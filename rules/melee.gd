# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Melee phase adapter. Attack resolution is shared with the combat rules.

const Combat = preload("res://rules/combat.gd")

static func target_reason(attacker: Dictionary, target: Dictionary, active_team: int, engagement_range: float = 1.0) -> String:
	if attacker.is_empty() or target.is_empty():
		return "INVALID MODEL"
	if int(attacker.get("team", -1)) != active_team:
		return "NOT ACTIVE TEAM"
	if int(target.get("team", -1)) == active_team:
		return "FRIENDLY TARGET"
	if float(attacker.get("distance_to_target", INF)) > engagement_range + 0.0001:
		return "NOT IN ENGAGEMENT"
	return ""

static func resolve_attack(weapon: Dictionary, target: Dictionary, rng: RandomNumberGenerator, hit_rerolls: int = 0) -> Dictionary:
	return Combat.resolve_ranged_attack(weapon, target, rng, hit_rerolls)

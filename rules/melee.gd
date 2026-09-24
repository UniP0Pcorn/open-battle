# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Melee phase adapter. Attack resolution is shared with the combat rules.

const Combat = preload("res://rules/combat.gd")
const Engagement = preload("res://rules/engagement.gd")
const WeaponRules = preload("res://rules/weapon_rules.gd")

static func target_reason(attacker: Dictionary, target: Dictionary, active_team: int, engagement_range: float = 1.0) -> String:
	if attacker.is_empty() or target.is_empty():
		return "INVALID MODEL"
	if int(attacker.get("team", -1)) != active_team:
		return "NOT ACTIVE TEAM"
	if int(target.get("team", -1)) == active_team:
		return "FRIENDLY TARGET"
	var distance := Engagement.separation(attacker, target)
	if is_inf(distance):
		distance = float(attacker.get("distance_to_target", INF))
	if distance > engagement_range + Engagement.EPSILON:
		return "NOT IN ENGAGEMENT"
	return ""

static func resolve_attack(weapon: Dictionary, target: Dictionary, rng: RandomNumberGenerator, hit_rerolls: int = 0, target_keywords: Array = []) -> Dictionary:
	var context := WeaponRules.context(weapon, INF, 0, 1, target_keywords, false)
	return Combat.resolve_ranged_attack(context.weapon, target, rng, hit_rerolls)

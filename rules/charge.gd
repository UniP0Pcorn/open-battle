# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Generic charge validation in inches. Rendering and unit ownership stay outside.

static func charge_distance(rng: RandomNumberGenerator) -> Dictionary:
	var first := rng.randi_range(1, 6)
	var second := rng.randi_range(1, 6)
	return {"rolls": [first, second], "distance": first + second}

static func target_reason(attacker: Dictionary, target: Dictionary, active_team: int, starting_distance: float, charge_roll: int, engagement_range: float = 1.0, can_charge_after_advance: bool = false, can_charge_after_fall_back: bool = false) -> String:
	if attacker.is_empty() or target.is_empty():
		return "INVALID MODEL"
	if int(attacker.get("team", -1)) != active_team:
		return "NOT ACTIVE TEAM"
	if bool(attacker.get("fell_back", false)) and not can_charge_after_fall_back:
		return "FELL BACK"
	if bool(attacker.get("advanced", false)) and not can_charge_after_advance:
		return "ADVANCED CANNOT CHARGE"
	if int(target.get("team", -1)) == active_team:
		return "FRIENDLY TARGET"
	var attacker_radius := float(attacker.get("base_radius", attacker.get("radius", 0.0)))
	var target_radius := float(target.get("base_radius", target.get("radius", 0.0)))
	if starting_distance > float(charge_roll) + attacker_radius + target_radius + engagement_range:
		return "OUT OF CHARGE RANGE"
	return ""

static func end_reason(attacker_position: Vector2, target_position: Vector2, engagement_range: float = 1.0, attacker_radius: float = 0.0, target_radius: float = 0.0) -> String:
	if attacker_position.distance_to(target_position) - attacker_radius - target_radius > engagement_range + 0.0001:
		return "NOT IN ENGAGEMENT"
	return ""

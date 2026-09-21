# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Configurable, generic ranged combat resolver. Values come from project data.

static func wound_target(strength: int, toughness: int) -> int:
	if strength >= toughness * 2:
		return 2
	if strength > toughness:
		return 3
	if strength == toughness:
		return 4
	if strength * 2 <= toughness:
		return 6
	return 5

static func resolve_ranged_attack(weapon: Dictionary, target: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var attacks := int(weapon.get("attacks", 1))
	var hit_on := int(weapon.get("hit_on", 4))
	var strength := int(weapon.get("strength", 4))
	var damage := int(weapon.get("damage", 1))
	var wounds_needed := wound_target(strength, int(target.get("toughness", 4)))
	var hits := 0
	var wounds := 0
	var damage_total := 0
	for _i in range(attacks):
		if rng.randi_range(1, 6) >= hit_on:
			hits += 1
			if rng.randi_range(1, 6) >= wounds_needed:
				wounds += 1
				damage_total += damage
	return {"attacks": attacks, "hits": hits, "wounds": wounds, "damage": damage_total, "wound_on": wounds_needed}

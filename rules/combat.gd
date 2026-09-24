# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Configurable, generic ranged combat resolver. Values come from project data.

const Dice = preload("res://rules/dice.gd")
const UnitAbilities = preload("res://rules/unit_abilities.gd")
const WeaponRules = preload("res://rules/weapon_rules.gd")

static func target_reason(attacker: Dictionary, target: Dictionary, distance: float, weapon: Dictionary, active_team: int, attacker_engaged: bool = false, target_engaged: bool = false) -> String:
	if attacker.is_empty() or target.is_empty():
		return "INVALID MODEL"
	if int(attacker.get("team", -1)) != active_team:
		return "NOT ACTIVE TEAM"
	if bool(attacker.get("advanced", false)) and not WeaponRules.ids_from_weapon(weapon).has("assault"):
		return "ADVANCED WITHOUT ASSAULT"
	var pistol := WeaponRules.ids_from_weapon(weapon).has("pistol")
	if attacker_engaged and not pistol:
		return "ENGAGED NON-PISTOL"
	if attacker_engaged and pistol and not target_engaged:
		return "PISTOL TARGET OUTSIDE ENGAGEMENT"
	if int(target.get("team", -1)) == active_team:
		return "FRIENDLY TARGET"
	var target_abilities := UnitAbilities.ids_from_profile({"abilities": target.get("ability_ids", [])})
	if target_abilities.has("lone_operator") and distance > 12.0:
		return "LONE OPERATOR"
	if distance > float(weapon.get("range_inches", 0.0)):
		return "OUT OF RANGE"
	return ""

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

static func save_target(armor_save: int, armor_penetration: int = 0, invulnerable_save: int = 0) -> int:
	var modified := armor_save + armor_penetration
	if invulnerable_save > 0:
		modified = mini(modified, invulnerable_save)
	return clampi(modified, 2, 7)

static func save_passes(roll: int, target: int) -> bool:
	return target <= 6 and roll >= target

static func resolve_ranged_attack(weapon: Dictionary, target: Dictionary, rng: RandomNumberGenerator, hit_rerolls: int = 0) -> Dictionary:
	var attacks_roll := Dice.roll_expression(rng, weapon.get("attacks", 1))
	var attacks := int(attacks_roll.total) if attacks_roll.valid else 0
	var hit_on := int(weapon.get("hit_on", 4))
	var strength := int(weapon.get("strength", 4))
	var wounds_needed := wound_target(strength, int(target.get("toughness", 4)))
	if int(weapon.get("anti_wound_on", 0)) > 0:
		wounds_needed = int(weapon.get("anti_wound_on", 0))
	var save_needed := save_target(int(target.get("save_on", 7)) + int(target.get("cover_save_bonus", 0)), int(weapon.get("ap", 0)), int(target.get("invulnerable_save", 0)))
	var hits := 0
	var wounds := 0
	var failed_saves := 0
	var damage_total := 0
	var damage_rolls: Array = []
	var hazardous_failures := 0
	var devastating_wounds := 0
	var sustained_hits := 0
	var rerolls_left := maxi(0, hit_rerolls)
	var twin_linked := bool(weapon.get("twin_linked", false))
	var lethal_hits := bool(weapon.get("lethal_hits", false))
	var sustained_bonus := maxi(0, int(weapon.get("sustained_hits", 0)))
	for _i in range(attacks):
		var unmodified_hit_roll := rng.randi_range(1, 6)
		var hit_roll := unmodified_hit_roll
		if hit_roll < hit_on and rerolls_left > 0:
			rerolls_left -= 1
			hit_roll = rng.randi_range(1, 6)
		if hit_roll >= hit_on:
			var hit_events: Array = [hit_roll]
			if hit_roll == 6 and sustained_bonus > 0:
				sustained_hits += sustained_bonus
				for _extra in range(sustained_bonus):
					hit_events.append(0)
			for event_roll in hit_events:
				hits += 1
				var wound_roll := 0
				var wound_success := false
				if lethal_hits and event_roll == 6:
					wound_success = true
				else:
					wound_roll = rng.randi_range(1, 6)
					wound_success = wound_roll >= wounds_needed
					if not wound_success and twin_linked:
						wound_roll = rng.randi_range(1, 6)
						wound_success = wound_roll >= wounds_needed
				if wound_success:
					wounds += 1
					var bypass_save := bool(weapon.get("devastating_wounds", false)) and wound_roll == 6
					if bypass_save:
						devastating_wounds += 1
					if bypass_save or not save_passes(rng.randi_range(1, 6), save_needed):
						failed_saves += 1
						var damage_roll := Dice.roll_expression(rng, weapon.get("damage", 1))
						if damage_roll.valid:
							damage_total += int(damage_roll.total)
							damage_rolls.append(damage_roll)
		if bool(weapon.get("hazardous", false)) and unmodified_hit_roll == 1:
			hazardous_failures += 1
	return {"attacks": attacks, "attack_roll": attacks_roll, "hits": hits, "wounds": wounds, "failed_saves": failed_saves, "damage": damage_total, "damage_rolls": damage_rolls, "hazardous_failures": hazardous_failures, "devastating_wounds": devastating_wounds, "sustained_hits": sustained_hits, "wound_on": wounds_needed, "save_on": save_needed}

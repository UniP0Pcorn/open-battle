# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Data-driven strategy effect layer.
##
## Definitions deliberately contain mechanics identifiers instead of prose.  The
## replay layer can therefore validate and record a strategy without embedding a
## faction book in the command parser.

const CommandPoints = preload("res://rules/command_points.gd")
const UnitAbilities = preload("res://rules/unit_abilities.gd")

const SUPPORTED_EFFECTS := ["REROLL_HIT", "PASS_BATTLE_SHOCK", "FIGHT_NEXT", "REACTION_SHOOT", "TEMPORARY_COVER", "GRANT_ABILITY"]
## Only abilities evaluated dynamically by existing action consumers are grantable.
const GRANTABLE_ABILITIES := ["fall_back_and_shoot", "fall_back_and_charge", "advance_and_charge", "shoot_after_advance", "fights_first", "reroll_hit", "reroll_hit_ones", "reroll_wound", "reroll_wound_ones", "stealth", "lone_operator", "reroll_save", "reroll_save_ones", "invulnerable_4", "invulnerable_5"]

const DEFINITIONS := {
	"command_reroll": {"id": "command_reroll", "cost": 1, "phase": "ANY", "effect": "REROLL_HIT", "timing": "AFTER_ROLL"},
	"insane_bravery": {"id": "insane_bravery", "cost": 1, "phase": "COMMAND", "effect": "PASS_BATTLE_SHOCK", "timing": "BATTLE_SHOCK"},
	"counter_offensive": {"id": "counter_offensive", "cost": 2, "phase": "FIGHT", "effect": "FIGHT_NEXT", "timing": "FIGHT"},
	"fire_overwatch": {"id": "fire_overwatch", "cost": 1, "phase": "ANY", "effect": "REACTION_SHOOT", "timing": "REACTION"},
	"go_to_ground": {"id": "go_to_ground", "cost": 1, "phase": "SHOOTING", "effect": "TEMPORARY_COVER", "timing": "SHOOTING"},
	"smokescreen": {"id": "smokescreen", "cost": 1, "phase": "SHOOTING", "effect": "TEMPORARY_COVER", "timing": "SHOOTING"}
}

const ALIASES := {
	"command-reroll": "command_reroll",
	"command reroll": "command_reroll",
	"insane-bravery": "insane_bravery",
	"counter-offensive": "counter_offensive",
	"fire-overwatch": "fire_overwatch",
	"go-to-ground": "go_to_ground"
}

static func command_reroll() -> Dictionary:
	return definition("command_reroll")

static func normalize_id(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	return str(ALIASES.get(normalized, normalized))

static func definition(id: String) -> Dictionary:
	var normalized := normalize_id(id)
	if not DEFINITIONS.has(normalized):
		return {}
	return DEFINITIONS[normalized].duplicate(true)

static func validate(stratagem: Dictionary) -> String:
	for field in ["id", "cost", "phase", "effect", "timing"]:
		if not stratagem.has(field):
			return "MISSING " + field.to_upper()
	if normalize_id(str(stratagem.id)) != str(stratagem.id):
		return "UNNORMALIZED STRATAGEM"
	if int(stratagem.cost) < 0 or str(stratagem.phase).is_empty() or str(stratagem.effect).is_empty():
		return "INVALID STRATAGEM"
	if str(stratagem.effect) not in SUPPORTED_EFFECTS:
		return "UNSUPPORTED EFFECT"
	for field in ["target_keywords", "excluded_target_keywords"]:
		if not stratagem.has(field):
			continue
		if str(stratagem.effect) not in ["GRANT_ABILITY", "REACTION_SHOOT"] or not (stratagem[field] is Array):
			return "INVALID STRATAGEM TARGET FILTER"
		for keyword in stratagem[field]:
			if not (keyword is String) or keyword.strip_edges().is_empty():
				return "INVALID STRATAGEM TARGET KEYWORD"
	if str(stratagem.effect) == "REACTION_SHOOT" and str(stratagem.timing) == "AFTER_ENEMY_MOVE":
		if str(stratagem.phase) != "MOVEMENT" or typeof(stratagem.get("hit_on")) not in [TYPE_INT, TYPE_FLOAT] or float(stratagem.hit_on) != float(int(stratagem.hit_on)) or int(stratagem.hit_on) not in range(1, 7):
			return "INVALID REACTION SHOOTING"
	if str(stratagem.effect) == "GRANT_ABILITY":
		if str(stratagem.get("target", "")) != "FRIENDLY_UNIT" or str(stratagem.get("duration", "")) not in ["BATTLE", "PHASE", "TURN"]:
			return "INVALID ABILITY TARGET OR DURATION"
		var reaction := str(stratagem.timing) == "AFTER_ENEMY_MOVE" and str(stratagem.phase) == "MOVEMENT"
		if str(stratagem.phase) not in ["COMMAND", "MOVEMENT", "SHOOTING", "CHARGE", "FIGHT"] or (str(stratagem.timing) != str(stratagem.phase) and not reaction):
			return "INVALID ABILITY TIMING"
		var ability: Variant = stratagem.get("ability", "")
		if not (ability is String) or ability not in GRANTABLE_ABILITIES or not UnitAbilities.DEFINITIONS.has(ability):
			return "UNKNOWN GRANTED ABILITY"
	return ""

static func use(stratagem: Dictionary, phase: String, team: int, points: Array) -> Dictionary:
	if str(stratagem.get("effect", "")) == "REACTION_SHOOT" and str(stratagem.get("timing", "")) != "AFTER_ENEMY_MOVE":
		return {"ok": false, "reason": "REACTION SHOOT NOT IMPLEMENTED", "points": points.duplicate(), "effect": ""}
	var schema_error := validate(stratagem)
	if not schema_error.is_empty():
		return {"ok": false, "reason": schema_error, "points": points.duplicate(), "effect": ""}
	var reason := CommandPoints.validate_stratagem(stratagem, phase, team, points)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "points": points.duplicate(), "effect": ""}
	var spent := CommandPoints.spend(points, team, int(stratagem.cost))
	return {
		"ok": true,
		"reason": "",
		"points": spent.points,
		"effect": str(stratagem.get("effect", "")),
		"timing": str(stratagem.get("timing", "")),
		"stratagem_id": str(stratagem.get("id", ""))
	}

## Filters apply to the friendly recipient unit (the shooter for reaction shots).
## Attached units use the union of member keywords; excluded keywords take priority.
static func target_keywords_reason(stratagem: Dictionary, members: Array) -> String:
	var keywords: Array = []
	for model in members:
		keywords.append_array(model.get("keywords", []))
		keywords.append_array(model.get("faction_keywords", []))
	for keyword in stratagem.get("excluded_target_keywords", []):
		if keyword in keywords:
			return "STRATAGEM TARGET EXCLUDED KEYWORD " + str(keyword)
	for keyword in stratagem.get("target_keywords", []):
		if keyword not in keywords:
			return "STRATAGEM TARGET MISSING KEYWORD " + str(keyword)
	return ""

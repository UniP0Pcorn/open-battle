# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Generic objective scoring and victory checks.

const BattleShock = preload("res://rules/battle_shock.gd")
const FactionRules = preload("res://rules/faction_rules.gd")

static func controller(objective: Vector2, models: Array, radius: float, context: Dictionary = {}) -> int:
	var presence := [0, 0]
	var scoring_context := {"phase": "COMMAND", "kind": "OBJECTIVE_CONTROL"}
	for key in context:
		scoring_context[key] = context[key]
	for model in models:
		if not bool(model.get("can_control", true)) or not BattleShock.can_control_objective(model):
			continue
		if model.position.distance_to(objective) <= radius:
			var team := int(model.get("team", -1))
			if team == 0 or team == 1:
				var modifiers := FactionRules.combat_modifiers(models, model, "objective_control", scoring_context)
				presence[team] += maxi(0, int(model.get("objective_control", 1)) + int(modifiers.get("objective_control_bonus", 0)))
	if presence[0] == presence[1]:
		return -1
	return 0 if presence[0] > presence[1] else 1

static func score_objectives(objectives: Array, models: Array, radius: float, context: Dictionary = {}) -> Dictionary:
	var score := [0, 0]
	var controllers: Array = []
	for objective in objectives:
		var point: Vector2 = objective.position if objective is Dictionary else objective
		var value := int(objective.get("points", 1)) if objective is Dictionary else 1
		var team := controller(point, models, radius, context)
		controllers.append(team)
		if team >= 0:
			score[team] += value
	return {"score": score, "controllers": controllers}

static func winner(score: Array, score_to_win: int) -> int:
	for team in range(mini(score.size(), 2)):
		if int(score[team]) >= score_to_win:
			return team
	return -1

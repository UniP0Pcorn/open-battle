# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Data-driven command point and stratagem resource helpers.
const CP_MAX := 10

static func new_state(starting_points: int = 0) -> Array:
	return [maxi(0, starting_points), maxi(0, starting_points)]

static func gain(points: Array, team: int, amount: int = 1, cap: int = CP_MAX) -> Array:
	var next := points.duplicate()
	if team == 0 or team == 1:
		next[team] = mini(cap, int(next[team]) + maxi(0, amount))
	return next

static func can_spend(points: Array, team: int, cost: int) -> bool:
	return team >= 0 and team < points.size() and cost >= 0 and int(points[team]) >= cost

static func spend(points: Array, team: int, cost: int) -> Dictionary:
	if not can_spend(points, team, cost):
		return {"ok": false, "points": points.duplicate()}
	var next := points.duplicate()
	next[team] -= cost
	return {"ok": true, "points": next}

static func validate_stratagem(stratagem: Dictionary, phase: String, team: int, points: Array) -> String:
	for field in ["id", "cost", "phase"]:
		if not stratagem.has(field):
			return "MISSING " + field.to_upper()
	if str(stratagem.phase) != phase and str(stratagem.phase) != "ANY":
		return "WRONG PHASE"
	if not can_spend(points, team, int(stratagem.cost)):
		return "NOT ENOUGH COMMAND POINTS"
	return ""

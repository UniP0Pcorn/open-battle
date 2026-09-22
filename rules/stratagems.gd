# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Small data-driven strategy effect layer.

const CommandPoints = preload("res://rules/command_points.gd")

static func command_reroll() -> Dictionary:
	return {"id": "command_reroll", "cost": 1, "phase": "ANY", "effect": "REROLL_HIT"}

static func use(stratagem: Dictionary, phase: String, team: int, points: Array) -> Dictionary:
	var reason := CommandPoints.validate_stratagem(stratagem, phase, team, points)
	if not reason.is_empty():
		return {"ok": false, "reason": reason, "points": points.duplicate(), "effect": ""}
	var spent := CommandPoints.spend(points, team, int(stratagem.cost))
	return {"ok": true, "reason": "", "points": spent.points, "effect": str(stratagem.get("effect", ""))}

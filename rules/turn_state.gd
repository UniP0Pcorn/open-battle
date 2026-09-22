# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Core battle-round phase state. Data-driven callers can add phase-specific rules later.

const PHASES := ["COMMAND", "MOVEMENT", "SHOOTING", "CHARGE", "FIGHT"]

static func new_state(first_team: int = 0) -> Dictionary:
	return {"round": 1, "active_team": first_team, "phase": PHASES[0], "phase_index": 0, "command_points": [0, 0]}

static func phase_index(phase: String) -> int:
	return PHASES.find(phase)

static func is_valid(state: Dictionary) -> bool:
	var index := int(state.get("phase_index", -1))
	return int(state.get("round", 0)) >= 1 and int(state.get("active_team", -1)) in [0, 1] and index >= 0 and index < PHASES.size() and str(state.get("phase", "")) == PHASES[index]

static func advance(state: Dictionary) -> Dictionary:
	var next := state.duplicate(true)
	var index := int(next.get("phase_index", 0)) + 1
	if index >= PHASES.size():
		index = 0
		next.round = int(next.get("round", 1)) + 1
		next.active_team = 1 - int(next.get("active_team", 0))
		var points: Array = next.get("command_points", [0, 0]).duplicate()
		points[next.active_team] = mini(10, int(points[next.active_team]) + 1)
		next.command_points = points
	next.phase_index = index
	next.phase = PHASES[index]
	return next

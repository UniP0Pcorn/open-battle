# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Canonical command envelope and phase contract shared by saves, replay and servers.

const KINDS := ["MOVE", "ADVANCE", "FALL_BACK", "DEPLOY_RESERVE", "SCOUT", "EMBARK", "DISEMBARK", "TRANSPORT_MOVE", "SHOOT", "CHARGE", "FIGHT", "PHASE_ADVANCE", "END_TURN", "BATTLE_SHOCK", "HAZARDOUS", "STRATAGEM"]
const PHASES := ["COMMAND", "MOVEMENT", "SHOOTING", "CHARGE", "FIGHT"]
const PHASE_BY_KIND := {
	"MOVE": "MOVEMENT",
	"ADVANCE": "MOVEMENT",
	"FALL_BACK": "MOVEMENT",
	"DEPLOY_RESERVE": "MOVEMENT",
	"SCOUT": "COMMAND",
	"EMBARK": "MOVEMENT",
	"DISEMBARK": "MOVEMENT",
	"TRANSPORT_MOVE": "MOVEMENT",
	"SHOOT": "SHOOTING",
	"CHARGE": "CHARGE",
	"FIGHT": "FIGHT"
}

static func validate_entry(entry: Dictionary) -> String:
	if not entry.has("sequence") or int(entry.get("sequence", -1)) < 0:
		return "INVALID SEQUENCE"
	if int(entry.get("team", -1)) not in [0, 1]:
		return "INVALID TEAM"
	var kind := str(entry.get("kind", ""))
	if not KINDS.has(kind):
		return "UNKNOWN COMMAND"
	if not (entry.get("payload", null) is Dictionary):
		return "INVALID PAYLOAD"
	return validate_payload(kind, entry.payload)

static func validate_payload(kind: String, payload: Dictionary) -> String:
	match kind:
		"MOVE", "FALL_BACK":
			if str(payload.get("unit_id", "")).is_empty() or not _numbers(payload.get("delta", []), 2):
				return "INVALID MOVE"
		"ADVANCE":
			if str(payload.get("unit_id", "")).is_empty() or not _nonnegative_int(payload.get("roll", -1)) or int(payload.get("roll", 0)) < 1 or int(payload.get("roll", 0)) > 6:
				return "INVALID ADVANCE"
		"DEPLOY_RESERVE":
			if str(payload.get("unit_id", "")).is_empty() or not (payload.get("positions", null) is Array) or payload.positions.is_empty():
				return "INVALID RESERVE ARRIVAL"
			for position in payload.positions:
				if not _numbers(position, 2):
					return "INVALID RESERVE ARRIVAL"
		"SCOUT":
			if str(payload.get("unit_id", "")).is_empty() or not _numbers(payload.get("delta", []), 2):
				return "INVALID SCOUT"
		"EMBARK":
			if str(payload.get("unit_id", "")).is_empty() or str(payload.get("transport_id", "")).is_empty():
				return "INVALID EMBARK"
		"DISEMBARK":
			if str(payload.get("unit_id", "")).is_empty() or not (payload.get("positions", null) is Array) or payload.positions.is_empty():
				return "INVALID DISEMBARK"
			for position in payload.positions:
				if not _numbers(position, 2):
					return "INVALID DISEMBARK"
		"TRANSPORT_MOVE":
			if str(payload.get("transport_id", "")).is_empty() or not _numbers(payload.get("delta", []), 2):
				return "INVALID TRANSPORT MOVE"
		"SHOOT", "FIGHT":
			if not _model_ref(payload, "attacker_id", "attacker") or not _model_ref(payload, "target_id", "target"):
				return "INVALID DAMAGE EVENT"
			if bool(payload.get("intent", false)):
				if str(payload.get("weapon", "")).is_empty():
					return "MISSING WEAPON"
				if payload.has("hazardous_damage") and not _nonnegative_int(payload.hazardous_damage):
					return "INVALID HAZARDOUS EVENT"
				if payload.has("hazardous_feel_no_pain_rolls") and not _dice_rolls(payload.hazardous_feel_no_pain_rolls):
					return "INVALID FEEL NO PAIN RESULT"
				return ""
			if not _nonnegative_int(payload.get("damage", -1)):
				return "INVALID DAMAGE EVENT"
			if payload.has("feel_no_pain_rolls") and not _dice_rolls(payload.feel_no_pain_rolls):
				return "INVALID FEEL NO PAIN RESULT"
			if payload.has("hazardous_damage") and not _nonnegative_int(payload.hazardous_damage):
				return "INVALID HAZARDOUS EVENT"
			if payload.has("hazardous_feel_no_pain_rolls") and not _dice_rolls(payload.hazardous_feel_no_pain_rolls):
				return "INVALID FEEL NO PAIN RESULT"
		"CHARGE":
			if not _nonnegative_int(payload.get("model", -1)) or not _nonnegative_int(payload.get("target", -1)) or not _numbers(payload.get("to", []), 2):
				return "INVALID CHARGE"
		"BATTLE_SHOCK":
			if str(payload.get("unit_id", "")).is_empty() or typeof(payload.get("passed", null)) != TYPE_BOOL:
				return "INVALID BATTLE SHOCK"
		"HAZARDOUS":
			if not _nonnegative_int(payload.get("attacker", -1)) or not _nonnegative_int(payload.get("damage", -1)):
				return "INVALID HAZARDOUS EVENT"
			if payload.has("feel_no_pain_rolls") and not _dice_rolls(payload.feel_no_pain_rolls):
				return "INVALID FEEL NO PAIN RESULT"
		"STRATAGEM":
			if str(payload.get("id", "")).is_empty() or str(payload.get("phase", "")).is_empty():
				return "INVALID STRATAGEM"
		"PHASE_ADVANCE":
			var from_phase := str(payload.get("from", ""))
			var to_phase := str(payload.get("to", ""))
			if not PHASES.has(from_phase) or not PHASES.has(to_phase):
				return "INVALID PHASE TRANSITION"
			if _next_phase(from_phase) != to_phase:
				return "INVALID PHASE TRANSITION"
		"END_TURN":
			pass
	return ""

static func validate_for_state(entry: Dictionary, state: Dictionary) -> String:
	var error := validate_entry(entry)
	if not error.is_empty():
		return error
	var kind := str(entry.kind)
	if int(entry.team) != int(state.get("active_team", -1)):
		return "NOT ACTIVE TEAM"
	if PHASE_BY_KIND.has(kind) and str(state.get("phase", "")) != str(PHASE_BY_KIND[kind]):
		return "INVALID PHASE"
	if kind == "PHASE_ADVANCE":
		if str(state.get("phase", "")) != str(entry.payload.get("from", "")):
			return "INVALID PHASE"
	return ""

static func _next_phase(phase: String) -> String:
	var index := PHASES.find(phase)
	if index < 0:
		return ""
	return PHASES[(index + 1) % PHASES.size()]

static func _nonnegative_int(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and int(value) >= 0 and float(value) == float(int(value))

static func _numbers(value: Variant, expected_size: int) -> bool:
	if not (value is Array) or value.size() != expected_size:
		return false
	for item in value:
		if typeof(item) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(item)):
			return false
	return true

static func _dice_rolls(value: Variant) -> bool:
	if not (value is Array):
		return false
	for roll in value:
		if typeof(roll) not in [TYPE_INT, TYPE_FLOAT] or float(roll) != float(int(roll)) or int(roll) < 1 or int(roll) > 6:
			return false
	return true

static func _model_ref(payload: Dictionary, id_key: String, index_key: String) -> bool:
	var model_id := str(payload.get(id_key, ""))
	if not model_id.is_empty():
		return true
	return _nonnegative_int(payload.get(index_key, -1))

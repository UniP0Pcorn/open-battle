# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Leader/bodyguard attachment state shared by roster, replay and clients.

const Reserves = preload("res://rules/reserves.gd")
const Transports = preload("res://rules/transports.gd")

static func group_id(model: Dictionary) -> String:
	var attached_to := str(model.get("attached_to", ""))
	return attached_to if not attached_to.is_empty() else str(model.get("unit_id", ""))

static func is_leader(model: Dictionary) -> bool:
	var leader_for: Variant = model.get("leader_for", [])
	return bool(model.get("leader", false)) or (leader_for is Array and not leader_for.is_empty())

static func attach_reason(models: Array, leader_unit_id: String, bodyguard_unit_id: String, team: int) -> String:
	if leader_unit_id.is_empty() or bodyguard_unit_id.is_empty() or leader_unit_id == bodyguard_unit_id or team not in [0, 1]:
		return "INVALID ATTACHMENT"
	var leaders := _unit_models(models, leader_unit_id)
	var bodyguards := _unit_models(models, bodyguard_unit_id)
	if leaders.is_empty() or bodyguards.is_empty():
		return "UNKNOWN ATTACHMENT UNIT"
	if int(leaders[0].get("team", -1)) != team or int(bodyguards[0].get("team", -1)) != team:
		return "NOT ACTIVE TEAM"
	if not is_leader(leaders[0]):
		return "UNIT IS NOT A LEADER"
	if Reserves.in_reserve(leaders[0]) or Reserves.in_reserve(bodyguards[0]) or Transports.is_embarked(leaders[0]) or Transports.is_embarked(bodyguards[0]):
		return "UNIT UNAVAILABLE"
	if not str(leaders[0].get("attached_to", "")).is_empty():
		return "LEADER ALREADY ATTACHED"
	if not str(leaders[0].get("attached_leader_id", "")).is_empty() or not str(bodyguards[0].get("attached_leader_id", "")).is_empty() or not str(bodyguards[0].get("attached_to", "")).is_empty():
		return "BODYGUARD ALREADY HAS LEADER"
	var allowed_value: Variant = leaders[0].get("leader_for", [])
	var allowed: Array = allowed_value if allowed_value is Array else []
	if not allowed.is_empty() and not allowed.has(bodyguard_unit_id):
		var matches_keyword := false
		var keywords_value: Variant = bodyguards[0].get("keywords", [])
		var keywords: Array = keywords_value if keywords_value is Array else []
		for keyword in keywords:
			if allowed.has(keyword):
				matches_keyword = true
				break
		if not matches_keyword:
			return "BODYGUARD NOT ELIGIBLE"
	return ""

static func detach_reason(models: Array, leader_unit_id: String, team: int) -> String:
	var leaders := _unit_models(models, leader_unit_id)
	if leaders.is_empty():
		return "UNKNOWN ATTACHMENT UNIT"
	if int(leaders[0].get("team", -1)) != team:
		return "NOT ACTIVE TEAM"
	if str(leaders[0].get("attached_to", "")).is_empty():
		return "LEADER NOT ATTACHED"
	return ""

static func _unit_models(models: Array, unit_id: String) -> Array:
	var result: Array = []
	for model in models:
		if str(model.get("unit_id", "")) == unit_id:
			result.append(model)
	return result

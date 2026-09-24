# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Transport-independent room lifecycle around the authoritative battle session.

const BattleSession = preload("res://rules/battle_session.gd")
const RulesetCatalog = preload("res://rules/ruleset_catalog.gd")

const SCHEMA_VERSION := 1
const MAX_PLAYERS := 2
const WAITING := "WAITING"
const ACTIVE := "ACTIVE"
const FINISHED := "FINISHED"
const ABANDONED := "ABANDONED"

static func create(room_id: String, edition: int = 11, points_limit: int = 1000, mission_id: String = "control_center", terrain: Array = []) -> Dictionary:
	var ruleset := RulesetCatalog.get_ruleset(edition)
	if room_id.strip_edges().is_empty() or ruleset.is_empty() or points_limit < 1:
		return {}
	return {
		"schema_version": SCHEMA_VERSION,
		"id": room_id,
		"status": WAITING,
		"edition": edition,
		"ruleset_id": str(ruleset.get("id", "")),
		"points_limit": points_limit,
		"mission_id": mission_id,
		"terrain": terrain.duplicate(true),
		"players": [],
		"session": {}
	}

static func join(room: Dictionary, player_id: String, preferred_team: int = -1) -> Dictionary:
	var error := validate(room)
	if not error.is_empty():
		return _failure(error, room)
	if room.status != WAITING:
		return _failure("ROOM NOT WAITING", room)
	if player_id.strip_edges().is_empty():
		return _failure("INVALID PLAYER", room)
	var next := room.duplicate(true)
	for player in next.players:
		if str(player.get("id", "")) == player_id:
			return _failure("PLAYER ALREADY JOINED", room)
	if next.players.size() >= MAX_PLAYERS:
		return _failure("ROOM FULL", room)
	var team := _available_team(next.players, preferred_team)
	if team < 0:
		return _failure("TEAM UNAVAILABLE", room)
	next.players.append({"id": player_id, "team": team, "ready": false})
	return {"ok": true, "reason": "", "room": next, "team": team}

static func set_ready(room: Dictionary, player_id: String, ready: bool = true) -> Dictionary:
	var error := validate(room)
	if not error.is_empty():
		return _failure(error, room)
	if room.status != WAITING:
		return _failure("ROOM NOT WAITING", room)
	var next := room.duplicate(true)
	for player in next.players:
		if str(player.get("id", "")) == player_id:
			player.ready = ready
			return {"ok": true, "reason": "", "room": next}
	return _failure("PLAYER NOT FOUND", room)

static func start(room: Dictionary, models: Array) -> Dictionary:
	var error := validate(room)
	if not error.is_empty():
		return _failure(error, room)
	if room.status != WAITING:
		return _failure("ROOM NOT WAITING", room)
	if room.players.size() != MAX_PLAYERS:
		return _failure("NEED TWO PLAYERS", room)
	for player in room.players:
		if not bool(player.get("ready", false)):
			return _failure("PLAYER NOT READY", room)
	var session := BattleSession.create(models, int(room.edition), 0, room.get("terrain", []))
	if session.is_empty():
		return _failure("SESSION CREATE FAILED", room)
	var next := room.duplicate(true)
	next.status = ACTIVE
	next.session = session
	return {"ok": true, "reason": "", "room": next}

static func submit(room: Dictionary, player_id: String, kind: String, payload: Dictionary) -> Dictionary:
	var error := validate(room)
	if not error.is_empty():
		return _failure(error, room)
	if room.status != ACTIVE or not (room.session is Dictionary) or room.session.is_empty():
		return _failure("ROOM NOT ACTIVE", room)
	var player := _player(room.players, player_id)
	if player.is_empty():
		return _failure("PLAYER NOT FOUND", room)
	var result := BattleSession.submit(room.session, int(player.team), kind, payload)
	if not bool(result.get("ok", false)):
		return {"ok": false, "reason": str(result.get("reason", "COMMAND REJECTED")), "room": room, "state": result.get("state", room.session)}
	var next := room.duplicate(true)
	next.session = result.state
	return {"ok": true, "reason": "", "room": next, "entry": result.entry, "state": result.state}

static func leave(room: Dictionary, player_id: String) -> Dictionary:
	var error := validate(room)
	if not error.is_empty():
		return _failure(error, room)
	var next := room.duplicate(true)
	var found := false
	for index in range(next.players.size()):
		if str(next.players[index].get("id", "")) == player_id:
			found = true
			if next.status == WAITING:
				next.players.remove_at(index)
			else:
				next.status = ABANDONED
				next.ended_by = player_id
			return {"ok": true, "reason": "", "room": next}
	return _failure("PLAYER NOT FOUND", room) if not found else {"ok": true, "reason": "", "room": next}

static func validate(room: Dictionary) -> String:
	if room.is_empty():
		return "INVALID ROOM"
	for field in ["schema_version", "id", "status", "edition", "ruleset_id", "players", "session"]:
		if not room.has(field):
			return "MISSING " + field.to_upper()
	if int(room.schema_version) != SCHEMA_VERSION:
		return "UNSUPPORTED ROOM VERSION"
	if str(room.status) not in [WAITING, ACTIVE, FINISHED, ABANDONED]:
		return "INVALID ROOM STATUS"
	var ruleset := RulesetCatalog.get_ruleset(int(room.edition))
	if ruleset.is_empty() or str(room.ruleset_id) != str(ruleset.get("id", "")):
		return "RULESET MISMATCH"
	if not (room.players is Array) or room.players.size() > MAX_PLAYERS:
		return "INVALID PLAYERS"
	var ids: Dictionary = {}
	var teams: Dictionary = {}
	for player in room.players:
		if not (player is Dictionary) or str(player.get("id", "")).is_empty() or int(player.get("team", -1)) not in [0, 1]:
			return "INVALID PLAYER"
		if ids.has(str(player.id)) or teams.has(int(player.team)):
			return "DUPLICATE PLAYER"
		ids[str(player.id)] = true
		teams[int(player.team)] = true
	return ""

static func public_snapshot(room: Dictionary) -> Dictionary:
	var snapshot := room.duplicate(true)
	if snapshot.has("session") and snapshot.session is Dictionary:
		# Command logs are useful for replay but not needed for a lobby listing.
		var session: Dictionary = snapshot.session.duplicate(true)
		session.erase("command_log")
		snapshot.session = session
	return snapshot

static func _available_team(players: Array, preferred_team: int) -> int:
	var used := {}
	for player in players:
		used[int(player.get("team", -1))] = true
	if preferred_team in [0, 1] and not used.has(preferred_team):
		return preferred_team
	for team in [0, 1]:
		if not used.has(team):
			return team
	return -1

static func _player(players: Array, player_id: String) -> Dictionary:
	for player in players:
		if str(player.get("id", "")) == player_id:
			return player
	return {}

static func _failure(reason: String, room: Dictionary) -> Dictionary:
	return {"ok": false, "reason": reason, "room": room}

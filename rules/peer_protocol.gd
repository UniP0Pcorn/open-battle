# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Transport-neutral P2P envelopes.
##
## WebSocketPeer/ENet are deliberately kept out of this file.  Both transports
## can carry the same envelopes, and reconnecting peers can verify a snapshot
## before they resume sending commands.

const CommandSchema = preload("res://rules/command_schema.gd")

const VERSION := 1
const COMMAND := "COMMAND"
const SNAPSHOT := "SNAPSHOT"
const RECONNECT := "RECONNECT"
const AUTH := "AUTH"

static func command(room_id: String, peer_id: String, session_id: String, sequence: int, ack: int, command_entry: Dictionary, snapshot_hash: String, reconnect_token: String = "") -> Dictionary:
	return {
		"version": VERSION, "kind": COMMAND, "room_id": room_id, "peer_id": peer_id,
		"session_id": session_id, "sequence": sequence, "ack": ack,
		"snapshot_hash": snapshot_hash, "command": command_entry.duplicate(true),
		"reconnect_token": reconnect_token
	}

static func snapshot(room_id: String, peer_id: String, session_id: String, sequence: int, state: Dictionary, reconnect_token: String = "") -> Dictionary:
	return {
		"version": VERSION, "kind": SNAPSHOT, "room_id": room_id, "peer_id": peer_id,
		"session_id": session_id, "sequence": sequence, "ack": sequence,
		"snapshot_hash": hash_snapshot(state), "state": state.duplicate(true),
		"reconnect_token": reconnect_token
	}

static func reconnect(room_id: String, peer_id: String, session_id: String, last_sequence: int, snapshot_hash: String, reconnect_token: String) -> Dictionary:
	return {
		"version": VERSION, "kind": RECONNECT, "room_id": room_id, "peer_id": peer_id,
		"session_id": session_id, "sequence": last_sequence, "ack": last_sequence,
		"snapshot_hash": snapshot_hash, "reconnect_token": reconnect_token
	}

static func auth(peer_id: String, session_id: String, response: Dictionary) -> Dictionary:
	return {
		"version": VERSION, "kind": AUTH, "room_id": "AUTH", "peer_id": peer_id,
		"session_id": session_id, "sequence": 0, "ack": -1, "snapshot_hash": "AUTH",
		"response": response.duplicate(true)
	}

static func validate(packet: Dictionary) -> String:
	for field in ["version", "kind", "room_id", "peer_id", "session_id", "sequence", "ack", "snapshot_hash"]:
		if not packet.has(field):
			return "MISSING " + field.to_upper()
	if int(packet.version) != VERSION:
		return "UNSUPPORTED PEER VERSION"
	if str(packet.kind) not in [COMMAND, SNAPSHOT, RECONNECT, AUTH]:
		return "UNKNOWN PEER MESSAGE"
	for field in ["room_id", "peer_id", "session_id"]:
		if str(packet.get(field, "")).strip_edges().is_empty():
			return "INVALID PEER IDENTITY"
	if int(packet.sequence) < 0 or int(packet.ack) < -1:
		return "INVALID PEER SEQUENCE"
	if str(packet.snapshot_hash).is_empty():
		return "MISSING SNAPSHOT HASH"
	if packet.kind == COMMAND:
		if not (packet.get("command", null) is Dictionary):
			return "MISSING COMMAND"
		var command_error := CommandSchema.validate_entry(packet.command)
		if not command_error.is_empty():
			return command_error
	if packet.kind == SNAPSHOT:
		if not (packet.get("state", null) is Dictionary):
			return "MISSING SNAPSHOT"
		if hash_snapshot(packet.state) != str(packet.snapshot_hash):
			return "SNAPSHOT HASH MISMATCH"
	if packet.kind == RECONNECT and str(packet.get("reconnect_token", "")).is_empty():
		return "MISSING RECONNECT TOKEN"
	if packet.kind == AUTH and not (packet.get("response", null) is Dictionary):
		return "MISSING AUTH RESPONSE"
	return ""

static func sequence_status(last_sequence: int, packet: Dictionary) -> String:
	var error := validate(packet)
	if not error.is_empty():
		return error
	var incoming := int(packet.sequence)
	if incoming == last_sequence + 1:
		return "NEXT"
	if incoming <= last_sequence:
		return "DUPLICATE"
	return "GAP"

static func hash_snapshot(state: Dictionary) -> String:
	var canonical: Variant = _canonical(state)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(JSON.stringify(canonical).to_utf8_buffer())
	return context.finish().hex_encode()

static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		var keys: Array = value.keys()
		keys.sort()
		for key in keys:
			result[str(key)] = _canonical(value[key])
		return result
	if value is Array:
		var array_result: Array = []
		for item in value:
			array_result.append(_canonical(item))
		return array_result
	if value is Vector2:
		return [value.x, value.y]
	return value

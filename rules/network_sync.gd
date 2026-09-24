# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Deterministic host/client synchronization adapter.
##
## This module is deliberately independent of ENet.  The host validates every
## command against the current snapshot before Room/BattleSession applies it;
## clients accept only snapshots whose content hash matches their envelope.

const PeerProtocol = preload("res://rules/peer_protocol.gd")
const Room = preload("res://rules/room.gd")

static func host_command(room: Dictionary, packet: Dictionary, expected_peer_id: String) -> Dictionary:
	var packet_error := PeerProtocol.validate(packet)
	if not packet_error.is_empty():
		return {"ok": false, "reason": packet_error, "room": room}
	if str(packet.kind) != PeerProtocol.COMMAND:
		return {"ok": false, "reason": "NOT A COMMAND", "room": room}
	if str(packet.room_id) != str(room.get("id", "")) or str(packet.peer_id) != expected_peer_id:
		return {"ok": false, "reason": "PEER ROOM MISMATCH", "room": room}
	if str(packet.snapshot_hash) != PeerProtocol.hash_snapshot(room.get("session", {})):
		return {"ok": false, "reason": "STALE SNAPSHOT", "room": room}
	var command: Dictionary = packet.command
	var expected_sequence := int(room.get("session", {}).get("command_log", []).size())
	if int(packet.sequence) != expected_sequence:
		return {"ok": false, "reason": "COMMAND SEQUENCE GAP", "room": room}
	var submitted := Room.submit(room, expected_peer_id, str(command.get("kind", "")), command.get("payload", {}))
	if not bool(submitted.get("ok", false)):
		return submitted
	var next_room: Dictionary = submitted.room
	var snapshot := PeerProtocol.snapshot(str(next_room.id), expected_peer_id, str(packet.session_id), int(next_room.session.get("command_log", []).size()) - 1, next_room.session, str(packet.get("reconnect_token", "")))
	return {"ok": true, "reason": "", "room": next_room, "entry": submitted.entry, "snapshot": snapshot}

static func accept_snapshot(local_state: Dictionary, packet: Dictionary) -> Dictionary:
	var packet_error := PeerProtocol.validate(packet)
	if not packet_error.is_empty():
		return {"ok": false, "reason": packet_error, "state": local_state}
	if str(packet.kind) != PeerProtocol.SNAPSHOT:
		return {"ok": false, "reason": "NOT A SNAPSHOT", "state": local_state}
	return {"ok": true, "reason": "", "state": packet.state.duplicate(true)}

static func reconnect_snapshot(room: Dictionary, player_id: String, token: String, last_sequence: int = -1) -> Dictionary:
	return Room.reconnect(room, player_id, token, last_sequence)

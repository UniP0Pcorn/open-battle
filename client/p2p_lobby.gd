# SPDX-License-Identifier: AGPL-3.0-only
extends Node
## Thin lobby/session controller over P2PTransport and the authoritative Room.

const AccountIdentity = preload("res://rules/account_identity.gd")
const AccountStore = preload("res://rules/account_store.gd")
const PeerProtocol = preload("res://rules/peer_protocol.gd")
const P2PTransport = preload("res://client/p2p_transport.gd")
const Room = preload("res://rules/room.gd")
const NetworkSync = preload("res://rules/network_sync.gd")

signal lobby_changed(room: Dictionary)
signal battle_snapshot_received(state: Dictionary)
signal error_occurred(reason: String)
signal nat_status_changed(result: Dictionary)

var transport: Node
var room: Dictionary = {}
var identity: Dictionary = {}
var player_id := ""
var reconnect_token := ""
var is_host := false
var pending_join := false
var trusted_identities: Dictionary = {}
var authenticated_peers: Dictionary = {}

func _ready() -> void:
	transport = P2PTransport.new()
	add_child(transport)
	transport.packet_received.connect(_on_packet_received)
	transport.peer_state_changed.connect(_on_peer_state_changed)
	transport.transport_error.connect(_on_transport_error)
	transport.nat_status_changed.connect(func(result: Dictionary): nat_status_changed.emit(result))
	for trusted in AccountStore.load_trusted_identities():
		trusted_identities[str(trusted.fingerprint)] = trusted.duplicate(true)

func set_identity(value: Dictionary) -> String:
	var error := AccountIdentity.validate(value)
	if not error.is_empty():
		return error
	identity = value.duplicate(true)
	player_id = str(identity.account_id)
	transport.set_identity(identity)
	return ""

func trust_identity(value: Dictionary) -> String:
	var error := AccountIdentity.validate(value)
	if not error.is_empty():
		return error
	trusted_identities[str(value.fingerprint)] = value.duplicate(true)
	return AccountStore.save_trusted_identity(value)

func host_room(room_id: String, port: int, edition: int = 11, points_limit: int = 1000, mission_id: String = "control_center", terrain: Array = [], use_upnp: bool = false) -> String:
	if identity.is_empty():
		return "IDENTITY REQUIRED"
	var mission_config := _load_mission_config(mission_id, terrain)
	room = Room.create(room_id, edition, points_limit, mission_id, mission_config.terrain, mission_config.objectives, mission_config.control_radius, mission_config.score_to_win)
	if room.is_empty():
		return "ROOM CREATE FAILED"
	is_host = true
	var error: String = transport.host(port, 1, use_upnp)
	if not error.is_empty():
		return error
	var joined := Room.join(room, player_id, 0)
	if not bool(joined.get("ok", false)):
		return str(joined.get("reason", "LOCAL JOIN FAILED"))
	room = joined.room
	reconnect_token = str(joined.get("reconnect_token", ""))
	lobby_changed.emit(Room.public_snapshot(room))
	return ""

func connect_to_room(room_id: String, address: String, port: int) -> String:
	if identity.is_empty():
		return "IDENTITY REQUIRED"
	room = Room.create(room_id)
	if room.is_empty():
		return "ROOM CREATE FAILED"
	is_host = false
	pending_join = true
	var error: String = transport.connect_to_host(address, port)
	if not error.is_empty():
		pending_join = false
	return error

func set_ready(ready: bool = true) -> String:
	var result := Room.set_ready(room, player_id, ready)
	if not bool(result.get("ok", false)):
		return str(result.get("reason", "READY FAILED"))
	room = result.room
	if not is_host:
		return _send_lobby("READY", {"ready": ready})
	lobby_changed.emit(Room.public_snapshot(room))
	return ""

func start(models: Array) -> String:
	if not is_host:
		return "HOST ONLY"
	var result := Room.start(room, models)
	if not bool(result.get("ok", false)):
		return str(result.get("reason", "START FAILED"))
	room = result.room
	lobby_changed.emit(Room.public_snapshot(room))
	return transport.broadcast(PeerProtocol.snapshot(str(room.id), player_id, _session_id(), _last_sequence(), room.session, reconnect_token))

func submit_command(kind: String, payload: Dictionary) -> String:
	if room.is_empty() or str(room.status) != Room.ACTIVE:
		return "ROOM NOT ACTIVE"
	if is_host:
		return _submit_host_command(player_id, kind, payload)
	var sequence := int(room.session.get("command_log", []).size())
	var local_team := -1
	for player in room.get("players", []):
		if str(player.get("id", "")) == player_id:
			local_team = int(player.get("team", -1))
	if local_team not in [0, 1]:
		return "PLAYER TEAM UNKNOWN"
	var entry := {"sequence": sequence, "team": local_team, "kind": kind, "payload": payload.duplicate(true)}
	var packet := PeerProtocol.command(str(room.id), player_id, _session_id(), sequence, sequence - 1, entry, PeerProtocol.hash_snapshot(room.session), reconnect_token)
	return transport.send(packet, 1)

func reconnect() -> String:
	if is_host or room.is_empty() or reconnect_token.is_empty():
		return "RECONNECT NOT AVAILABLE"
	var packet := PeerProtocol.reconnect(str(room.id), player_id, _session_id(), _last_sequence(), PeerProtocol.hash_snapshot(room.session), reconnect_token)
	return transport.send(packet, 1)

func _send_lobby(action: String, payload: Dictionary = {}) -> String:
	return transport.send(PeerProtocol.lobby(str(room.id), player_id, _session_id(), action, payload), 1)

func _submit_host_command(actor_id: String, kind: String, payload: Dictionary) -> String:
	var actor_team := -1
	for player in room.get("players", []):
		if str(player.get("id", "")) == actor_id:
			actor_team = int(player.get("team", -1))
	var sequence := int(room.session.get("command_log", []).size())
	var command := {"sequence": sequence, "team": actor_team, "kind": kind, "payload": payload}
	var packet := PeerProtocol.command(str(room.id), actor_id, _session_id(), sequence, sequence - 1, command, PeerProtocol.hash_snapshot(room.session))
	var result := NetworkSync.host_command(room, packet, actor_id) if kind in ["STRATAGEM", "ADVANCE", "CHARGE", "SHOOT", "FIGHT", "BATTLE_SHOCK"] else Room.submit(room, actor_id, kind, payload)
	if not bool(result.get("ok", false)):
		return str(result.get("reason", "COMMAND REJECTED"))
	room = result.room
	var snapshot_packet := PeerProtocol.snapshot(str(room.id), player_id, _session_id(), _last_sequence(), room.session, reconnect_token)
	transport.broadcast(snapshot_packet)
	battle_snapshot_received.emit(room.session)
	lobby_changed.emit(Room.public_snapshot(room))
	return ""

func _on_packet_received(peer_id: int, packet: Dictionary) -> void:
	match str(packet.kind):
		"LOBBY":
			_handle_lobby(peer_id, packet)
		"COMMAND":
			if is_host:
				if str(authenticated_peers.get(peer_id, "")) != str(packet.peer_id):
					error_occurred.emit("AUTH REQUIRED")
					return
				var sync_result := NetworkSync.host_command(room, packet, str(packet.peer_id))
				if bool(sync_result.get("ok", false)):
					room = sync_result.room
					transport.broadcast(sync_result.snapshot)
					lobby_changed.emit(Room.public_snapshot(room))
				else:
					error_occurred.emit(str(sync_result.get("reason", "COMMAND REJECTED")))
		"AUTH":
			if is_host:
				_handle_auth(peer_id, packet)
		"SNAPSHOT":
			if not is_host:
				var snapshot_result := NetworkSync.accept_snapshot(room.session, packet)
				if bool(snapshot_result.get("ok", false)):
					room.session = snapshot_result.state
					if int(room.session.get("winner", -1)) >= 0:
						room.status = Room.FINISHED
						room.winner = int(room.session.winner)
					battle_snapshot_received.emit(room.session)
					lobby_changed.emit(Room.public_snapshot(room))
				else:
					error_occurred.emit(str(snapshot_result.get("reason", "SNAPSHOT REJECTED")))
		"RECONNECT":
			if is_host:
				if str(authenticated_peers.get(peer_id, "")) != str(packet.peer_id):
					error_occurred.emit("AUTH REQUIRED")
					return
				var result := Room.reconnect(room, str(packet.peer_id), str(packet.get("reconnect_token", "")), int(packet.sequence))
				if bool(result.get("ok", false)):
					room = result.room
					transport.send(result.snapshot, peer_id)

func _handle_lobby(peer_id: int, packet: Dictionary) -> void:
		if not is_host:
			if str(packet.action) == "AUTH_OK":
				if str(room.get("status", Room.WAITING)) == Room.ACTIVE and not reconnect_token.is_empty():
					var reconnect_packet := PeerProtocol.reconnect(str(room.id), player_id, _session_id(), _last_sequence(), PeerProtocol.hash_snapshot(room.session), reconnect_token)
					transport.send(reconnect_packet, 1)
				else:
					_send_lobby("JOIN", {"preferred_team": -1})
			elif str(packet.action) == "JOINED":
				room = packet.payload.room.duplicate(true)
				reconnect_token = str(packet.payload.get("reconnect_token", ""))
				lobby_changed.emit(room)
			elif str(packet.action) == "UPDATE":
				room = packet.payload.room.duplicate(true)
				lobby_changed.emit(room)
			return
		var action := str(packet.action)
		if str(authenticated_peers.get(peer_id, "")) != str(packet.peer_id):
			transport.send(PeerProtocol.lobby(str(room.id), player_id, _session_id(), "ERROR", {"reason": "AUTH REQUIRED"}), peer_id)
			return
		if action == "JOIN":
			var joined := Room.join(room, str(packet.peer_id), int(packet.payload.get("preferred_team", -1)))
			if bool(joined.get("ok", false)):
				room = joined.room
				transport.send(PeerProtocol.lobby(str(room.id), player_id, _session_id(), "JOINED", {"room": Room.public_snapshot(room), "reconnect_token": joined.reconnect_token}), peer_id)
		elif action == "READY":
			var ready := Room.set_ready(room, str(packet.peer_id), bool(packet.payload.get("ready", true)))
			if bool(ready.get("ok", false)):
				room = ready.room
				transport.send(PeerProtocol.lobby(str(room.id), player_id, _session_id(), "UPDATE", {"room": Room.public_snapshot(room)}), peer_id)

func _handle_auth(peer_id: int, packet: Dictionary) -> void:
	var response: Dictionary = packet.get("response", {})
	var public_record: Dictionary = response.get("public_record", {})
	var fingerprint := str(public_record.get("fingerprint", ""))
	var trusted: Dictionary = trusted_identities.get(fingerprint, {})
	if trusted.is_empty() or str(packet.get("peer_id", "")) != str(response.get("account_id", "")) or not AccountIdentity.verify(trusted, response, _auth_nonce()):
		transport.send(PeerProtocol.lobby(str(room.id), player_id, _session_id(), "ERROR", {"reason": "AUTH REJECTED"}), peer_id)
		return
	authenticated_peers[peer_id] = str(trusted.account_id)
	transport.send(PeerProtocol.lobby(str(room.id), player_id, _session_id(), "AUTH_OK"), peer_id)

func _on_peer_state_changed(peer_id: int, connected: bool) -> void:
	if not connected:
		if is_host:
			var disconnected_id := str(authenticated_peers.get(peer_id, ""))
			authenticated_peers.erase(peer_id)
			if not disconnected_id.is_empty():
				var dropped := Room.drop_connection(room, disconnected_id)
				if bool(dropped.get("ok", false)):
					room = dropped.room
					lobby_changed.emit(Room.public_snapshot(room))
		else:
			status_message("连接已断开，可使用重连入口恢复。")
		return
	if connected and not is_host and pending_join:
		pending_join = false
		var response := AccountIdentity.challenge(identity, _auth_nonce())
		response["public_record"] = AccountIdentity.public_record(identity)
		transport.send(PeerProtocol.auth(player_id, _session_id(), response), 1)

func status_message(value: String) -> void:
	error_occurred.emit(value)

func _on_transport_error(reason: String) -> void:
	error_occurred.emit(reason)

func _session_id() -> String:
	return PeerProtocol.hash_snapshot({"room_id": str(room.get("id", "")), "edition": int(room.get("edition", 0)), "mission": str(room.get("mission_id", ""))})

func _auth_nonce() -> String:
	return PeerProtocol.hash_snapshot({"room_id": str(room.get("id", "")), "auth": "open-battle-p2p"})

func _last_sequence() -> int:
	return maxi(0, int(room.get("session", {}).get("command_log", []).size()) - 1)

func _load_mission_config(mission_id: String, terrain_override: Array) -> Dictionary:
	var config := {"terrain": terrain_override.duplicate(true), "objectives": [], "control_radius": 3.0, "score_to_win": 5}
	var selected: Dictionary = {}
	var directory := DirAccess.open("res://data/missions")
	if directory != null:
		for filename in directory.get_files():
			if not filename.to_lower().ends_with(".json"):
				continue
			var parsed = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions/" + filename))
			if parsed is Dictionary and (str(parsed.get("id", "")) == mission_id or filename.get_basename() == mission_id):
				selected = parsed
				break
	if selected.is_empty():
		var fallback = JSON.parse_string(FileAccess.get_file_as_string("res://data/missions/control_center.json"))
		if fallback is Dictionary:
			selected = fallback
	config.control_radius = float(selected.get("control_radius_inches", config.control_radius))
	config.score_to_win = int(selected.get("score_to_win", config.score_to_win))
	if config.terrain.is_empty():
		config.terrain = selected.get("terrain", []).duplicate(true)
	for objective in selected.get("objectives", []):
		if not (objective is Dictionary):
			continue
		var position: Variant = objective.get("position", null)
		if position is Vector2:
			config.objectives.append({"id": str(objective.get("id", "")), "position": position, "points": int(objective.get("points", 1))})
		elif objective.get("position_inches", []).size() >= 2:
			config.objectives.append({"id": str(objective.get("id", "")), "position": Vector2(float(objective.position_inches[0]), float(objective.position_inches[1])), "points": int(objective.get("points", 1))})
	return config

func close_room() -> void:
	transport.close()
	room = {}
	is_host = false
	pending_join = false
	authenticated_peers.clear()
	reconnect_token = ""
	lobby_changed.emit({})

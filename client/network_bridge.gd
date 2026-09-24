# SPDX-License-Identifier: AGPL-3.0-only
extends Node
## Persistent network facade shared by the lobby and tabletop scenes.

const P2PLobby = preload("res://client/p2p_lobby.gd")

signal lobby_changed(room: Dictionary)
signal battle_snapshot_received(state: Dictionary)
signal error_occurred(reason: String)
signal nat_status_changed(result: Dictionary)

var lobby: Node

func _ready() -> void:
	lobby = P2PLobby.new()
	add_child(lobby)
	lobby.lobby_changed.connect(func(room: Dictionary): lobby_changed.emit(room))
	lobby.battle_snapshot_received.connect(func(state: Dictionary): battle_snapshot_received.emit(state))
	lobby.error_occurred.connect(func(reason: String): error_occurred.emit(reason))
	lobby.nat_status_changed.connect(func(result: Dictionary): nat_status_changed.emit(result))

func set_identity(identity: Dictionary) -> String:
	return lobby.set_identity(identity)

func trust_identity(identity: Dictionary) -> String:
	return lobby.trust_identity(identity)

func host_room(room_id: String, port: int, edition: int = 11, points_limit: int = 1000, mission_id: String = "control_center", terrain: Array = [], use_upnp: bool = false) -> String:
	return lobby.host_room(room_id, port, edition, points_limit, mission_id, terrain, use_upnp)

func connect_to_room(room_id: String, address: String, port: int) -> String:
	return lobby.connect_to_room(room_id, address, port)

func connect_invite(invite: String, now: int = 0) -> String:
	return lobby.connect_invite(invite, now)

func set_ready(ready: bool = true) -> String:
	return lobby.set_ready(ready)

func start(models: Array) -> String:
	return lobby.start(models)

func submit_command(kind: String, payload: Dictionary) -> String:
	return lobby.submit_command(kind, payload)

func reconnect() -> String:
	return lobby.reconnect()

func room_invite(address: String, expires_at: int) -> String:
	return lobby.room_invite(address, expires_at)

func active_room() -> Dictionary:
	return lobby.room.duplicate(true) if lobby != null and lobby.room is Dictionary else {}

func local_player_team() -> int:
	if lobby == null or not (lobby.room is Dictionary):
		return -1
	for player in lobby.room.get("players", []):
		if str(player.get("id", "")) == str(lobby.player_id):
			return int(player.get("team", -1))
	return -1

func close_room() -> void:
	lobby.close_room()

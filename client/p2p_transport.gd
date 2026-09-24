# SPDX-License-Identifier: AGPL-3.0-only
extends Node
## ENet-backed P2P transport for the transport-neutral peer envelopes.

const PeerProtocol = preload("res://rules/peer_protocol.gd")

signal packet_received(peer_id: int, packet: Dictionary)
signal peer_state_changed(peer_id: int, connected: bool)
signal transport_error(reason: String)

var peer: ENetMultiplayerPeer
var identity: Dictionary = {}

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected)
	multiplayer.connection_failed.connect(_on_connection_failed)

func set_identity(value: Dictionary) -> void:
	identity = value.duplicate(true)

func host(port: int, max_clients: int = 1) -> String:
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_server(port, max_clients)
	if error != OK:
		peer = null
		return "CREATE SERVER FAILED " + str(error)
	multiplayer.multiplayer_peer = peer
	return ""

func connect_to_host(address: String, port: int) -> String:
	if address.strip_edges().is_empty():
		return "INVALID ADDRESS"
	peer = ENetMultiplayerPeer.new()
	var error := peer.create_client(address, port)
	if error != OK:
		peer = null
		return "CREATE CLIENT FAILED " + str(error)
	multiplayer.multiplayer_peer = peer
	return ""

func close() -> void:
	if peer != null:
		peer.close()
		peer = null
	multiplayer.multiplayer_peer = null

func send(packet: Dictionary, target_peer: int = 1) -> String:
	var error := PeerProtocol.validate(packet)
	if not error.is_empty():
		return error
	if multiplayer.multiplayer_peer == null:
		return "TRANSPORT NOT CONNECTED"
	var encoded := JSON.stringify(packet)
	rpc_id(target_peer, "_receive_packet", encoded)
	return ""

func broadcast(packet: Dictionary) -> String:
	var error := PeerProtocol.validate(packet)
	if not error.is_empty():
		return error
	if multiplayer.multiplayer_peer == null:
		return "TRANSPORT NOT CONNECTED"
	rpc("_receive_packet", JSON.stringify(packet))
	return ""

@rpc("any_peer", "call_remote", "reliable")
func _receive_packet(encoded: String) -> void:
	var parsed = JSON.parse_string(encoded)
	if not (parsed is Dictionary):
		transport_error.emit("INVALID PEER JSON")
		return
	var packet: Dictionary = parsed
	var error := PeerProtocol.validate(packet)
	if not error.is_empty():
		transport_error.emit(error)
		return
	packet_received.emit(multiplayer.get_remote_sender_id(), packet)

func _on_peer_connected(peer_id: int) -> void:
	peer_state_changed.emit(peer_id, true)

func _on_peer_disconnected(peer_id: int) -> void:
	peer_state_changed.emit(peer_id, false)

func _on_connected() -> void:
	peer_state_changed.emit(1, true)

func _on_connection_failed() -> void:
	transport_error.emit("CONNECTION FAILED")

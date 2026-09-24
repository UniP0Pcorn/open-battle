# SPDX-License-Identifier: AGPL-3.0-only
extends Node
## WebSocket transport for the opaque relay prototype.

const PeerProtocol = preload("res://rules/peer_protocol.gd")
signal packet_received(peer_id: int, packet: Dictionary)
signal peer_state_changed(peer_id: int, connected: bool)
signal transport_error(reason: String)

var socket := WebSocketPeer.new()
var room_id := ""
var role := ""
var connected := false

func _process(_delta: float) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if connected:
			connected = false
			peer_state_changed.emit(1, false)
		return
	socket.poll()
	var state := socket.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not connected:
		connected = true
		socket.send_text(JSON.stringify({"type": "hello", "room_id": room_id, "role": role}))
		peer_state_changed.emit(1, true)
	while socket.get_available_packet_count() > 0:
		var value := socket.get_packet().get_string_from_utf8()
		var parsed = JSON.parse_string(value)
		if not (parsed is Dictionary):
			transport_error.emit("INVALID RELAY JSON")
			continue
		if str(parsed.get("type", "")) in ["ready", "error"]:
			if str(parsed.get("type", "")) == "error":
				transport_error.emit(str(parsed.get("reason", "RELAY ERROR")))
			continue
		var error := PeerProtocol.validate(parsed)
		if not error.is_empty():
			transport_error.emit(error)
			continue
		packet_received.emit(1, parsed)

func host(url: String, value: String) -> String:
	return _connect(url, value, "host")

func connect_to_host(url: String, value: String) -> String:
	return _connect(url, value, "client")

func _connect(url: String, value: String, value_role: String) -> String:
	close()
	if not url.begins_with("ws://") and not url.begins_with("wss://"):
		return "INVALID RELAY URL"
	room_id = value
	role = value_role
	var error := socket.connect_to_url(url)
	return "RELAY CONNECT FAILED " + str(error) if error != OK else ""

func send(packet: Dictionary, _target_peer: int = 1) -> String:
	var error := PeerProtocol.validate(packet)
	if not error.is_empty():
		return error
	if not connected or socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return "TRANSPORT NOT CONNECTED"
	socket.send_text(PeerProtocol.encode(packet))
	return ""

func broadcast(packet: Dictionary) -> String:
	return send(packet, 1)

func close() -> void:
	if socket.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		socket.close()
	connected = false

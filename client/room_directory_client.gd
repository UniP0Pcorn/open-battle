# SPDX-License-Identifier: AGPL-3.0-only
extends Node
## Optional HTTP client for the dependency-free room advertisement directory.

const RoomDirectory = preload("res://rules/room_directory.gd")

signal rooms_received(rooms: Array)
signal request_completed(ok: bool, payload: Variant)

var request: HTTPRequest
var busy := false

func _ready() -> void:
	request = HTTPRequest.new()
	add_child(request)
	request.request_completed.connect(_on_request_completed)

func list_rooms(base_url: String) -> String:
	var url := _base_url(base_url)
	if url.is_empty():
		return "INVALID DIRECTORY URL"
	return _start(url + "/v1/rooms", HTTPClient.METHOD_GET, "")

func publish(base_url: String, advertisement: Dictionary) -> String:
	var url := _base_url(base_url)
	if url.is_empty():
		return "INVALID DIRECTORY URL"
	if advertisement.is_empty():
		return "INVALID ROOM ADVERTISEMENT"
	return _start(url + "/v1/rooms", HTTPClient.METHOD_POST, JSON.stringify(advertisement))

func remove(base_url: String, room_id: String, fingerprint: String) -> String:
	var url := _base_url(base_url)
	if url.is_empty() or room_id.strip_edges().is_empty() or fingerprint.strip_edges().is_empty():
		return "INVALID DIRECTORY REQUEST"
	return _start(url + "/v1/rooms/" + room_id.uri_encode() + "?fingerprint=" + fingerprint.uri_encode(), HTTPClient.METHOD_DELETE, "")

func _start(url: String, method: HTTPClient.Method, body: String) -> String:
	if busy:
		return "DIRECTORY BUSY"
	var headers := PackedStringArray(["Content-Type: application/json"])
	var error := request.request(url, headers, method, body)
	if error != OK:
		return "DIRECTORY REQUEST FAILED " + str(error)
	busy = true
	return ""

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	busy = false
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	var ok := result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
	if ok and parsed is Dictionary and parsed.get("rooms", null) is Array:
		var valid_rooms: Array = []
		var now := int(Time.get_unix_time_from_system())
		for room in parsed.rooms:
			if room is Dictionary and RoomDirectory.validate(room, now).is_empty():
				valid_rooms.append(room.duplicate(true))
		rooms_received.emit(valid_rooms)
	request_completed.emit(ok, parsed if parsed != null else {})

func _base_url(value: String) -> String:
	var url := value.strip_edges().trim_suffix("/")
	return url if url.begins_with("http://") or url.begins_with("https://") else ""

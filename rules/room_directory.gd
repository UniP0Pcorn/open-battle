# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Public room advertisement and invite codec.
## A future HTTPS directory, LAN beacon, or relay can carry the same record.

const VERSION := 1
const SCHEME := "open-battle://join/"

static func advertise(room_id: String, host: Dictionary, address: String, port: int, edition: int, mission_id: String, expires_at: int) -> Dictionary:
	return {"version": VERSION, "room_id": room_id.strip_edges(), "host": {"version": int(host.get("version", 0)), "account_id": str(host.get("account_id", "")), "display_name": str(host.get("display_name", "")), "fingerprint": str(host.get("fingerprint", ""))}, "address": address.strip_edges(), "port": port, "edition": edition, "mission_id": mission_id.strip_edges(), "expires_at": expires_at}

static func validate(record: Dictionary, now: int = 0) -> String:
	for field in ["version", "room_id", "host", "address", "port", "edition", "mission_id", "expires_at"]:
		if not record.has(field):
			return "MISSING " + field.to_upper()
	if int(record.version) != VERSION or str(record.room_id).strip_edges().is_empty() or str(record.mission_id).strip_edges().is_empty() or not (record.host is Dictionary):
		return "INVALID ROOM ADVERTISEMENT"
	for field in ["version", "account_id", "fingerprint"]:
		if str(record.host.get(field, "")).strip_edges().is_empty():
			return "MISSING HOST " + field.to_upper()
	if str(record.host.get("fingerprint", "")).length() != 64 or not _is_hex(str(record.host.fingerprint)):
		return "INVALID HOST FINGERPRINT"
	var address := str(record.address).strip_edges()
	if address.is_empty() or address.find(" ") >= 0 or address.find("/") >= 0 or address.find("\\") >= 0:
		return "INVALID ENDPOINT"
	if int(record.port) < 1024 or int(record.port) > 65535:
		return "INVALID PORT"
	if int(record.edition) <= 0 or int(record.expires_at) <= 0:
		return "INVALID ROOM ADVERTISEMENT"
	if now > 0 and int(record.expires_at) <= now:
		return "ROOM ADVERTISEMENT EXPIRED"
	return ""

static func encode(record: Dictionary, now: int = 0) -> String:
	if not validate(record, now).is_empty():
		return ""
	var payload := JSON.stringify(record).to_utf8_buffer()
	return SCHEME + Marshalls.raw_to_base64(payload).replace("+", "-").replace("/", "_").trim_suffix("=")

static func decode(invite: String, now: int = 0) -> Dictionary:
	var value := invite.strip_edges()
	if not value.begins_with(SCHEME):
		return {}
	var encoded := value.trim_prefix(SCHEME).replace("-", "+").replace("_", "/")
	while encoded.length() % 4 != 0:
		encoded += "="
	var bytes := Marshalls.base64_to_raw(encoded)
	if bytes.is_empty():
		return {}
	var parsed = JSON.parse_string(bytes.get_string_from_utf8())
	if not (parsed is Dictionary) or not validate(parsed, now).is_empty():
		return {}
	return parsed

static func _is_hex(value: String) -> bool:
	for character in value.to_lower():
		if character not in "0123456789abcdef":
			return false
	return true

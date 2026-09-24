# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Local account persistence.  Only the derived credential hash is stored.

const AccountIdentity = preload("res://rules/account_identity.gd")
const DEFAULT_PATH := "user://open_battle_identity.json"
const DEFAULT_TRUST_PATH := "user://open_battle_trusted_identities.json"

static func save_identity(identity: Dictionary, path: String = DEFAULT_PATH) -> String:
	var error := AccountIdentity.validate(identity)
	if not error.is_empty():
		return error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "OPEN IDENTITY FILE FAILED"
	file.store_string(JSON.stringify(identity))
	return ""

static func load_identity(path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary) or not AccountIdentity.validate(parsed).is_empty():
		return {}
	return parsed

static func remove_identity(path: String = DEFAULT_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK

static func save_trusted_identity(identity: Dictionary, path: String = DEFAULT_TRUST_PATH) -> String:
	var error := AccountIdentity.validate(identity)
	if not error.is_empty():
		return error
	var trusted := load_trusted_identities(path)
	var replaced := false
	for index in range(trusted.size()):
		if str(trusted[index].get("fingerprint", "")) == str(identity.fingerprint):
			trusted[index] = identity.duplicate(true)
			replaced = true
			break
	if not replaced:
		trusted.append(identity.duplicate(true))
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "OPEN TRUST FILE FAILED"
	file.store_string(JSON.stringify(trusted))
	return ""

static func load_trusted_identities(path: String = DEFAULT_TRUST_PATH) -> Array:
	if not FileAccess.file_exists(path):
		return []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return []
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Array):
		return []
	var result: Array = []
	for value in parsed:
		if value is Dictionary and AccountIdentity.validate(value).is_empty():
			result.append(value.duplicate(true))
	return result

static func remove_trusted_identities(path: String = DEFAULT_TRUST_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK

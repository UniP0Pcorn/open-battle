# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Offline account identity and challenge authentication for P2P sessions.
##
## A peer keeps the credential hash locally and only sends a challenge proof.
## A room may pin the public record/fingerprint before accepting commands.  A
## future relay can replace the trust store without changing peer envelopes.

const VERSION := 1

static func create(account_id: String, password: String, display_name: String = "") -> Dictionary:
	if account_id.strip_edges().is_empty() or password.is_empty():
		return {}
	var normalized := account_id.strip_edges().to_lower()
	var credential_hash := _sha256(normalized + "\n" + password)
	return {
		"version": VERSION,
		"account_id": normalized,
		"display_name": display_name.strip_edges(),
		"credential_hash": credential_hash,
		"fingerprint": _sha256(normalized + "\n" + credential_hash)
	}

static func public_record(identity: Dictionary) -> Dictionary:
	return {
		"version": int(identity.get("version", 0)),
		"account_id": str(identity.get("account_id", "")),
		"display_name": str(identity.get("display_name", "")),
		"fingerprint": str(identity.get("fingerprint", ""))
	}

static func challenge(identity: Dictionary, nonce: String) -> Dictionary:
	if not validate(identity).is_empty() or nonce.is_empty():
		return {}
	return {"account_id": str(identity.account_id), "nonce": nonce, "proof": _proof(identity, nonce)}

static func verify(identity: Dictionary, response: Dictionary, nonce: String) -> bool:
	if not validate(identity).is_empty() or nonce.is_empty():
		return false
	return str(response.get("account_id", "")) == str(identity.account_id) and str(response.get("nonce", "")) == nonce and str(response.get("proof", "")) == _proof(identity, nonce)

static func session_token(identity: Dictionary, nonce: String) -> String:
	if not validate(identity).is_empty() or nonce.is_empty():
		return ""
	return _sha256(_proof(identity, nonce) + "\n" + nonce)

static func validate(identity: Dictionary) -> String:
	for field in ["version", "account_id", "credential_hash", "fingerprint"]:
		if not identity.has(field):
			return "MISSING " + field.to_upper()
	if int(identity.version) != VERSION or str(identity.account_id).strip_edges().is_empty() or str(identity.credential_hash).is_empty():
		return "INVALID IDENTITY"
	if str(identity.fingerprint) != _sha256(str(identity.account_id) + "\n" + str(identity.credential_hash)):
		return "IDENTITY FINGERPRINT MISMATCH"
	return ""

static func _proof(identity: Dictionary, nonce: String) -> String:
	return _sha256(str(identity.account_id) + "\n" + str(identity.credential_hash) + "\n" + nonce)

static func _sha256(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()

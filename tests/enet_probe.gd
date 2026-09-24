# SPDX-License-Identifier: AGPL-3.0-only
extends SceneTree
const Identity = preload("res://rules/account_identity.gd")
const Setup = preload("res://rules/battle_setup.gd")
const Protocol = preload("res://rules/peer_protocol.gd")
var bridge: Node
var role := ""
var output := ""
var checks := 0
var snapshot_signals := 0

func _initialize() -> void:
	call_deferred("run")

func verify(condition: bool, label: String) -> bool:
	checks += 1
	if not condition:
		finish(false, label)
	return condition

func wait_for(predicate: Callable) -> bool:
	var deadline := Time.get_ticks_msec() + 10000
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await create_timer(0.01).timeout
	return false

func write_json(path: String, value: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value))

func finish(ok: bool, reason: String = "") -> void:
	var session: Dictionary = bridge.lobby.room.get("session", {}) if bridge != null else {}
	write_json(output.path_join(role + ".json"), {"ok": ok, "reason": reason, "checks": checks, "hash": Protocol.hash_snapshot(session), "commands": session.get("command_log", []).size()})
	if bridge != null:
		bridge.close_room()
	quit(0 if ok else 1)

func run() -> void:
	await process_frame
	var args := OS.get_cmdline_user_args()
	role = args[0]
	var port := int(args[1])
	output = args[2]
	bridge = root.get_node("NetworkBridge")
	bridge.battle_snapshot_received.connect(func(_state: Dictionary): snapshot_signals += 1)
	var host_id := Identity.create("enet-test-host", "synthetic-test-only")
	var client_id := Identity.create("enet-test-client", "synthetic-test-only")
	bridge.lobby.trusted_identities.clear()
	bridge.lobby.trusted_identities[str(client_id.fingerprint)] = client_id
	bridge.set_identity(host_id if role == "host" else client_id)
	if role == "host":
		if not verify(bridge.host_room("enet-loopback", port).is_empty(), "host starts"):
			return
		bridge.set_ready()
		write_json(output.path_join("listening.json"), {"ready": true})
		if not verify(await wait_for(func(): return bridge.lobby.room.players.size() == 2 and bool(bridge.lobby.room.players[1].get("ready", false))), "authenticated client joins and readies"):
			return
		if not verify(bridge.start(Setup.default_models()).is_empty(), "host starts shared session"):
			return
		if not verify(bridge.submit_command("END_TURN", {"next_team": 1}).is_empty(), "host hands turn to client"):
			return
		if not verify(await wait_for(func(): return bridge.lobby.room.session.command_log.size() >= 3), "host receives remote phase and advance intent"):
			return
		var entry: Dictionary = bridge.lobby.room.session.command_log[-1]
		if not verify(str(entry.kind) == "ADVANCE" and int(entry.payload.roll) >= 1 and int(entry.payload.roll) <= 6 and not bool(entry.payload.get("intent", false)), "host records resolved advance"):
			return
		if not verify(snapshot_signals >= 3, "host tabletop receives remote command snapshots"):
			return
		if not verify(await wait_for(func(): return not bool(bridge.lobby.room.players[1].connected)), "host observes transport disconnect"):
			return
		write_json(output.path_join("disconnected.json"), {"ready": true})
		if not verify(await wait_for(func(): return bool(bridge.lobby.room.players[1].connected)), "host accepts authenticated reconnect"):
			return
		if not verify(await wait_for(func(): return FileAccess.file_exists(output.path_join("client.json"))), "client acknowledges authoritative snapshot"):
			return
		finish(true)
	else:
		if not verify(bridge.connect_to_room("enet-loopback", "127.0.0.1", port).is_empty(), "client connects"):
			return
		if not verify(await wait_for(func(): return not bridge.lobby.reconnect_token.is_empty()), "challenge and join complete"):
			return
		if not verify(bridge.set_ready().is_empty(), "client readies"):
			return
		if not verify(await wait_for(func(): return int(bridge.lobby.room.session.get("active_team", -1)) == 1), "client receives host turn snapshot"):
			return
		if not verify(bridge.submit_command("PHASE_ADVANCE", {"from": "COMMAND", "to": "MOVEMENT"}).is_empty(), "client requests movement phase"):
			return
		if not verify(await wait_for(func(): return str(bridge.lobby.room.session.get("phase", "")) == "MOVEMENT"), "client receives movement phase"):
			return
		var unit_id := ""
		for model in bridge.lobby.room.session.models:
			if int(model.team) == 1:
				unit_id = str(model.unit_id)
				break
		if not verify(bridge.submit_command("ADVANCE", {"unit_id": unit_id, "intent": true, "roll": 999}).is_empty(), "client sends advance intent"):
			return
		if not verify(await wait_for(func(): return bridge.lobby.room.session.command_log.size() >= 3), "client receives resolved advance snapshot"):
			return
		var prior_hash := Protocol.hash_snapshot(bridge.lobby.room.session)
		bridge.lobby.transport.close()
		if not verify(await wait_for(func(): return FileAccess.file_exists(output.path_join("disconnected.json"))), "host confirms disconnect"):
			return
		var before_reconnect := snapshot_signals
		if not verify(bridge.reconnect().is_empty(), "reconnect recreates ENet connection"):
			return
		if not verify(await wait_for(func(): return snapshot_signals > before_reconnect), "reconnected client receives authoritative snapshot"):
			return
		if not verify(Protocol.hash_snapshot(bridge.lobby.room.session) == prior_hash, "reconnect restores identical battle state"):
			return
		finish(true)

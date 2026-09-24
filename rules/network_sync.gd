# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Deterministic host/client synchronization adapter.
##
## This module is deliberately independent of ENet.  The host validates every
## command against the current snapshot before Room/BattleSession applies it;
## clients accept only snapshots whose content hash matches their envelope.

const PeerProtocol = preload("res://rules/peer_protocol.gd")
const Room = preload("res://rules/room.gd")
const Combat = preload("res://rules/combat.gd")
const Damage = preload("res://rules/damage.gd")
const Melee = preload("res://rules/melee.gd")
const UnitAbilities = preload("res://rules/unit_abilities.gd")
const Visibility = preload("res://rules/visibility.gd")
const WeaponRules = preload("res://rules/weapon_rules.gd")

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
	var command: Dictionary = packet.command.duplicate(true)
	if str(command.get("kind", "")) in ["SHOOT", "FIGHT"] and bool(command.get("payload", {}).get("intent", false)):
		var materialized := _materialize_attack(room.session, command, packet)
		if not bool(materialized.get("ok", false)):
			return {"ok": false, "reason": str(materialized.get("reason", "ATTACK REJECTED")), "room": room}
		command.payload = materialized.payload
	var expected_sequence := int(room.get("session", {}).get("command_log", []).size())
	if int(packet.sequence) != expected_sequence:
		return {"ok": false, "reason": "COMMAND SEQUENCE GAP", "room": room}
	var submitted := Room.submit(room, expected_peer_id, str(command.get("kind", "")), command.get("payload", {}))
	if not bool(submitted.get("ok", false)):
		return submitted
	var next_room: Dictionary = submitted.room
	var snapshot := PeerProtocol.snapshot(str(next_room.id), expected_peer_id, str(packet.session_id), int(next_room.session.get("command_log", []).size()) - 1, next_room.session, str(packet.get("reconnect_token", "")))
	return {"ok": true, "reason": "", "room": next_room, "entry": submitted.entry, "snapshot": snapshot}

static func _materialize_attack(state: Dictionary, command: Dictionary, packet: Dictionary) -> Dictionary:
	var payload: Dictionary = command.get("payload", {}).duplicate(true)
	var models: Array = state.get("models", [])
	var attacker_index := _model_index(models, payload, "attacker_id", "attacker")
	var target_index := _model_index(models, payload, "target_id", "target")
	if attacker_index < 0 or target_index < 0 or attacker_index >= models.size() or target_index >= models.size() or attacker_index == target_index:
		return {"ok": false, "reason": "INVALID DAMAGE EVENT"}
	var attacker: Dictionary = models[attacker_index]
	var target: Dictionary = models[target_index]
	var weapon_name := str(payload.get("weapon", ""))
	var weapon: Dictionary = {}
	for candidate in attacker.get("weapons", []):
		if candidate is Dictionary and str(candidate.get("name", "")) == weapon_name:
			weapon = candidate.duplicate(true)
			break
	if weapon.is_empty():
		return {"ok": false, "reason": "UNKNOWN WEAPON"}
	var rng := RandomNumberGenerator.new()
	rng.seed = (str(packet.get("session_id", "")) + ":" + str(packet.get("sequence", 0))).hash()
	var result: Dictionary
	var resolved_weapon: Dictionary = weapon.duplicate(true)
	if str(command.get("kind", "")) == "FIGHT":
		var melee_context := WeaponRules.context(weapon, INF, 0, 1, target.get("keywords", []), false)
		resolved_weapon = melee_context.weapon
		result = Melee.resolve_attack(resolved_weapon, target, rng, 0, target.get("keywords", []), UnitAbilities.event_modifiers(attacker.get("ability_ids", []), "before_attack", {"phase": "FIGHT", "kind": "FIGHT"}))
	else:
		var distance := _position(attacker).distance_to(_position(target))
		var cover := Visibility.cover_bonus(_position(attacker), _position(target), state.get("terrain", [])) + int(target.get("temporary_cover_bonus", 0))
		var target_count := 0
		for model in models:
			if str(model.get("unit_id", "")) == str(target.get("unit_id", "")):
				target_count += 1
		var line_of_sight := not Visibility.blocked(_position(attacker), _position(target), state.get("terrain", []))
		var context := WeaponRules.context(weapon, distance, cover, target_count, target.get("keywords", []), float(attacker.get("spent", 0.0)) <= 0.0001, line_of_sight)
		resolved_weapon = context.weapon
		result = Combat.resolve_ranged_attack(resolved_weapon, target, rng, 0, UnitAbilities.event_modifiers(attacker.get("ability_ids", []), "before_attack", {"phase": "SHOOTING", "kind": "SHOOT"}))
	payload.intent = false
	payload.attacker = attacker_index
	payload.target = target_index
	payload.attacker_id = str(attacker.get("model_id", ""))
	payload.target_id = str(target.get("model_id", ""))
	payload.hits = int(result.get("hits", 0))
	payload.damage = int(result.get("damage", 0))
	payload.one_shot = WeaponRules.ids_from_weapon(resolved_weapon).has("one_shot")
	var preview: Array = [target.duplicate(true)]
	var damage_preview := Damage.allocate_to_unit(preview, int(result.get("damage", 0)), 0, rng)
	if not damage_preview.feel_no_pain_rolls.is_empty():
		payload.feel_no_pain_rolls = damage_preview.feel_no_pain_rolls
	var hazardous_damage := int(result.get("hazardous_failures", 0)) * int(resolved_weapon.get("hazardous_damage", 0))
	payload.hazardous_damage = maxi(0, hazardous_damage)
	if hazardous_damage > 0:
		var hazardous_preview: Array = [attacker.duplicate(true)]
		var hazardous_damage_preview := Damage.allocate_to_unit(hazardous_preview, hazardous_damage, 0, rng)
		if not hazardous_damage_preview.feel_no_pain_rolls.is_empty():
			payload.hazardous_feel_no_pain_rolls = hazardous_damage_preview.feel_no_pain_rolls
	return {"ok": true, "reason": "", "payload": payload}

static func _model_index(models: Array, payload: Dictionary, id_key: String, index_key: String) -> int:
	var model_id := str(payload.get(id_key, ""))
	if not model_id.is_empty():
		for index in range(models.size()):
			if str(models[index].get("model_id", "")) == model_id:
				return index
	return int(payload.get(index_key, -1))

static func _position(model: Dictionary) -> Vector2:
	var value: Variant = model.get("position", Vector2.ZERO)
	if value is Vector2:
		return value
	if value is Array and value.size() == 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO

static func accept_snapshot(local_state: Dictionary, packet: Dictionary) -> Dictionary:
	var packet_error := PeerProtocol.validate(packet)
	if not packet_error.is_empty():
		return {"ok": false, "reason": packet_error, "state": local_state}
	if str(packet.kind) != PeerProtocol.SNAPSHOT:
		return {"ok": false, "reason": "NOT A SNAPSHOT", "state": local_state}
	return {"ok": true, "reason": "", "state": packet.state.duplicate(true)}

static func reconnect_snapshot(room: Dictionary, player_id: String, token: String, last_sequence: int = -1) -> Dictionary:
	return Room.reconnect(room, player_id, token, last_sequence)

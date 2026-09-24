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
const FactionRules = preload("res://rules/faction_rules.gd")
const Visibility = preload("res://rules/visibility.gd")
const WeaponRules = preload("res://rules/weapon_rules.gd")
const Attachments = preload("res://rules/attachments.gd")
const Replay = preload("res://rules/replay.gd")
const Stratagems = preload("res://rules/stratagems.gd")

static func host_command(room: Dictionary, packet: Dictionary, expected_peer_id: String, host_rng: RandomNumberGenerator = null) -> Dictionary:
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
	var actor_team := -1
	for player in room.get("players", []):
		if str(player.get("id", "")) == expected_peer_id:
			actor_team = int(player.get("team", -1))
	if actor_team not in [0, 1] or int(command.get("team", -1)) != actor_team:
		return {"ok": false, "reason": "PLAYER TEAM MISMATCH", "room": room}
	if str(command.get("kind", "")) in ["SHOOT", "FIGHT", "BATTLE_SHOCK", "ADVANCE", "CHARGE"] and not bool(command.get("payload", {}).get("intent", false)):
		return {"ok": false, "reason": "HOST RESOLUTION REQUIRED", "room": room}
	if str(command.kind) == "HAZARDOUS":
		return {"ok": false, "reason": "HAZARDOUS REQUIRES HOST ATTACK", "room": room}
	var expected_sequence := int(room.get("session", {}).get("command_log", []).size())
	if int(packet.sequence) != expected_sequence:
		return {"ok": false, "reason": "COMMAND SEQUENCE GAP", "room": room}
	# The optional RNG is a host-local test seam, never read from a packet or snapshot.
	# Record outcomes for replay; public session/sequence values must not seed dice.
	if host_rng == null:
		host_rng = RandomNumberGenerator.new()
		var entropy := Crypto.new().generate_random_bytes(8)
		if entropy.size() != 8:
			return {"ok": false, "reason": "HOST RANDOM SOURCE UNAVAILABLE", "room": room}
		host_rng.seed = entropy.decode_s64(0)
	if str(command.kind) == "ADVANCE":
		var advance_roll := host_rng.randi_range(1, 6)
		command.payload = {"unit_id": str(command.payload.get("unit_id", "")), "roll": advance_roll, "rolls": [advance_roll]}
	if str(command.kind) == "CHARGE":
		var charged := _materialize_charge(room.session, command, host_rng)
		if not charged.ok:
			return {"ok": false, "reason": charged.reason, "room": room}
		command.payload = charged.payload
	if str(command.get("kind", "")) == "STRATAGEM":
		var definition := Replay._stratagem_for(room.session, actor_team, str(command.payload.get("id", "")))
		if str(definition.get("effect", "")) == "REACTION_SHOOT":
			var definition_error := Stratagems.validate(definition)
			if not definition_error.is_empty() or str(definition.get("timing", "")) != "AFTER_ENEMY_MOVE":
				return {"ok": false, "reason": "INVALID REACTION SHOOTING", "room": room}
			var intent: Dictionary = command.payload.duplicate(true)
			intent.erase("attack")
			var reaction_attack := _materialize_attack(room.session, {"team": actor_team, "kind": "SHOOT", "payload": intent}, host_rng, definition)
			if not reaction_attack.ok:
				return {"ok": false, "reason": reaction_attack.reason, "room": room}
			command.payload.attack = reaction_attack.payload
	if str(command.get("kind", "")) in ["SHOOT", "FIGHT"] and bool(command.get("payload", {}).get("intent", false)):
		var materialized := _materialize_attack(room.session, command, host_rng)
		if not bool(materialized.get("ok", false)):
			return {"ok": false, "reason": str(materialized.get("reason", "ATTACK REJECTED")), "room": room}
		command.payload = materialized.payload
	if str(command.get("kind", "")) == "BATTLE_SHOCK" and bool(command.get("payload", {}).get("intent", false)):
		var shock_materialized := _materialize_battle_shock(room.session, command, host_rng)
		if not bool(shock_materialized.get("ok", false)):
			return {"ok": false, "reason": str(shock_materialized.get("reason", "BATTLE SHOCK REJECTED")), "room": room}
		command.payload = shock_materialized.payload
	var submitted := Room.submit(room, expected_peer_id, str(command.get("kind", "")), command.get("payload", {}))
	if not bool(submitted.get("ok", false)):
		return submitted
	var next_room: Dictionary = submitted.room
	var snapshot := PeerProtocol.snapshot(str(next_room.id), expected_peer_id, str(packet.session_id), int(next_room.session.get("command_log", []).size()) - 1, next_room.session, str(packet.get("reconnect_token", "")))
	return {"ok": true, "reason": "", "room": next_room, "entry": submitted.entry, "snapshot": snapshot}

static func _materialize_charge(state: Dictionary, command: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var models: Array = state.models
	var charger := _model_index(models, command.payload, "model_id", "model")
	var target := _model_index(models, command.payload, "target_id", "target")
	if charger < 0 or target < 0 or charger >= models.size() or target >= models.size() or charger == target:
		return {"ok": false, "reason": "INVALID CHARGE"}
	var origin := _position(models[charger])
	var destination := _position(models[target]) - (_position(models[target]) - origin).normalized() * (float(models[charger].get("radius", 0)) + float(models[target].get("radius", 0)) + 1.0)
	var payload := {"model": charger, "model_id": str(models[charger].model_id), "target": target, "target_id": str(models[target].model_id), "from": [origin.x, origin.y], "to": [destination.x, destination.y], "roll": [6, 6]}
	var reason := Replay._validate_references(models, command, "CHARGE", payload, state.get("terrain", []))
	if not reason.is_empty():
		return {"ok": false, "reason": reason}
	payload.roll = [rng.randi_range(1, 6), rng.randi_range(1, 6)]
	payload.failed = origin.distance_to(destination) > float(payload.roll[0] + payload.roll[1]) + 0.00001
	return {"ok": true, "payload": payload}

static func _materialize_attack(state: Dictionary, command: Dictionary, rng: RandomNumberGenerator, reaction: Dictionary = {}) -> Dictionary:
	var payload: Dictionary = command.get("payload", {}).duplicate(true)
	for derived_field in ["attacker", "target", "hits", "damage", "one_shot", "feel_no_pain_rolls", "hazardous_damage", "hazardous_feel_no_pain_rolls"]:
		payload.erase(derived_field)
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
	if not reaction.is_empty():
		weapon.hit_on = int(reaction.hit_on)
	var result: Dictionary
	var resolved_weapon: Dictionary = weapon.duplicate(true)
	var ability_modifiers := FactionRules.combat_modifiers(models, attacker, "before_attack", {"phase": str(state.phase), "kind": str(command.kind)})
	var hit_rerolls := 0
	for effect in state.get("stratagem_effects", []):
		if effect is Dictionary and str(effect.get("effect", "")) == "REROLL_HIT" and int(effect.get("team", -1)) == int(command.get("team", -1)) and not bool(effect.get("consumed", false)):
			hit_rerolls = 1
			break
	if str(command.get("kind", "")) == "FIGHT":
		hit_rerolls += int(ability_modifiers.get("hit_rerolls", 0))
		var melee_context := WeaponRules.context(weapon, INF, 0, 1, target.get("keywords", []), false)
		resolved_weapon = melee_context.weapon
		if bool(attacker.get("charged", false)) and WeaponRules.ids_from_weapon(resolved_weapon).has("lance"):
			resolved_weapon.wound_bonus = 1
		result = Melee.resolve_attack(resolved_weapon, target, rng, hit_rerolls, target.get("keywords", []), FactionRules.combat_modifiers(models, attacker, "before_attack", {"phase": "FIGHT", "kind": "FIGHT"}))
	else:
		hit_rerolls += int(ability_modifiers.get("hit_rerolls", 0))
		var distance := _position(attacker).distance_to(_position(target))
		var target_abilities := FactionRules.combat_modifiers(models, target, "before_defend")
		var cover := Visibility.cover_bonus(_position(attacker), _position(target), state.get("terrain", [])) + int(target_abilities.get("cover_bonus", 0)) + int(target.get("temporary_cover_bonus", 0))
		var target_count := 0
		for model in models:
			if Attachments.group_id(model) == Attachments.group_id(target):
				target_count += 1
		var line_of_sight := not Visibility.blocked(_position(attacker), _position(target), state.get("terrain", []))
		var context := WeaponRules.context(weapon, distance, cover, target_count, target.get("keywords", []), float(attacker.get("spent", 0.0)) <= 0.0001, line_of_sight)
		resolved_weapon = context.weapon
		target = target.duplicate(true)
		target.cover_save_bonus = int(context.cover_bonus)
		result = Combat.resolve_ranged_attack(resolved_weapon, target, rng, hit_rerolls, FactionRules.combat_modifiers(models, attacker, "before_attack", {"phase": "SHOOTING", "kind": "SHOOT"}))
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

static func _materialize_battle_shock(state: Dictionary, command: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var payload: Dictionary = command.get("payload", {}).duplicate(true)
	var unit_id := str(payload.get("unit_id", ""))
	var unit_models: Array = []
	for model in state.get("models", []):
		if Attachments.group_id(model) == unit_id and int(model.get("team", -1)) == int(command.get("team", -1)):
			unit_models.append(model)
	if unit_models.is_empty():
		return {"ok": false, "reason": "UNKNOWN UNIT"}
	var rolls: Array = [rng.randi_range(1, 6), rng.randi_range(1, 6)]
	var total := int(rolls[0]) + int(rolls[1])
	payload.erase("intent")
	payload.rolls = rolls
	payload.total = total
	payload.passed = total <= int(unit_models[0].get("leadership", 7))
	return {"ok": true, "reason": "", "payload": payload}

static func _model_index(models: Array, payload: Dictionary, id_key: String, index_key: String) -> int:
	var model_id := str(payload.get(id_key, ""))
	if not model_id.is_empty():
		for index in range(models.size()):
			if str(models[index].get("model_id", "")) == model_id:
				return index
		return -1
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
	var restored: Dictionary = packet.state.duplicate(true)
	for model in restored.get("models", []):
		if model.get("position") is Array:
			model.position = _position(model)
	return {"ok": true, "reason": "", "state": restored}

static func reconnect_snapshot(room: Dictionary, player_id: String, token: String, last_sequence: int = -1) -> Dictionary:
	return Room.reconnect(room, player_id, token, last_sequence)

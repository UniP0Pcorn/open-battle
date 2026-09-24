# SPDX-License-Identifier: AGPL-3.0-only
extends SceneTree
const Rules = preload("res://rules/movement.gd")
const Combat = preload("res://rules/combat.gd")
const ArmyValidation = preload("res://rules/army_validation.gd")
const CommandLog = preload("res://rules/command_log.gd")
const CommandSchema = preload("res://rules/command_schema.gd")
const BattleSession = preload("res://rules/battle_session.gd")
const Room = preload("res://rules/room.gd")
const PeerProtocol = preload("res://rules/peer_protocol.gd")
const AccountIdentity = preload("res://rules/account_identity.gd")
const AccountStore = preload("res://rules/account_store.gd")
const NatMapping = preload("res://client/nat_mapping.gd")
const P2PTransport = preload("res://client/p2p_transport.gd")
const P2PLobby = preload("res://client/p2p_lobby.gd")
const RoomDirectory = preload("res://rules/room_directory.gd")
const NetworkSync = preload("res://rules/network_sync.gd")
const LobbyScreen = preload("res://client/lobby/lobby_screen.gd")
const Deployment = preload("res://rules/deployment.gd")
const Engagement = preload("res://rules/engagement.gd")
const UnitValidation = preload("res://rules/unit_validation.gd")
const Dice = preload("res://rules/dice.gd")
const TurnState = preload("res://rules/turn_state.gd")
const DatasheetValidation = preload("res://rules/datasheet_validation.gd")
const Charge = preload("res://rules/charge.gd")
const Melee = preload("res://rules/melee.gd")
const Terrain = preload("res://rules/terrain.gd")
const Visibility = preload("res://rules/visibility.gd")
const Damage = preload("res://rules/damage.gd")
const MissionRules = preload("res://rules/mission.gd")
const CommandPoints = preload("res://rules/command_points.gd")
const BattleShock = preload("res://rules/battle_shock.gd")
const ArmyBuilder = preload("res://rules/army_builder.gd")
const UnitMovement = preload("res://rules/unit_movement.gd")
const Stratagems = preload("res://rules/stratagems.gd")
const SourceManifest = preload("res://rules/source_manifest.gd")
const ProfileCatalog = preload("res://rules/profile_catalog.gd")
const RosterEditor = preload("res://rules/roster_editor.gd")
const UnitAbilities = preload("res://rules/unit_abilities.gd")
const FactionRules = preload("res://rules/faction_rules.gd")
const WeaponRules = preload("res://rules/weapon_rules.gd")
const Replay = preload("res://rules/replay.gd")
const UnitKeywords = preload("res://rules/unit_keywords.gd")
const RulesetCatalog = preload("res://rules/ruleset_catalog.gd")
const MissionValidation = preload("res://rules/mission_validation.gd")
const ModelState = preload("res://rules/model_state.gd")
const AIPlayer = preload("res://rules/ai_player.gd")
const Reserves = preload("res://rules/reserves.gd")
const Attachments = preload("res://rules/attachments.gd")
const BattleSetup = preload("res://rules/battle_setup.gd")
class FakeNAT extends RefCounted:
	var discover_error := 0
	var mapping_error := 0
	var renewal_error := 0
	var cleanup_error := 0
	var valid := true
	var gate: Semaphore
	var added: Array = []
	var deleted: Array = []
	func discover(_timeout: int, _ttl: int, _filter: String) -> int:
		if gate != null:
			gate.wait()
		return discover_error
	func get_gateway() -> Object:
		return self
	func is_valid_gateway() -> bool:
		return valid
	func add_port_mapping(port: int, internal: int, _description: String, protocol: String, lease: int) -> int:
		added.append([port, internal, protocol, lease])
		return renewal_error if added.size() > 1 else mapping_error
	func query_external_address() -> String:
		return "203.0.113.1"
	func delete_port_mapping(port: int, protocol: String) -> int:
		deleted.append([port, protocol])
		return cleanup_error

func await_nat_state(mapping: Node, expected: String) -> bool:
	for attempt in range(200):
		if str(mapping.status.state) == expected:
			return true
		await create_timer(0.01).timeout
	return false

var failures := 0
var checks := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
	else:
		print("PASS: " + description)

func seeded_rng(value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = value
	return rng

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var radius := Rules.radius_inches(40.0)
	check(is_equal_approx(radius * 2.0, 1.5748031496), "40 mm conversion")
	check(Rules.BOARD_SIZE == Vector2(60, 44), "table dimensions")
	check(Rules.inside_board(Vector2(radius, radius), radius), "tangent to edge is legal")
	check(not Rules.inside_board(Vector2(radius - 0.01, 5), radius), "whole base must fit")
	check(not Rules.inside_board(Vector2(60 - radius + 0.01, 5), radius), "right edge")
	check(not Rules.inside_board(Vector2(5, 44 - radius + 0.01), radius), "bottom edge")
	check(Rules.movement_reason(Vector2(5, 5), Vector2(11, 5), 0, 6, radius, [], -1).is_empty(), "exactly six inches")
	check(Rules.movement_reason(Vector2(5, 5), Vector2(11.001, 5), 0, 6, radius, [], -1) == "MOVE LIMIT EXCEEDED", "over budget")
	check(Rules.movement_reason(Vector2(5, 5), Vector2(8, 9), 1, 6, radius, [], -1).is_empty(), "3-4-5 diagonal plus spent budget")
	check(Rules.movement_reason(Vector2(5, 5), Vector2(8, 9), 2, 6, radius, [], -1) == "MOVE LIMIT EXCEEDED", "cumulative move enforcement")
	var occupied: Array = [{"position": Vector2(5, 5), "radius": radius}]
	check(Rules.placement_reason(Vector2(5, 5), radius, occupied) == "BASE OVERLAP", "placement overlap rejected")
	check(Rules.placement_reason(Vector2(5 + radius * 2, 5), radius, occupied).is_empty(), "tangent bases allowed")
	check(Rules.placement_reason(Vector2(5, 5), radius, occupied, 0).is_empty(), "moving base excluded from collision")
	var blocked_path: Array = [{"position": Vector2(8, 5), "radius": radius}]
	check(not Rules.path_reason(Vector2(5, 5), Vector2(11, 5), radius, blocked_path).is_empty(), "path crossing is rejected")
	check(Rules.movement_reason(Vector2(5, 5), Vector2(11, 5), 0, 10, radius, blocked_path, -1) == "PATH BLOCKED", "movement reports blocked path")
	check(Rules.path_reason(Vector2(5, 5), Vector2(5, 5), radius, blocked_path).is_empty(), "zero-length path is clear")
	check(Combat.wound_target(5, 5) == 4, "equal strength wounds on four")
	check(Combat.wound_target(10, 5) == 2, "double strength wounds on two")
	check(Combat.save_target(4, -1) == 5, "armor penetration modifies saves")
	check(Combat.save_target(4, -3, 4) == 4, "best invulnerable save is selected")
	check(Combat.save_target(3, -4) == 7, "high signed AP can make armor save impossible")
	check(Combat.save_target(2, -1, 5) == 3, "armor remains preferable when better than invulnerable save")
	var ap_weapon := {"attacks": 80, "hit_on": 2, "strength": 8, "damage": 1, "ap": -2}
	var ap_target := {"toughness": 4, "save_on": 4}
	var ap_attack := Combat.resolve_ranged_attack(ap_weapon, ap_target, seeded_rng(87))
	var ap_zero_weapon: Dictionary = ap_weapon.duplicate(true)
	ap_zero_weapon.ap = 0
	var no_ap_attack := Combat.resolve_ranged_attack(ap_zero_weapon, ap_target, seeded_rng(87))
	check(ap_attack.save_on == 6 and ap_attack.damage > no_ap_attack.damage, "negative AP worsens saves and increases resolved damage")
	ap_target.cover_save_bonus = 1
	check(Combat.resolve_ranged_attack(ap_weapon, ap_target, seeded_rng(87)).save_on == 5, "cover offsets one point of negative AP")
	ap_target.invulnerable_save = 4
	check(Combat.resolve_ranged_attack(ap_weapon, ap_target, seeded_rng(87)).save_on == 4, "AP and cover do not alter invulnerable save")
	check(Combat.save_target(7, 0) == 7 and not Combat.save_passes(6, 7), "impossible save fails")
	var attacker := {"team": 0}
	var enemy := {"team": 1, "toughness": 5}
	var weapon := {"range_inches": 24.0, "attacks": 1, "hit_on": 4, "strength": 5, "damage": 1}
	check(Combat.target_reason(attacker, enemy, 12.0, weapon, 0).is_empty(), "enemy in range is a legal target")
	var lone_operator := {"team": 1, "toughness": 5, "ability_ids": ["lone_operator"]}
	check(Combat.target_reason(attacker, lone_operator, 13.0, weapon, 0) == "LONE OPERATOR" and Combat.target_reason(attacker, lone_operator, 12.0, weapon, 0).is_empty(), "lone operator limits distant shooting")
	check(Combat.target_reason(attacker, enemy, 25.0, weapon, 0) == "OUT OF RANGE", "out of range target is rejected")
	check(Combat.target_reason(attacker, {"team": 0}, 12.0, weapon, 0) == "FRIENDLY TARGET", "friendly target is rejected")
	var advanced_attacker := {"team": 0, "advanced": true}
	check(Combat.target_reason(advanced_attacker, enemy, 12.0, weapon, 0) == "ADVANCED WITHOUT ASSAULT" and Combat.target_reason(advanced_attacker, enemy, 12.0, {"range_inches": 24.0, "abilities": ["突击"]}, 0).is_empty(), "advance restricts shooting to assault weapons")
	var engaged_attacker := {"team": 0}
	var pistol_weapon := {"range_inches": 12.0, "abilities": ["手枪"]}
	check(Combat.target_reason(engaged_attacker, enemy, 6.0, weapon, 0, true, true) == "ENGAGED NON-PISTOL" and Combat.target_reason(engaged_attacker, enemy, 6.0, pistol_weapon, 0, true, true).is_empty() and Combat.target_reason(engaged_attacker, enemy, 6.0, pistol_weapon, 0, true, false) == "PISTOL TARGET OUTSIDE ENGAGEMENT", "pistol target restrictions use engagement state")
	var combat_rng := RandomNumberGenerator.new()
	combat_rng.seed = 1
	var combat_result := Combat.resolve_ranged_attack({"attacks": 2, "hit_on": 3, "strength": 5, "damage": 2}, {"toughness": 5}, combat_rng)
	check(combat_result.has("hits") and combat_result.has("damage"), "combat result has hit and damage totals")
	var roster := {"points_limit": 1000, "units": [{"unit_id": "fixture", "count": 10, "points_each": 100}]}
	check(ArmyValidation.validate_roster(roster).is_empty(), "valid roster passes")
	check(ArmyValidation.total_points(roster) == 1000, "roster points total")
	roster.points_limit = 900
	check(not ArmyValidation.validate_roster(roster).is_empty(), "over-limit roster fails")
	var log: Array = []
	log = CommandLog.append(log, 0, "MOVE", {"unit_id": "u", "delta": [3.0, 0.0]})
	log = CommandLog.append(log, 0, "SHOOT", {"attacker": 0, "target": 2, "damage": 1})
	check(CommandLog.validate(log).is_empty(), "command log entries validate")
	check(CommandLog.decode(CommandLog.encode(log)).size() == 2, "command log round trips")
	var broken_log := log.duplicate(true)
	broken_log[1].sequence = 4
	check(CommandLog.validate(broken_log) == "SEQUENCE GAP", "command log detects sequence gaps")
	check(CommandSchema.validate_for_state(log[0], {"active_team": 0, "phase": "MOVEMENT"}).is_empty(), "command schema accepts active movement")
	check(CommandSchema.validate_for_state(log[1], {"active_team": 0, "phase": "MOVEMENT"}) == "INVALID PHASE", "command schema rejects wrong phase")
	var phase_entry := {"sequence": 0, "team": 0, "kind": "PHASE_ADVANCE", "payload": {"from": "MOVEMENT", "to": "SHOOTING"}}
	check(CommandSchema.validate_for_state(phase_entry, {"active_team": 0, "phase": "MOVEMENT"}).is_empty(), "command schema accepts phase advance")
	var bad_phase_entry := phase_entry.duplicate(true)
	bad_phase_entry.payload.to = "FIGHT"
	check(CommandSchema.validate_entry(bad_phase_entry) == "INVALID PHASE TRANSITION", "command schema rejects skipped phase")
	var malformed_command: Dictionary = log[0].duplicate(true)
	malformed_command.payload = {"unit_id": "u"}
	check(CommandSchema.validate_entry(malformed_command) == "INVALID MOVE", "command schema rejects incomplete payload")
	var incomplete_damage := {"sequence": 0, "team": 0, "kind": "SHOOT", "payload": {"target": 1, "damage": 1}}
	check(CommandSchema.validate_entry(incomplete_damage) == "INVALID DAMAGE EVENT", "command schema requires damage attacker")
	var advance_entry := {"sequence": 0, "team": 0, "kind": "ADVANCE", "payload": {"unit_id": "u", "roll": 4}}
	check(CommandSchema.validate_for_state(advance_entry, {"active_team": 0, "phase": "MOVEMENT"}).is_empty(), "command schema accepts advance")
	var fall_back_entry := {"sequence": 0, "team": 0, "kind": "FALL_BACK", "payload": {"unit_id": "u", "delta": [-2.0, 0.0]}}
	check(CommandSchema.validate_for_state(fall_back_entry, {"active_team": 0, "phase": "MOVEMENT"}).is_empty(), "command schema accepts fall back")
	var reserve_entry := {"sequence": 0, "team": 0, "kind": "DEPLOY_RESERVE", "payload": {"unit_id": "u", "positions": [[10.0, 20.0]]}}
	check(CommandSchema.validate_for_state(reserve_entry, {"active_team": 0, "phase": "MOVEMENT"}).is_empty(), "command schema accepts reserve arrival")
	var scout_entry := {"sequence": 0, "team": 0, "kind": "SCOUT", "payload": {"unit_id": "u", "delta": [3.0, 0.0]}}
	check(CommandSchema.validate_for_state(scout_entry, {"active_team": 0, "phase": "COMMAND"}).is_empty(), "command schema accepts scout")
	var attach_entry := {"sequence": 0, "team": 0, "kind": "ATTACH", "payload": {"leader_unit_id": "leader", "bodyguard_unit_id": "bodyguard"}}
	check(CommandSchema.validate_for_state(attach_entry, {"active_team": 0, "phase": "COMMAND"}).is_empty(), "command schema accepts attachment")
	var detach_entry := {"sequence": 0, "team": 0, "kind": "DETACH", "payload": {"leader_unit_id": "leader"}}
	check(CommandSchema.validate_for_state(detach_entry, {"active_team": 0, "phase": "COMMAND"}).is_empty(), "command schema accepts detachment")
	var battle_shock_intent := {"sequence": 0, "team": 0, "kind": "BATTLE_SHOCK", "payload": {"unit_id": "u", "intent": true}}
	check(CommandSchema.validate_entry(battle_shock_intent).is_empty(), "command schema accepts host-materialized battle shock intent")
	var embark_entry := {"sequence": 0, "team": 0, "kind": "EMBARK", "payload": {"unit_id": "u", "transport_id": "transport_m001"}}
	check(CommandSchema.validate_for_state(embark_entry, {"active_team": 0, "phase": "MOVEMENT"}).is_empty(), "command schema accepts embark")
	var disembark_entry := {"sequence": 0, "team": 0, "kind": "DISEMBARK", "payload": {"unit_id": "u", "positions": [[10.0, 20.0]]}}
	check(CommandSchema.validate_for_state(disembark_entry, {"active_team": 0, "phase": "MOVEMENT"}).is_empty(), "command schema accepts disembark")
	var bad_reserve_entry := reserve_entry.duplicate(true)
	bad_reserve_entry.payload.positions = [[10.0]]
	check(CommandSchema.validate_entry(bad_reserve_entry) == "INVALID RESERVE ARRIVAL", "command schema rejects malformed reserve arrival")
	var bad_advance := advance_entry.duplicate(true)
	bad_advance.payload.roll = -1
	check(CommandSchema.validate_entry(bad_advance) == "INVALID ADVANCE", "command schema rejects invalid advance roll")
	bad_advance.payload.roll = 7
	check(CommandSchema.validate_entry(bad_advance) == "INVALID ADVANCE", "command schema bounds advance roll")
	var session := BattleSession.create([{"model_id": "u_m001", "position": Vector2(2, 2), "unit_id": "u", "team": 0}], 11, 0)
	check(not session.is_empty() and BattleSession.validate_snapshot(session).is_empty() and session.phase == "COMMAND", "authoritative session creates a versioned snapshot")
	var session_move := BattleSession.submit(session, 0, "MOVE", {"unit_id": "u", "delta": [1, 0]})
	check(not session_move.ok and session_move.reason == "INVALID PHASE", "authoritative session rejects movement in command phase")
	session = BattleSession.advance_phase(session).state
	var accepted_move := BattleSession.submit(session, 0, "MOVE", {"unit_id": "u", "delta": [1, 0]})
	check(accepted_move.ok and accepted_move.state.command_log.size() == 2 and accepted_move.state.phase == "MOVEMENT", "authoritative session accepts a legal movement command")
	var terrain_session := BattleSession.create([{"model_id": "session_terrain_m001", "position": Vector2(2, 5), "unit_id": "session_terrain", "team": 0, "radius": 0.5, "movement_inches": 10.0}], 11, 0, [{"id": "session_wall", "x": 4.0, "y": 4.0, "width": 2.0, "height": 2.0}])
	terrain_session = BattleSession.advance_phase(terrain_session).state
	var blocked_session_move := BattleSession.submit(terrain_session, 0, "MOVE", {"unit_id": "session_terrain", "delta": [6, 0]})
	check(not blocked_session_move.ok and blocked_session_move.reason == "TERRAIN BLOCKED", "authoritative session blocks terrain crossing")
	var wrong_end_turn := BattleSession.submit(accepted_move.state, 1, "END_TURN", {})
	check(not wrong_end_turn.ok and wrong_end_turn.reason == "NOT ACTIVE TEAM", "authoritative session rejects foreign end turn")
	var ended_session := BattleSession.submit(accepted_move.state, 0, "END_TURN", {})
	check(ended_session.ok and ended_session.state.active_team == 1 and ended_session.state.phase == "COMMAND" and ended_session.state.command_points[1] == 1, "authoritative session advances to command phase and grants command point")
	var scored_session := BattleSession.create([{"model_id": "score_m001", "position": Vector2(10, 10), "unit_id": "score_unit", "team": 0, "objective_control": 3}], 11, 0, [], [{"position": Vector2(10, 10), "points": 2}], 3.0, 2)
	var scored_turn := BattleSession.submit(scored_session, 0, "END_TURN", {})
	check(scored_turn.ok and scored_turn.state.score[0] == 2 and scored_turn.state.winner == 0 and scored_turn.state.objectives.size() == 1 and scored_turn.state.score_to_win == 2, "authoritative session scores mission objectives and records the winner")
	var finished_command := BattleSession.submit(scored_turn.state, 1, "END_TURN", {})
	check(not finished_command.ok and finished_command.reason == "BATTLE FINISHED", "authoritative session rejects commands after mission victory")
	var bad_snapshot: Dictionary = accepted_move.state.duplicate(true)
	bad_snapshot.ruleset_id = "wh40k_unknown"
	check(BattleSession.validate_snapshot(bad_snapshot) == "RULESET MISMATCH", "authoritative session rejects mismatched ruleset")
	var duplicate_snapshot: Dictionary = accepted_move.state.duplicate(true)
	duplicate_snapshot.models.append(duplicate_snapshot.models[0].duplicate(true))
	check(BattleSession.validate_snapshot(duplicate_snapshot) == "DUPLICATE MODEL ID u_m001", "authoritative session rejects duplicate model ids")
	var room := Room.create("room-test", 11, 1000, "control_center", [{"id": "wall", "x": 4.0, "y": 4.0, "width": 2.0, "height": 2.0}])
	check(not room.is_empty() and Room.validate(room).is_empty() and room.status == Room.WAITING, "room creates waiting lifecycle")
	var joined_gold := Room.join(room, "player_gold", 0)
	room = joined_gold.room
	check(joined_gold.ok and joined_gold.team == 0, "room assigns preferred team")
	var joined_blue := Room.join(room, "player_blue", 1)
	room = joined_blue.room
	check(joined_blue.ok and joined_blue.team == 1 and room.players.size() == 2, "room joins second player")
	check(not Room.join(room, "spectator", -1).ok, "room rejects third player")
	room = Room.set_ready(room, "player_gold").room
	check(not Room.start(room, [{"model_id": "room_m001", "unit_id": "room_unit", "team": 0, "position": Vector2(2, 2)}]).ok, "room waits for both ready players")
	room = Room.set_ready(room, "player_blue").room
	var started_room := Room.start(room, [{"model_id": "room_m001", "unit_id": "room_unit", "team": 0, "position": Vector2(2, 2)}])
	room = started_room.room
	check(started_room.ok and room.status == Room.ACTIVE and room.session.phase == "COMMAND", "room starts authoritative session")
	var wrong_room_command := Room.submit(room, "player_blue", "PHASE_ADVANCE", {"from": "COMMAND", "to": "MOVEMENT"})
	check(not wrong_room_command.ok and wrong_room_command.reason == "NOT ACTIVE TEAM", "room maps player to team")
	var room_advanced := Room.submit(room, "player_gold", "PHASE_ADVANCE", {"from": "COMMAND", "to": "MOVEMENT"})
	room = room_advanced.room
	check(room_advanced.ok and room.session.phase == "MOVEMENT", "room submits legal command")
	var room_move := Room.submit(room, "player_gold", "MOVE", {"unit_id": "room_unit", "delta": [1, 0]})
	room = room_move.room
	check(room_move.ok and room.session.models[0].position == Vector2(3, 2), "room persists authoritative command state")
	check(not Room.public_snapshot(room).session.has("command_log"), "room public snapshot omits command log")
	var peer_session_id := PeerProtocol.hash_snapshot({"room_id": room.id, "edition": int(room.edition), "mission": room.mission_id})
	var peer_snapshot := PeerProtocol.snapshot(room.id, "player_gold", peer_session_id, 1, room.session, joined_gold.reconnect_token)
	check(PeerProtocol.validate(peer_snapshot).is_empty(), "peer snapshot validates its integrity hash")
	var disconnect_result := Room.drop_connection(room, "player_gold")
	var reconnect_result := Room.reconnect(disconnect_result.room, "player_gold", joined_gold.reconnect_token, 1)
	check(disconnect_result.ok and reconnect_result.ok and reconnect_result.snapshot.state.phase == room.session.phase, "room restores a disconnected player from reconnect token")
	var command_packet := PeerProtocol.command(room.id, "player_gold", peer_session_id, 2, 1, {"sequence": 2, "team": 0, "kind": "PHASE_ADVANCE", "payload": {"from": "MOVEMENT", "to": "SHOOTING"}}, PeerProtocol.hash_snapshot(room.session))
	check(PeerProtocol.sequence_status(1, command_packet) == "NEXT", "peer command sequence advances without a gap")
	var duplicate_packet: Dictionary = command_packet.duplicate(true)
	duplicate_packet.sequence = 1
	duplicate_packet.ack = 0
	check(NetworkSync.host_command(room, duplicate_packet, "player_gold").reason == "COMMAND SEQUENCE GAP", "host rejects retransmitted command sequence")
	var future_packet: Dictionary = command_packet.duplicate(true)
	future_packet.sequence = 99
	future_packet.ack = 98
	check(NetworkSync.host_command(room, future_packet, "player_gold").reason == "COMMAND SEQUENCE GAP", "host rejects command sequence gaps")
	var bad_token := Room.reconnect(disconnect_result.room, "player_gold", "forged-reconnect-token", 1)
	check(not bad_token.ok and bad_token.reason == "INVALID RECONNECT TOKEN", "room rejects forged reconnect token")
	var dropped_command_room: Dictionary = disconnect_result.room.duplicate(true)
	var dropped_command := Room.submit(dropped_command_room, "player_gold", "PHASE_ADVANCE", {"from": "MOVEMENT", "to": "SHOOTING"})
	check(not dropped_command.ok and dropped_command.reason == "PLAYER DISCONNECTED", "disconnected player cannot submit through room API")

	var wrong_session_packet: Dictionary = command_packet.duplicate(true)
	wrong_session_packet.session_id = "wrong-room-session"
	check(NetworkSync.host_command(room, wrong_session_packet, "player_gold").reason == "SESSION ID MISMATCH", "host rejects commands from a different relay session")
	var synced := NetworkSync.host_command(room, command_packet, "player_gold")
	check(synced.ok and synced.room.session.phase == "SHOOTING", "host sync applies a verified peer command")
	var movement_room: Dictionary = room.duplicate(true)
	movement_room.session = BattleSession.create([
		{"model_id": "charger", "unit_id": "charge_unit", "team": 0, "position": Vector2(10, 10), "radius": 0.5, "movement_inches": 6.0, "wounds": 3},
		{"model_id": "charge_target", "unit_id": "enemy_unit", "team": 1, "position": Vector2(13, 10), "radius": 0.5, "wounds": 3}])
	movement_room.session.phase = "MOVEMENT"
	movement_room.session.phase_index = 1
	var advance_intent := {"sequence": 0, "team": 0, "kind": "ADVANCE", "payload": {"intent": true, "unit_id": "charge_unit", "roll": 999}}
	var advance_packet := PeerProtocol.command(room.id, "player_gold", peer_session_id, 0, -1, advance_intent, PeerProtocol.hash_snapshot(movement_room.session))
	var host_advance := NetworkSync.host_command(movement_room, advance_packet, "player_gold")
	check(host_advance.ok and host_advance.entry.payload.roll >= 1 and host_advance.entry.payload.roll <= 6 and host_advance.room.session.models[0].advance_bonus == host_advance.entry.payload.roll, "host rolls advance and ignores uploaded die")
	check(Replay.apply_entry(movement_room.session, host_advance.entry).state.models == host_advance.room.session.models, "advance authoritative result replays identically")
	advance_intent.payload.erase("intent")
	advance_intent.payload.roll = 6
	advance_packet = PeerProtocol.command(room.id, "player_gold", peer_session_id, 0, -1, advance_intent, PeerProtocol.hash_snapshot(movement_room.session))
	check(NetworkSync.host_command(movement_room, advance_packet, "player_gold").reason == "HOST RESOLUTION REQUIRED", "remote advance cannot upload a resolved roll")
	movement_room.session.phase = "CHARGE"
	movement_room.session.phase_index = 3
	var charge_intent := {"sequence": 0, "team": 0, "kind": "CHARGE", "payload": {"intent": true, "model_id": "charger", "target_id": "charge_target", "roll": [99, 99], "to": [50, 40], "failed": true}}
	var charge_packet := PeerProtocol.command(room.id, "player_gold", peer_session_id, 0, -1, charge_intent, PeerProtocol.hash_snapshot(movement_room.session))
	var invalid_charge_packet: Dictionary = charge_packet.duplicate(true)
	invalid_charge_packet.command.payload.erase("model_id")
	invalid_charge_packet.command.payload.model = 999999
	check(NetworkSync.host_command(movement_room, invalid_charge_packet, "player_gold").reason == "INVALID CHARGE", "out of bounds charge model index is safely rejected")
	invalid_charge_packet.command.payload.model_id = "unknown_model"
	invalid_charge_packet.command.payload.model = 0
	check(NetworkSync.host_command(movement_room, invalid_charge_packet, "player_gold").reason == "INVALID CHARGE", "unknown stable charge ID cannot fall back to another model")
	var host_charge := NetworkSync.host_command(movement_room, charge_packet, "player_gold")
	check(host_charge.ok and not host_charge.entry.payload.failed and host_charge.room.session.models[0].position == Vector2(11, 10), "host computes charge endpoint and ignores uploaded result")
	check(host_charge.entry.payload.roll.size() == 2 and host_charge.entry.payload.roll[0] >= 1 and host_charge.entry.payload.roll[0] <= 6 and host_charge.entry.payload.roll[1] >= 1 and host_charge.entry.payload.roll[1] <= 6, "host charge records two valid dice")
	check(Replay.apply_entry(movement_room.session, host_charge.entry).state.models == host_charge.room.session.models, "successful charge replays identically")
	charge_intent.sequence = 1
	var charge_again := PeerProtocol.command(room.id, "player_gold", peer_session_id, 1, 0, charge_intent, PeerProtocol.hash_snapshot(host_charge.room.session))
	check(NetworkSync.host_command(host_charge.room, charge_again, "player_gold").reason == "CHARGE ALREADY ATTEMPTED", "successful charge cannot reroll by submitting again")
	movement_room.session.models[1].position = Vector2(24, 10)
	charge_intent.sequence = 0
	# Pick a deterministic fixture whose 2D6 cannot cover twelve inches.
	var failed_charge_session := peer_session_id
	var failed_rng_seed := 1
	for seed_index in range(100):
		var fixture_rng := seeded_rng(seed_index)
		if fixture_rng.randi_range(1, 6) + fixture_rng.randi_range(1, 6) < 12:
			failed_rng_seed = seed_index
			break
	charge_packet = PeerProtocol.command(room.id, "player_gold", peer_session_id, 0, -1, charge_intent, PeerProtocol.hash_snapshot(movement_room.session))
	var seed_probe: Dictionary = charge_packet.duplicate(true)
	seed_probe.command.payload.seed = 99999
	seed_probe.command.payload.rng_state = 777
	var baseline_seed := NetworkSync.host_command(movement_room, charge_packet, "player_gold", seeded_rng(87))
	var changed_seed := NetworkSync.host_command(movement_room, seed_probe, "player_gold", seeded_rng(87))
	check(baseline_seed.ok and changed_seed.ok and baseline_seed.entry.payload == changed_seed.entry.payload, "client session and injected seed cannot control host charge dice")
	var secret_snapshot := JSON.stringify(baseline_seed.snapshot)
	check(not secret_snapshot.contains("rng_state") and not secret_snapshot.contains("host_rng") and not secret_snapshot.contains("entropy"), "authoritative snapshots contain results without private random state")
	var failed_charge := NetworkSync.host_command(movement_room, charge_packet, "player_gold", seeded_rng(failed_rng_seed))
	check(failed_charge.ok and failed_charge.entry.payload.failed and failed_charge.room.session.models[0].position == Vector2(10, 10) and failed_charge.room.session.models[0].charge_attempted and not failed_charge.room.session.models[0].charged, "failed charge consumes attempt without moving")
	check(Replay.apply_entry(movement_room.session, failed_charge.entry).state.models == failed_charge.room.session.models, "failed charge replays identically")
	charge_intent.sequence = 1
	charge_again = PeerProtocol.command(room.id, "player_gold", failed_charge_session, 1, 0, charge_intent, PeerProtocol.hash_snapshot(failed_charge.room.session))
	check(NetworkSync.host_command(failed_charge.room, charge_again, "player_gold").reason == "CHARGE ALREADY ATTEMPTED", "failed charge cannot reroll by submitting again")
	var reset_charge_state: Dictionary = failed_charge.room.session.duplicate(true)
	reset_charge_state.phase = "COMMAND"
	reset_charge_state.phase_index = 0
	var reset_charge := BattleSession.submit(reset_charge_state, 0, "PHASE_ADVANCE", {"from": "COMMAND", "to": "MOVEMENT"})
	check(reset_charge.ok and not reset_charge.state.models[0].charge_attempted, "new movement phase resets charge attempt")
	charge_intent.sequence = 0
	charge_intent.payload.erase("intent")
	charge_intent.payload.model = 0
	charge_intent.payload.target = 1
	charge_packet = PeerProtocol.command(room.id, "player_gold", peer_session_id, 0, -1, charge_intent, PeerProtocol.hash_snapshot(movement_room.session))
	check(NetworkSync.host_command(movement_room, charge_packet, "player_gold").reason == "HOST RESOLUTION REQUIRED", "remote charge cannot upload resolved dice")
	var hazard_packet := PeerProtocol.command(room.id, "player_gold", peer_session_id, 0, -1, {"sequence": 0, "team": 0, "kind": "HAZARDOUS", "payload": {"attacker": 0, "damage": 3}}, PeerProtocol.hash_snapshot(movement_room.session))
	check(NetworkSync.host_command(movement_room, hazard_packet, "player_gold").reason == "HAZARDOUS REQUIRES HOST ATTACK", "remote standalone hazardous results are rejected")
	# Original fixture mechanics, not an official faction datasheet.
	var grant := {"id": "fixture_mobility", "cost": 1, "phase": "MOVEMENT", "effect": "GRANT_ABILITY", "timing": "MOVEMENT", "target": "FRIENDLY_UNIT", "duration": "BATTLE", "ability": "fall_back_and_shoot"}
	var grant_room: Dictionary = room.duplicate(true)
	grant_room.session.command_points = [2, 0]
	grant_room.session.models[0].faction_stratagems = [grant]
	var grant_payload := {"id": "fixture_mobility", "phase": "MOVEMENT", "unit_id": "room_unit", "ability": "invulnerable_4", "effect": "CLIENT_OVERRIDE"}
	var grant_entry := {"sequence": 2, "team": 0, "kind": "STRATAGEM", "payload": grant_payload}
	var grant_packet := PeerProtocol.command(room.id, "player_gold", peer_session_id, 2, 1, grant_entry, PeerProtocol.hash_snapshot(grant_room.session))
	var grant_network := NetworkSync.host_command(grant_room, grant_packet, "player_gold")
	check(grant_network.ok and grant_network.room.session.models[0].ability_ids.has("fall_back_and_shoot"), "host executes data-defined grant instead of recording only effect")
	check(not grant_network.room.session.models[0].ability_ids.has("invulnerable_4") and grant_network.room.session.command_points[0] == 1, "host ignores client ability override and spends authoritative cost")
	check(UnitAbilities.modifiers(grant_network.room.session.models[0].ability_ids).fall_back_and_shoot, "granted ability activates existing rules consumer")
	var grant_attacker: Dictionary = grant_network.room.session.models[0].duplicate(true)
	grant_attacker.fell_back = true
	check(Combat.target_reason(grant_attacker, {"team": 1}, 5.0, {"range_inches": 24}, 0).is_empty(), "granted fallback ability changes actual shooting eligibility")
	var filtered_grant_room: Dictionary = grant_room.duplicate(true)
	filtered_grant_room.session.models[0].faction_stratagems[0].target_keywords = ["INFANTRY", "FIXTURE_FACTION"]
	filtered_grant_room.session.models[0].keywords = ["INFANTRY"]
	filtered_grant_room.session.models[0].faction_keywords = ["FIXTURE_FACTION"]
	var filtered_grant_packet: Dictionary = grant_packet.duplicate(true)
	filtered_grant_packet.snapshot_hash = PeerProtocol.hash_snapshot(filtered_grant_room.session)
	var filtered_grant := NetworkSync.host_command(filtered_grant_room, filtered_grant_packet, "player_gold")
	check(filtered_grant.ok and filtered_grant.room.session.models[0].ability_ids.has("fall_back_and_shoot"), "strategy target filters accept unit and faction keywords")
	check(Replay.apply_entry(filtered_grant_room.session, filtered_grant.entry).state.models == filtered_grant.room.session.models, "keyword restricted strategy executes identically in replay")
	filtered_grant_room.session.models[0].faction_keywords = []
	filtered_grant_packet.command.payload.target_keywords = []
	filtered_grant_packet.snapshot_hash = PeerProtocol.hash_snapshot(filtered_grant_room.session)
	filtered_grant = NetworkSync.host_command(filtered_grant_room, filtered_grant_packet, "player_gold")
	check(not filtered_grant.ok and filtered_grant.reason == "STRATAGEM TARGET MISSING KEYWORD FIXTURE_FACTION" and filtered_grant.room == filtered_grant_room, "client cannot override required keywords or spend CP on rejected target")
	var filter_definition: Dictionary = filtered_grant_room.session.models[0].faction_stratagems[0].duplicate(true)
	check(Stratagems.target_keywords_reason(filter_definition, [{"keywords": ["INFANTRY"]}, {"faction_keywords": ["FIXTURE_FACTION"]}]).is_empty(), "attached recipient keyword filter uses member union")
	filter_definition.excluded_target_keywords = ["VEHICLE"]
	check(Stratagems.target_keywords_reason(filter_definition, [{"keywords": ["INFANTRY", "VEHICLE"], "faction_keywords": ["FIXTURE_FACTION"]}]) == "STRATAGEM TARGET EXCLUDED KEYWORD VEHICLE", "excluded recipient keyword takes priority")
	filter_definition.target_keywords = "INFANTRY"
	check(Stratagems.validate(filter_definition) == "INVALID STRATAGEM TARGET FILTER", "strategy rejects malformed keyword array")
	filter_definition.target_keywords = [5]
	check(Stratagems.validate(filter_definition) == "INVALID STRATAGEM TARGET KEYWORD", "strategy rejects non string target keyword")
	filter_definition.target_keywords = []
	filter_definition.effect = "REROLL_HIT"
	check(Stratagems.validate(filter_definition) == "INVALID STRATAGEM TARGET FILTER", "unsupported strategy effect cannot silently ignore target filter")
	var capped_room: Dictionary = grant_room.duplicate(true)
	capped_room.session.models[0].faction_stratagems[0].usage_limit = {"scope": "PHASE", "max": 1}
	var capped_packet: Dictionary = grant_packet.duplicate(true)
	capped_packet.snapshot_hash = PeerProtocol.hash_snapshot(capped_room.session)
	var capped_first := NetworkSync.host_command(capped_room, capped_packet, "player_gold")
	check(capped_first.ok and capped_first.room.session.stratagem_usage.size() == 1, "successful strategy records authoritative usage")
	var capped_second_packet := PeerProtocol.command(room.id, "player_gold", peer_session_id, 3, 2, {"sequence": 3, "team": 0, "kind": "STRATAGEM", "payload": grant_payload}, PeerProtocol.hash_snapshot(capped_first.room.session))
	capped_second_packet.command.payload.usage_limit = {"scope": "BATTLE", "max": 999}
	var capped_second := NetworkSync.host_command(capped_first.room, capped_second_packet, "player_gold")
	check(not capped_second.ok and capped_second.reason == "STRATAGEM USAGE LIMIT REACHED" and capped_second.room == capped_first.room, "same phase strategy repeat rejects atomically despite client override")
	var capped_definition: Dictionary = capped_room.session.models[0].faction_stratagems[0]
	var capped_next: Dictionary = capped_first.room.session.duplicate(true)
	capped_next.phase = "SHOOTING"
	check(Stratagems.usage_reason(capped_definition, capped_next, 0).is_empty(), "phase usage cap releases at another phase")
	capped_definition.usage_limit.scope = "TURN"
	check(not Stratagems.usage_reason(capped_definition, capped_next, 0).is_empty(), "turn usage cap survives phase changes")
	capped_next.round += 1
	capped_next.active_team = 1
	check(Stratagems.usage_reason(capped_definition, capped_next, 0).is_empty(), "turn usage cap releases in another player turn")
	capped_definition.usage_limit.scope = "BATTLE"
	check(not Stratagems.usage_reason(capped_definition, capped_next, 0).is_empty(), "battle usage cap survives turn changes")
	check(Stratagems.usage_reason(capped_definition, capped_next, 1).is_empty(), "strategy usage limits are independent for both players")
	var capped_replay := Replay.apply_entry(capped_room.session, capped_first.entry)
	check(capped_replay.ok and capped_replay.state.stratagem_usage == capped_first.room.session.stratagem_usage, "replay reconstructs usage records")
	var capped_json: Dictionary = JSON.parse_string(PeerProtocol.encode(capped_first.snapshot))
	var capped_restored := NetworkSync.accept_snapshot({}, capped_json)
	check(capped_restored.ok and not Stratagems.usage_reason(capped_definition, capped_restored.state, 0).is_empty(), "JSON reconnect preserves consumed strategy allowance")
	var corrupt_usage: Dictionary = capped_first.room.session.duplicate(true)
	corrupt_usage.stratagem_usage[0].team = 0.5
	check(BattleSession.validate_snapshot(corrupt_usage) == "INVALID STRATAGEM USAGE", "snapshot rejects malformed strategy usage metadata")
	var bad_limit: Dictionary = capped_definition.duplicate(true)
	bad_limit.usage_limit.max = 1.5
	check(Stratagems.validate(bad_limit) == "INVALID STRATAGEM USAGE LIMIT", "fractional strategy usage caps rejected")
	bad_limit.usage_limit = {"scope": "ROUND", "max": 1}
	check(Stratagems.validate(bad_limit) == "INVALID STRATAGEM USAGE LIMIT", "unknown strategy usage scopes rejected")
	var grant_replay := Replay.apply_entry(grant_room.session, grant_entry)
	check(grant_replay.ok and grant_replay.state.models == grant_network.room.session.models, "grant replay matches host model state")
	var grant_snapshot := NetworkSync.accept_snapshot(grant_room.session, grant_network.snapshot)
	check(grant_snapshot.ok and grant_snapshot.state.models[0].ability_ids.has("fall_back_and_shoot"), "client snapshot retains executed grant")
	var bad_grant_entry: Dictionary = grant_entry.duplicate(true)
	var reaction_rule := {"id": "fixture_reactive_cover", "cost": 1, "phase": "MOVEMENT", "effect": "GRANT_ABILITY", "timing": "AFTER_ENEMY_MOVE", "target": "FRIENDLY_UNIT", "duration": "TURN", "ability": "stealth"}
	var reaction_models: Array = [
		{"model_id": "moving", "unit_id": "moving_unit", "team": 0, "position": Vector2(20, 10), "radius": 0.5, "movement_inches": 6, "wounds": 3},
		{"model_id": "responding", "unit_id": "responding_unit", "team": 1, "position": Vector2(30, 20), "radius": 0.5, "wounds": 3, "faction_stratagems": [reaction_rule]}
	]
	var reaction_room: Dictionary = room.duplicate(true)
	reaction_room.session = BattleSession.create(reaction_models)
	reaction_room.session.phase = "MOVEMENT"
	reaction_room.session.phase_index = 1
	reaction_room.session.command_points = [1, 1]
	var reaction_initial: Dictionary = reaction_room.session.duplicate(true)
	var trigger_entry := {"sequence": 0, "team": 0, "kind": "MOVE", "payload": {"unit_id": "moving_unit", "delta": [1, 0]}}
	var trigger_packet := PeerProtocol.command(room.id, "player_gold", peer_session_id, 0, -1, trigger_entry, PeerProtocol.hash_snapshot(reaction_initial))
	var trigger_result := NetworkSync.host_command(reaction_room, trigger_packet, "player_gold")
	check(trigger_result.ok and trigger_result.room.session.reaction_window.team == 1, "enemy move opens data-declared reaction window")
	var waiting_state: Dictionary = trigger_result.room.session
	check(waiting_state.active_team == 0 and waiting_state.models[0].position == Vector2(21, 10), "reaction suspends priority after committed movement without changing active team")
	check(not BattleSession.submit(waiting_state, 0, "END_TURN", {}).ok, "active player cannot skip pending reaction")
	check(not BattleSession.submit(waiting_state, 1, "MOVE", {"unit_id": "responding_unit", "delta": [0, 1], "window_id": "move:0"}).ok, "responder cannot use reaction priority for normal actions")
	check(not BattleSession.submit(waiting_state, 1, "REACTION_PASS", {"window_id": "move:999"}).ok, "stale window identifier rejected")
	var reaction_payload := {"id": "fixture_reactive_cover", "phase": "MOVEMENT", "unit_id": "responding_unit", "window_id": "move:0"}
	var response_entry := {"sequence": 1, "team": 1, "kind": "STRATAGEM", "payload": reaction_payload}
	var response_packet := PeerProtocol.command(room.id, "player_blue", peer_session_id, 1, 0, response_entry, PeerProtocol.hash_snapshot(waiting_state))
	var responded := NetworkSync.host_command(trigger_result.room, response_packet, "player_blue")
	check(responded.ok and responded.room.session.models[1].ability_ids.has("stealth") and responded.room.session.command_points[1] == 0, "opponent reaction executes ability and spends responder points")
	check(not responded.room.session.has("reaction_window") and responded.room.session.active_team == 0, "reaction completion resumes original player's priority")
	var replayed_response := Replay.replay(reaction_initial, responded.room.session.command_log)
	check(replayed_response.ok and replayed_response.state.models == responded.room.session.models, "mixed-team reaction log replays host result")
	var passed_response := BattleSession.submit(waiting_state, 1, "REACTION_PASS", {"window_id": "move:0"})
	check(passed_response.ok and not passed_response.state.has("reaction_window") and passed_response.state.command_points[1] == 1, "passing closes reaction without spending points")
	check(not BattleSession.submit(passed_response.state, 1, "REACTION_PASS", {"window_id": "move:0"}).ok, "closed reaction cannot be reused")
	var outside_reaction: Dictionary = reaction_initial.duplicate(true)
	outside_reaction.active_team = 1
	check(not BattleSession.submit(outside_reaction, 1, "STRATAGEM", {"id": "fixture_reactive_cover", "phase": "MOVEMENT", "unit_id": "responding_unit"}).ok, "reactive strategy cannot be invoked without trigger")
	var no_budget: Dictionary = reaction_initial.duplicate(true)
	no_budget.command_points[1] = 0
	var no_budget_move := Replay.apply_entry(no_budget, trigger_entry)
	check(no_budget_move.ok and not no_budget_move.state.has("reaction_window"), "unaffordable reactions do not stall movement")
	var unimplemented_reaction := Stratagems.use(Stratagems.definition("fire_overwatch"), "MOVEMENT", 0, [1, 0])
	var shooting_rule := {"id": "fixture_reaction_shot", "cost": 1, "phase": "MOVEMENT", "timing": "AFTER_ENEMY_MOVE", "effect": "REACTION_SHOOT", "hit_on": 6}
	var shooting_room: Dictionary = reaction_room.duplicate(true)
	shooting_room.session.models[0].wounds = 100
	shooting_room.session.models[0].save_on = 7
	shooting_room.session.models[0].toughness = 4
	shooting_room.session.models[1].faction_stratagems = [shooting_rule]
	shooting_room.session.models[1].weapons = [{"name": "fixture_rifle", "range_inches": 24, "attacks": 30, "hit_on": 2, "strength": 5, "damage": 1}]
	var shot_trigger: Dictionary = trigger_packet.duplicate(true)
	shot_trigger.snapshot_hash = PeerProtocol.hash_snapshot(shooting_room.session)
	var shot_waiting := NetworkSync.host_command(shooting_room, shot_trigger, "player_gold")
	var shot_payload := {"id": "fixture_reaction_shot", "phase": "MOVEMENT", "window_id": "move:0", "attacker_id": "responding", "target_id": "moving", "weapon": "fixture_rifle", "attack": {"damage": 999}, "damage": 999, "hits": 999, "hit_on": 1}
	var shot_packet := PeerProtocol.command(room.id, "player_blue", peer_session_id, 1, 0, {"sequence": 1, "team": 1, "kind": "STRATAGEM", "payload": shot_payload}, PeerProtocol.hash_snapshot(shot_waiting.room.session))
	var shot_result := NetworkSync.host_command(shot_waiting.room, shot_packet, "player_blue", seeded_rng((peer_session_id + ":1").hash()))
	check(shot_result.ok and shot_result.entry.payload.attack.damage < 999 and shot_result.room.session.command_points[1] == 0, "reaction shooting overwrites client results and spends authoritative cost")
	var expected_shot_rng := RandomNumberGenerator.new()
	expected_shot_rng.seed = (peer_session_id + ":1").hash()
	var expected_shot := Combat.resolve_ranged_attack({"attacks": 30, "hit_on": 6, "strength": 5, "damage": 1}, {"toughness": 4, "save_on": 7}, expected_shot_rng)
	check(shot_result.entry.payload.attack.hits == expected_shot.hits and shot_result.entry.payload.attack.damage == expected_shot.damage, "reaction hit threshold comes from definition rather than client weapon override")
	check(shot_result.room.session.models[0].wounds == 100 - expected_shot.damage and not shot_result.room.session.has("reaction_window"), "reaction damage applied and window closes atomically")
	var shot_replay := Replay.replay(shooting_room.session, shot_result.room.session.command_log)
	check(shot_replay.ok and shot_replay.state.models == shot_result.room.session.models, "reaction attack result replays through normal damage rules")
	var conditional_shot_room: Dictionary = shot_waiting.room.duplicate(true)
	conditional_shot_room.session.models[1].ability_ids = [{"id": "fixture_reaction_wounds", "events": {"before_attack": {"when": {"phase": "MOVEMENT", "kind": "SHOOT"}, "modifiers": {"wound_rerolls": 100}}}}]
	var conditional_shot_packet: Dictionary = shot_packet.duplicate(true)
	conditional_shot_packet.snapshot_hash = PeerProtocol.hash_snapshot(conditional_shot_room.session)
	var conditional_shot := NetworkSync.host_command(conditional_shot_room, conditional_shot_packet, "player_blue", seeded_rng(87))
	var conditional_expected := Combat.resolve_ranged_attack({"attacks": 30, "hit_on": 6, "strength": 5, "damage": 1}, {"toughness": 4, "save_on": 7}, seeded_rng(87), 0, {"wound_rerolls": 100})
	check(conditional_shot.ok and conditional_shot.entry.payload.attack.damage == conditional_expected.damage, "reaction attack event evaluates actual movement phase")
	conditional_shot_room.session.models[1].ability_ids[0].events.before_attack.when.phase = "SHOOTING"
	conditional_shot_packet.snapshot_hash = PeerProtocol.hash_snapshot(conditional_shot_room.session)
	conditional_shot = NetworkSync.host_command(conditional_shot_room, conditional_shot_packet, "player_blue", seeded_rng(87))
	conditional_expected = Combat.resolve_ranged_attack({"attacks": 30, "hit_on": 6, "strength": 5, "damage": 1}, {"toughness": 4, "save_on": 7}, seeded_rng(87))
	check(conditional_shot.ok and conditional_shot.entry.payload.attack.damage == conditional_expected.damage, "shooting phase only passive cannot leak into movement reaction")
	var filtered_shot_room: Dictionary = shot_waiting.room.duplicate(true)
	filtered_shot_room.session.models[1].faction_stratagems[0].target_keywords = ["INFANTRY"]
	var filtered_shot_packet: Dictionary = shot_packet.duplicate(true)
	filtered_shot_packet.snapshot_hash = PeerProtocol.hash_snapshot(filtered_shot_room.session)
	var filtered_shot := NetworkSync.host_command(filtered_shot_room, filtered_shot_packet, "player_blue")
	check(not filtered_shot.ok and filtered_shot.reason == "STRATAGEM TARGET MISSING KEYWORD INFANTRY" and filtered_shot.room == filtered_shot_room, "reaction shooter restriction rejects without damage CP spend or closing window")
	filtered_shot_room.session.models[1].keywords = ["INFANTRY"]
	filtered_shot_packet.snapshot_hash = PeerProtocol.hash_snapshot(filtered_shot_room.session)
	filtered_shot = NetworkSync.host_command(filtered_shot_room, filtered_shot_packet, "player_blue")
	check(filtered_shot.ok and not filtered_shot.room.session.has("reaction_window"), "eligible reaction shooter applies strategy and closes window")
	var no_recipient_room: Dictionary = shooting_room.duplicate(true)
	no_recipient_room.session.models[1].faction_stratagems[0].target_keywords = ["UNAVAILABLE_KEYWORD"]
	var no_recipient_packet: Dictionary = shot_trigger.duplicate(true)
	no_recipient_packet.snapshot_hash = PeerProtocol.hash_snapshot(no_recipient_room.session)
	var no_recipient_move := NetworkSync.host_command(no_recipient_room, no_recipient_packet, "player_gold")
	check(no_recipient_move.ok and not no_recipient_move.room.session.has("reaction_window"), "reaction with no keyword eligible recipient does not stall movement")
	var exhausted_shot_room: Dictionary = shot_result.room.duplicate(true)
	exhausted_shot_room.session.command_points[1] = 2
	exhausted_shot_room.session.models[1].faction_stratagems[0].usage_limit = {"scope": "PHASE", "max": 1}
	var exhausted_move := PeerProtocol.command(room.id, "player_gold", peer_session_id, 2, 1, {"sequence": 2, "team": 0, "kind": "MOVE", "payload": {"unit_id": "moving_unit", "delta": [0, 1]}}, PeerProtocol.hash_snapshot(exhausted_shot_room.session))
	var exhausted_result := NetworkSync.host_command(exhausted_shot_room, exhausted_move, "player_gold")
	check(exhausted_result.ok and not exhausted_result.room.session.has("reaction_window"), "exhausted reaction strategy does not reopen a window")
	var unknown_weapon_packet: Dictionary = shot_packet.duplicate(true)
	unknown_weapon_packet.command.payload.weapon = "fake"
	var bad_weapon := NetworkSync.host_command(shot_waiting.room, unknown_weapon_packet, "player_blue")
	check(not bad_weapon.ok and bad_weapon.room == shot_waiting.room, "unknown reaction weapon leaves CP and pending window unchanged")
	var distant_room: Dictionary = shot_waiting.room.duplicate(true)
	distant_room.session.models[1].position = Vector2(59, 43)
	var distant_packet: Dictionary = shot_packet.duplicate(true)
	distant_packet.snapshot_hash = PeerProtocol.hash_snapshot(distant_room.session)
	check(not NetworkSync.host_command(distant_room, distant_packet, "player_blue").ok, "reaction validates actual weapon range")
	var blocked_room: Dictionary = shot_waiting.room.duplicate(true)
	blocked_room.session.terrain = [{"x": 24.0, "y": 10.0, "width": 2.0, "height": 20.0}]
	var blocked_packet: Dictionary = shot_packet.duplicate(true)
	blocked_packet.snapshot_hash = PeerProtocol.hash_snapshot(blocked_room.session)
	check(not NetworkSync.host_command(blocked_room, blocked_packet, "player_blue").ok, "direct reaction shot cannot cross blocking terrain")
	var shot_no_window: Dictionary = shot_waiting.room.duplicate(true)
	shot_no_window.session.erase("reaction_window")
	var shot_no_window_packet: Dictionary = shot_packet.duplicate(true)
	shot_no_window_packet.snapshot_hash = PeerProtocol.hash_snapshot(shot_no_window.session)
	check(not NetworkSync.host_command(shot_no_window, shot_no_window_packet, "player_blue").ok, "reaction shooting cannot execute after its window closes")
	var host_reaction_probe = P2PLobby.new()
	root.add_child(host_reaction_probe)
	await process_frame
	host_reaction_probe.room = shot_waiting.room.duplicate(true)
	host_reaction_probe.player_id = "player_blue"
	host_reaction_probe.is_host = true
	var host_reaction_error: String = host_reaction_probe.submit_command("STRATAGEM", shot_payload)
	check(host_reaction_error.is_empty() and not host_reaction_probe.room.session.has("reaction_window"), "host player's reaction uses same materialization path as remote player")
	host_reaction_probe.queue_free()
	var wrong_target_room: Dictionary = shot_waiting.room.duplicate(true)
	wrong_target_room.session.models.append({"model_id": "unrelated", "unit_id": "unrelated_unit", "team": 0, "position": Vector2(30, 25), "wounds": 3})
	var wrong_target_packet: Dictionary = shot_packet.duplicate(true)
	wrong_target_packet.snapshot_hash = PeerProtocol.hash_snapshot(wrong_target_room.session)
	wrong_target_packet.command.payload.target_id = "unrelated"
	check(not NetworkSync.host_command(wrong_target_room, wrong_target_packet, "player_blue").ok, "reaction cannot select unrelated enemy unit")
	check(not unimplemented_reaction.ok and unimplemented_reaction.points == [1, 0], "unimplemented reaction shooting fails without spending points")
	var corrupt_window: Dictionary = waiting_state.duplicate(true)
	corrupt_window.reaction_window.team = 0
	check(not BattleSession.validate_snapshot(corrupt_window).is_empty(), "snapshot rejects reaction priority assigned to active player")
	var reaction_wire := PeerProtocol.snapshot(room.id, "player_gold", peer_session_id, 0, waiting_state)
	var reaction_restored := NetworkSync.accept_snapshot(reaction_initial, JSON.parse_string(PeerProtocol.encode(reaction_wire)))
	check(reaction_restored.ok and reaction_restored.state.reaction_window.id == "move:0", "reaction window survives serialized reconnect snapshot")
	var response_turn_end := BattleSession.submit(responded.room.session, 0, "END_TURN", {})
	check(response_turn_end.ok and not response_turn_end.state.models[1].ability_ids.has("stealth"), "reactive turn grant expires when triggering turn ends")
	var phase_grant_state: Dictionary = grant_room.session.duplicate(true)
	phase_grant_state.models[0].faction_stratagems[0].duration = "PHASE"
	var phase_granted := Replay.apply_entry(phase_grant_state, grant_entry)
	check(phase_granted.ok and phase_granted.state.models[0].ability_grants.fall_back_and_shoot.durations == ["PHASE"], "phase grant records authoritative expiry metadata")
	var phase_command := {"sequence": 3, "team": 0, "kind": "PHASE_ADVANCE", "payload": {"from": "MOVEMENT", "to": "SHOOTING"}}
	var expired_phase := Replay.apply_entry(phase_granted.state, phase_command)
	check(expired_phase.ok and not expired_phase.state.models[0].ability_ids.has("fall_back_and_shoot"), "phase grant expires before next phase actions")
	var defensive_grant_state: Dictionary = phase_grant_state.duplicate(true)
	defensive_grant_state.models[0].faction_stratagems[0].ability = "invulnerable_4"
	var defensive_granted := Replay.apply_entry(defensive_grant_state, grant_entry)
	var defensive_preview := Combat.resolve_ranged_attack({"attacks": 1}, defensive_granted.state.models[0], seeded_rng(87))
	check(defensive_granted.ok and defensive_preview.save_on == 4, "data strategy grants executable invulnerable save")
	var defensive_expired := Replay.apply_entry(defensive_granted.state, phase_command)
	defensive_preview = Combat.resolve_ranged_attack({"attacks": 1}, defensive_expired.state.models[0], seeded_rng(87))
	check(defensive_expired.ok and defensive_preview.save_on == 7, "temporary defensive grant expires without stale cached save")
	var turn_grant_state: Dictionary = phase_grant_state.duplicate(true)
	turn_grant_state.models[0].faction_stratagems[0].duration = "TURN"
	var turn_granted := Replay.apply_entry(turn_grant_state, grant_entry)
	var turn_advanced := Replay.apply_entry(turn_granted.state, phase_command)
	check(turn_advanced.ok and turn_advanced.state.models[0].ability_ids.has("fall_back_and_shoot"), "turn grant survives phase boundary")
	var turn_command := {"sequence": 4, "team": 0, "kind": "END_TURN", "payload": {}}
	var turn_expired := Replay.apply_entry(turn_advanced.state, turn_command)
	check(turn_expired.ok and not turn_expired.state.models[0].ability_ids.has("fall_back_and_shoot"), "turn grant expires on turn end")
	var native_grant_state: Dictionary = phase_grant_state.duplicate(true)
	native_grant_state.models[0].ability_ids = ["fall_back_and_shoot"]
	var native_granted := Replay.apply_entry(native_grant_state, grant_entry)
	var native_expired := Replay.apply_entry(native_granted.state, phase_command)
	check(native_expired.ok and native_expired.state.models[0].ability_ids.has("fall_back_and_shoot"), "temporary grant expiry preserves native ability")
	var stacked_grant_state: Dictionary = turn_granted.state.duplicate(true)
	stacked_grant_state.models[0].faction_stratagems[0].duration = "PHASE"
	var stacked_granted := Replay.apply_entry(stacked_grant_state, grant_entry)
	var stacked_expired := Replay.apply_entry(stacked_granted.state, phase_command)
	check(stacked_expired.ok and stacked_expired.state.models[0].ability_ids.has("fall_back_and_shoot"), "shorter grant expiration preserves overlapping turn grant")
	var permanent_expired := Replay.apply_entry(grant_replay.state, turn_command)
	check(permanent_expired.ok and permanent_expired.state.models[0].ability_ids.has("fall_back_and_shoot"), "battle grant survives turn boundary")
	var phase_end_expired := Replay.apply_entry(phase_granted.state, turn_command)
	check(phase_end_expired.ok and not phase_end_expired.state.models[0].ability_ids.has("fall_back_and_shoot"), "turn end also expires phase grant")
	var duration_room: Dictionary = grant_room.duplicate(true)
	duration_room.session = phase_grant_state.duplicate(true)
	var duration_packet: Dictionary = grant_packet.duplicate(true)
	duration_packet.snapshot_hash = PeerProtocol.hash_snapshot(duration_room.session)
	var duration_host := NetworkSync.host_command(duration_room, duration_packet, "player_gold")
	check(duration_host.ok and duration_host.room.session.models[0].ability_grants.fall_back_and_shoot.durations == ["PHASE"], "network grant retains host-defined temporary duration")
	var decoded_duration: Dictionary = JSON.parse_string(PeerProtocol.encode(duration_host.snapshot))
	var duration_snapshot := NetworkSync.accept_snapshot(duration_room.session, decoded_duration)
	check(duration_snapshot.ok and duration_snapshot.state.models[0].ability_grants.fall_back_and_shoot.durations == ["PHASE"], "serialized snapshot preserves temporary expiry metadata")
	check(duration_snapshot.state.models[0].position is Vector2 and PeerProtocol.hash_snapshot(duration_snapshot.state) == duration_host.snapshot.snapshot_hash, "decoded snapshot restores live coordinates without changing hash")
	check(PeerProtocol.hash_snapshot({"value": 1}) == PeerProtocol.hash_snapshot({"value": 1.0}), "hash normalizes JSON integral number types")
	var legacy_packet: Dictionary = duration_host.snapshot.duplicate(true)
	legacy_packet.version = 1
	check(not PeerProtocol.validate(legacy_packet).is_empty(), "legacy wire protocol is rejected after canonical encoding change")
	var expiry_packet := PeerProtocol.command(room.id, "player_gold", peer_session_id, 3, 2, phase_command, PeerProtocol.hash_snapshot(duration_host.room.session))
	var duration_expired := NetworkSync.host_command(duration_host.room, expiry_packet, "player_gold")
	check(duration_expired.ok and not duration_expired.room.session.models[0].ability_ids.has("fall_back_and_shoot"), "network phase transition expires granted ability")
	var corrupt_duration: Dictionary = duration_host.room.session.duplicate(true)
	corrupt_duration.models[0].ability_grants.fall_back_and_shoot.durations = ["FOREVER_UNKNOWN"]
	check(not BattleSession.validate_snapshot(corrupt_duration).is_empty(), "invalid serialized grant duration is rejected")
	bad_grant_entry.payload.unit_id = "missing"
	var bad_grant := Replay.apply_entry(grant_room.session, bad_grant_entry)
	check(not bad_grant.ok and bad_grant.state == grant_room.session, "invalid grant target is atomic and spends no points")
	var wrong_phase_grant: Dictionary = grant_room.session.duplicate(true)
	wrong_phase_grant.phase = "FIGHT"
	check(not Replay.apply_entry(wrong_phase_grant, grant_entry).ok, "grant enforces declared phase")
	var reserve_grant: Dictionary = grant_room.session.duplicate(true)
	reserve_grant.models[0].reserve_status = "reserve"
	check(not Replay.apply_entry(reserve_grant, grant_entry).ok, "grant rejects inactive reserve recipient")
	var unsupported_grant: Dictionary = grant.duplicate(true)
	unsupported_grant.effect = "NO_IMPLEMENTATION"
	check(Stratagems.validate(unsupported_grant) == "UNSUPPORTED EFFECT", "unknown effects cannot silently consume points")
	unsupported_grant = grant.duplicate(true)
	unsupported_grant.timing = "AFTER_ROLL"
	check(Stratagems.validate(unsupported_grant) == "INVALID ABILITY TIMING", "grant rejects unsupported timing window")
	unsupported_grant = grant.duplicate(true)
	unsupported_grant.ability = "invented_ability"
	check(Stratagems.validate(unsupported_grant) == "UNKNOWN GRANTED ABILITY", "grant validates executable ability identifier")
	var objective_grant: Dictionary = grant.duplicate(true)
	objective_grant.ability = "objective_control_plus_1"
	check(Stratagems.validate(objective_grant).is_empty(), "strategy can declare an executable objective control grant")
	var objective_grant_state: Dictionary = grant_room.session.duplicate(true)
	objective_grant_state.models[0].faction_stratagems = [objective_grant]
	var objective_granted := Replay.apply_entry(objective_grant_state, grant_entry)
	check(objective_granted.ok and objective_granted.state.models[0].ability_ids.has("objective_control_plus_1") and UnitAbilities.modifiers(objective_granted.state.models[0].ability_ids).objective_control_bonus == 1, "objective control strategy grant changes the shared rules consumer")
	check(UnitAbilities.modifiers(["invulnerable_4", "invulnerable_5"]).invulnerable_save == 4, "stacked defensive passives choose best save instead of adding thresholds")
	check(UnitAbilities.modifiers(["feel_no_pain_6", "feel_no_pain_5"]).feel_no_pain == 5, "stacked damage prevention chooses best threshold")
	var detachment_profile := {"abilities": ["stealth"], "faction_abilities": ["reroll_hit"], "detachment_abilities": ["fall_back_and_shoot"]}
	check(FactionRules.validate(detachment_profile).is_empty() and UnitAbilities.modifiers(FactionRules.abilities(detachment_profile)).fall_back_and_shoot, "detachment abilities join shared profile execution contract")
	detachment_profile.detachment_abilities = "bad"
	check(FactionRules.validate(detachment_profile).has("INVALID DETACHMENT_ABILITIES"), "invalid detachment container is rejected")
	var accepted_snapshot := NetworkSync.accept_snapshot(room.session, synced.snapshot)
	check(accepted_snapshot.ok and accepted_snapshot.state.phase == "SHOOTING", "client sync accepts an authoritative snapshot")
	var stale_packet := command_packet.duplicate(true)
	stale_packet.snapshot_hash = "stale"
	check(not NetworkSync.host_command(room, stale_packet, "player_gold").ok, "host sync rejects a stale peer snapshot")
	var attack_models: Array = [
		# Network fixtures below remain independent of official faction data.
		{"model_id": "net_attacker", "unit_id": "net_unit_a", "team": 0, "position": Vector2(5, 5), "radius": 0.5, "spent": 0.0, "wounds": 3, "toughness": 4, "save_on": 4, "weapons": [{"name": "net gun", "range_inches": 24.0, "attacks": 1, "hit_on": 4, "strength": 4, "damage": 1}]},
		{"model_id": "net_target", "unit_id": "net_unit_b", "team": 1, "position": Vector2(10, 5), "radius": 0.5, "spent": 0.0, "wounds": 3, "toughness": 4, "save_on": 7, "weapons": []}
	]
	var attack_room: Dictionary = Room.create("attack-room")
	attack_room.players = [{"id": "attacker", "team": 0, "ready": true, "connected": true}, {"id": "target", "team": 1, "ready": true, "connected": true}]
	attack_room.status = Room.ACTIVE
	attack_room.session = BattleSession.create(attack_models, 11, 0)
	attack_room.session.phase = "SHOOTING"
	attack_room.session.phase_index = TurnState.phase_index("SHOOTING")
	var intent_packet := PeerProtocol.command("attack-room", "attacker", PeerProtocol.hash_snapshot({"room_id": "attack-room", "edition": 11, "mission": "control_center"}), 0, -1, {"sequence": 0, "team": 0, "kind": "SHOOT", "payload": {"attacker": 0, "attacker_id": "net_attacker", "target": 1, "target_id": "net_target", "weapon": "net gun", "intent": true, "damage": 999, "hazardous_damage": 999, "feel_no_pain_rolls": [6]}}, PeerProtocol.hash_snapshot(attack_room.session))
	var intent_result := NetworkSync.host_command(attack_room, intent_packet, "attacker")
	var forged_result_packet: Dictionary = intent_packet.duplicate(true)
	forged_result_packet.command.payload.intent = false
	forged_result_packet.command.payload.hits = 999
	var forged_result := NetworkSync.host_command(attack_room, forged_result_packet, "attacker")
	check(not forged_result.ok and forged_result.reason == "HOST RESOLUTION REQUIRED" and forged_result.room == attack_room, "remote materialized damage packet cannot bypass host resolution")
	var forged_team_packet: Dictionary = intent_packet.duplicate(true)
	forged_team_packet.command.team = 1
	check(NetworkSync.host_command(attack_room, forged_team_packet, "attacker").reason == "PLAYER TEAM MISMATCH", "attack modifier team comes from authenticated room identity")
	check(intent_result.ok and intent_result.entry.payload.damage >= 0 and int(intent_result.entry.payload.damage) != 999 and int(intent_result.entry.payload.hazardous_damage) != 999 and intent_result.entry.payload.has("hazardous_damage") and not bool(intent_result.entry.payload.get("intent", false)), "host materializes network attack intent with recorded outcomes")
	var shock_room := Room.create("shock-room")
	var aura_rule := {"id": "fixture_guidance", "aura": {"radius_inches": 6.0, "event": "before_attack", "include_self": false, "keywords": ["INFANTRY"], "modifiers": {"hit_rerolls": 1}}}
	var aura_source := {"model_id": "aura_source", "team": 0, "wounds": 3, "radius": 0.5, "position": Vector2(1, 1), "ability_ids": [aura_rule]}
	var aura_recipient := {"model_id": "aura_recipient", "team": 0, "wounds": 3, "radius": 0.5, "position": Vector2(8, 1), "keywords": ["INFANTRY"]}
	check(UnitAbilities.validate([aura_rule]).is_empty(), "aura schema accepts supported attack modifier")
	check(FactionRules.combat_modifiers([aura_source], aura_recipient, "before_attack").hit_rerolls == 1, "aura reaches exact base-edge boundary")
	check(FactionRules.combat_modifiers([aura_source, aura_source.duplicate(true)], aura_recipient, "before_attack").hit_rerolls == 1, "same aura id does not stack across sources")
	check(FactionRules.combat_modifiers([aura_source], aura_source, "before_attack").hit_rerolls == 0, "aura excludes source when requested")
	aura_recipient.position.x += 0.01
	check(FactionRules.combat_modifiers([aura_source], aura_recipient, "before_attack").hit_rerolls == 0, "leaving aura range removes bonus immediately")
	aura_recipient.position = [8.0, 1.0]
	check(FactionRules.combat_modifiers([aura_source], aura_recipient, "before_attack").hit_rerolls == 1, "aura supports serialized snapshot coordinates")
	aura_source.reserve_status = "reserve"
	check(FactionRules.combat_modifiers([aura_source], aura_recipient, "before_attack").hit_rerolls == 0, "reserve source emits no aura")
	aura_source.reserve_status = "deployed"
	aura_source.embarked_in = "transport"
	check(FactionRules.combat_modifiers([aura_source], aura_recipient, "before_attack").hit_rerolls == 0, "embarked source emits no aura")
	aura_source.embarked_in = ""
	aura_source.wounds = 0
	check(FactionRules.combat_modifiers([aura_source], aura_recipient, "before_attack").hit_rerolls == 0, "destroyed source emits no aura")
	aura_source.wounds = 3
	aura_recipient.team = 1
	check(FactionRules.combat_modifiers([aura_source], aura_recipient, "before_attack").hit_rerolls == 0, "friendly aura cannot benefit enemy")
	aura_recipient.team = 0
	aura_recipient.keywords = []
	check(FactionRules.combat_modifiers([aura_source], aura_recipient, "before_attack").hit_rerolls == 0, "aura enforces recipient keywords")
	var invalid_aura: Dictionary = aura_rule.duplicate(true)
	invalid_aura.aura.radius_inches = -1
	check(not UnitAbilities.validate([invalid_aura]).is_empty(), "negative aura radius rejected")
	invalid_aura = aura_rule.duplicate(true)
	invalid_aura.aura.modifiers = {"damage": 999}
	check(not UnitAbilities.validate([invalid_aura]).is_empty(), "unsupported aura output rejected")
	var aura_room: Dictionary = attack_room.duplicate(true)
	aura_source.position = Vector2(5, 7)
	aura_source.unit_id = "aura_unit"
	aura_room.session.models.append(aura_source)
	aura_room.session.models[0].keywords = ["INFANTRY"]
	aura_room.session.models[0].weapons[0].attacks = 12
	var aura_packet: Dictionary = intent_packet.duplicate(true)
	aura_packet.snapshot_hash = PeerProtocol.hash_snapshot(aura_room.session)
	var aura_host := NetworkSync.host_command(aura_room, aura_packet, "attacker", seeded_rng("network-test:0".hash()))
	var aura_rng := RandomNumberGenerator.new()
	aura_rng.seed = "network-test:0".hash()
	var aura_expected := Combat.resolve_ranged_attack(aura_room.session.models[0].weapons[0], aura_room.session.models[1], aura_rng, 1)
	check(aura_host.ok and aura_host.entry.payload.hits == aura_expected.hits and aura_host.entry.payload.damage == aura_expected.damage, "host materializes attack with current aura using authoritative dice")
	var aura_replay := Replay.apply_entry(aura_room.session, aura_host.entry)
	check(aura_replay.ok and aura_replay.state.models == aura_host.room.session.models, "aura attack replays authoritative result identically")
	var defend_rule := {"id": "fixture_cover", "aura": {"radius_inches": 6, "event": "before_defend", "modifiers": {"cover_bonus": 1}}}
	var defend_source: Dictionary = aura_source.duplicate(true)
	defend_source.ability_ids = [defend_rule]
	check(FactionRules.combat_modifiers([defend_source], defend_source, "before_defend").cover_bonus == 1, "defensive aura includes its source by default")
	check(FactionRules.combat_modifiers([defend_source], defend_source, "before_attack").cover_bonus == 0, "defensive aura cannot leak into attack event")
	var inactive_recipient: Dictionary = defend_source.duplicate(true)
	inactive_recipient.embarked_in = "transport"
	check(FactionRules.combat_modifiers([defend_source], inactive_recipient, "before_defend").cover_bonus == 0, "embarked recipient receives no aura")
	check(FactionRules.combat_modifiers([], defend_source, "before_defend").cover_bonus == 0, "removed aura source leaves no cached modifier")
	invalid_aura = aura_rule.duplicate(true)
	invalid_aura.aura.keywords = [5]
	check(not UnitAbilities.validate([invalid_aura]).is_empty(), "malformed aura keyword rejected")
	var defense_weapon := {"attacks": 80, "hit_on": 2, "strength": 8, "damage": 1}
	var defense_target := {"toughness": 4, "save_on": 5, "ability_ids": []}
	var plain_defense := Combat.resolve_ranged_attack(defense_weapon, defense_target, seeded_rng(87))
	var attacking_save := Combat.resolve_ranged_attack(defense_weapon, defense_target, seeded_rng(87), 0, {"save_rerolls": 100})
	check(attacking_save == plain_defense, "attacker save rerolls cannot improve defender saves")
	var defending_save := Combat.resolve_ranged_attack(defense_weapon, defense_target, seeded_rng(87), 0, {}, {"save_rerolls": 100})
	check(defending_save.damage < plain_defense.damage, "defender save rerolls reduce actual resolved damage")
	defense_target.ability_ids = [{"id": "fixture_defense", "modifiers": {"save_rerolls": 100}}]
	check(Combat.resolve_ranged_attack(defense_weapon, defense_target, seeded_rng(87)) == defending_save, "native defender passive uses same save resolver")
	defense_target.ability_ids = []
	defense_target.invulnerable_save = 3
	var threshold_defense := Combat.resolve_ranged_attack(defense_weapon, defense_target, seeded_rng(87), 0, {}, {"invulnerable_save": 5})
	check(threshold_defense.save_on == 3, "weaker defensive aura preserves native invulnerable save")
	threshold_defense = Combat.resolve_ranged_attack(defense_weapon, defense_target, seeded_rng(87), 0, {}, {"invulnerable_save": 2})
	check(threshold_defense.save_on == 2, "stronger defensive aura improves invulnerable save")
	var save_aura := {"id": "fixture_save_aura", "aura": {"radius_inches": 6, "event": "before_defend", "modifiers": {"save_rerolls": 20, "invulnerable_save": 4}}}
	check(UnitAbilities.validate([save_aura]).is_empty(), "defensive aura accepts implemented save modifiers")
	var invalid_save_aura: Dictionary = save_aura.duplicate(true)
	invalid_save_aura.aura.modifiers.invulnerable_save = 1
	check(not UnitAbilities.validate([invalid_save_aura]).is_empty(), "defensive aura rejects invalid invulnerable threshold")
	invalid_save_aura = save_aura.duplicate(true)
	invalid_save_aura.aura.event = "before_attack"
	check(not UnitAbilities.validate([invalid_save_aura]).is_empty(), "save aura cannot be declared as attack modifier")
	var save_room: Dictionary = attack_room.duplicate(true)
	save_room.session.models[1].ability_ids = [save_aura]
	save_room.session.models[1].wounds = 100
	save_room.session.models[0].weapons[0].attacks = 30
	var save_packet: Dictionary = intent_packet.duplicate(true)
	save_packet.snapshot_hash = PeerProtocol.hash_snapshot(save_room.session)
	var save_host := NetworkSync.host_command(save_room, save_packet, "attacker", seeded_rng(87))
	var save_expected := Combat.resolve_ranged_attack(save_room.session.models[0].weapons[0], save_room.session.models[1], seeded_rng(87), 0, {}, FactionRules.combat_modifiers(save_room.session.models, save_room.session.models[1], "before_defend"))
	check(save_host.ok and save_host.entry.payload.damage == save_expected.damage, "authoritative shooting applies current defensive aura")
	check(Replay.apply_entry(save_room.session, save_host.entry).state.models == save_host.room.session.models, "defensive aura attack result replays identically")
	var save_melee := Melee.resolve_attack(defense_weapon, defense_target, seeded_rng(87), 0, [], {}, {"save_rerolls": 100, "invulnerable_save": 2})
	check(save_melee == Combat.resolve_ranged_attack(defense_weapon, defense_target, seeded_rng(87), 0, {}, {"save_rerolls": 100, "invulnerable_save": 2}), "melee shares defensive save resolution")
	var conditional_aura: Dictionary = save_aura.duplicate(true)
	conditional_aura.aura.when = {"phase": "SHOOTING", "kind": "SHOOT"}
	var conditional_source: Dictionary = save_room.session.models[1].duplicate(true)
	conditional_source.ability_ids = [conditional_aura]
	check(UnitAbilities.validate([conditional_aura]).is_empty(), "aura accepts phase and attack kind conditions")
	check(FactionRules.combat_modifiers([conditional_source], conditional_source, "before_defend", {"phase": "SHOOTING", "kind": "SHOOT"}).invulnerable_save == 4, "conditional aura applies on matching phase and attack kind")
	check(FactionRules.combat_modifiers([conditional_source], conditional_source, "before_defend", {"phase": "MOVEMENT", "kind": "SHOOT"}).invulnerable_save == 0, "conditional aura does not treat reaction as shooting phase")
	check(FactionRules.combat_modifiers([conditional_source], conditional_source, "before_defend", {"phase": "SHOOTING", "kind": "FIGHT"}).invulnerable_save == 0, "conditional aura excludes other attack kinds")
	check(FactionRules.combat_modifiers([conditional_source], conditional_source, "before_defend").invulnerable_save == 0, "missing context cannot activate conditional aura")
	conditional_aura.aura.when = {"unsupported": true}
	check(not UnitAbilities.validate([conditional_aura]).is_empty(), "unknown aura condition rejected instead of silently ignored")
	conditional_aura.aura.when = "SHOOTING"
	check(not UnitAbilities.validate([conditional_aura]).is_empty(), "malformed aura conditions are rejected")
	var cover_rng := RandomNumberGenerator.new()
	cover_rng.seed = 87
	var cover_weapon := {"attacks": 200, "hit_on": 2, "strength": 8, "damage": 1}
	var uncovered := Combat.resolve_ranged_attack(cover_weapon, {"toughness": 4, "save_on": 4}, cover_rng)
	cover_rng.seed = 87
	var covered := Combat.resolve_ranged_attack(cover_weapon, {"toughness": 4, "save_on": 4, "cover_save_bonus": 1}, cover_rng)
	check(covered.failed_saves < uncovered.failed_saves, "positive cover benefit improves rather than worsens armor saves")
	shock_room = Room.join(shock_room, "shock_gold", 0).room
	shock_room = Room.join(shock_room, "shock_blue", 1).room
	shock_room = Room.set_ready(shock_room, "shock_gold").room
	shock_room = Room.set_ready(shock_room, "shock_blue").room
	var shock_started := Room.start(shock_room, [{"model_id": "shock_m001", "unit_id": "shock_unit", "team": 0, "position": Vector2(10, 10), "leadership": 7}, {"model_id": "shock_enemy_m001", "unit_id": "shock_enemy", "team": 1, "position": Vector2(30, 30)}])
	shock_room = shock_started.room
	var shock_session_id := PeerProtocol.hash_snapshot({"room_id": shock_room.id, "edition": int(shock_room.edition), "mission": shock_room.mission_id})
	var shock_packet := PeerProtocol.command(shock_room.id, "shock_gold", shock_session_id, 0, -1, {"sequence": 0, "team": 0, "kind": "BATTLE_SHOCK", "payload": {"unit_id": "shock_unit", "intent": true}}, PeerProtocol.hash_snapshot(shock_room.session))
	var network_shock_result := NetworkSync.host_command(shock_room, shock_packet, "shock_gold")
	var forged_shock: Dictionary = shock_packet.duplicate(true)
	forged_shock.command.payload = {"unit_id": "shock_unit", "passed": true, "rolls": [1, 1], "total": 2}
	check(not NetworkSync.host_command(shock_room, forged_shock, "shock_gold").ok, "client cannot submit precomputed battle shock result")
	check(network_shock_result.ok and not bool(network_shock_result.entry.payload.get("intent", false)) and network_shock_result.entry.payload.get("rolls", []).size() == 2, "host materializes network battle shock with recorded outcomes")
	var lobby_probe = P2PLobby.new()
	root.add_child(lobby_probe)
	await process_frame
	lobby_probe.room = room
	lobby_probe.player_id = "player_gold"
	var probe_error: String = lobby_probe.submit_command("PHASE_ADVANCE", {"from": "MOVEMENT", "to": "SHOOTING"})
	check(probe_error == "TRANSPORT NOT CONNECTED", "client lobby validates mapped team then rejects disconnected transport without RPC")
	lobby_probe.queue_free()
	var identity := AccountIdentity.create("Player@Example.com", "correct horse battery staple", "Player")
	var challenge := AccountIdentity.challenge(identity, "nonce-001")
	check(AccountIdentity.validate(identity).is_empty() and AccountIdentity.verify(identity, challenge, "nonce-001"), "account challenge proof validates")
	check(not AccountIdentity.verify(identity, challenge, "nonce-002") and AccountIdentity.session_token(identity, "").is_empty(), "account proof rejects a changed nonce")
	var auth_packet := PeerProtocol.auth("player_gold", peer_session_id, challenge)
	check(PeerProtocol.validate(auth_packet).is_empty() and P2PTransport != null and P2PLobby != null and LobbyScreen != null, "P2P transport accepts authenticated envelopes")
	var identity_path := "user://open_battle_identity_test.json"
	AccountStore.remove_identity(identity_path)
	check(AccountStore.save_identity(identity, identity_path).is_empty() and AccountStore.load_identity(identity_path).fingerprint == identity.fingerprint, "account identity persists without plaintext password")
	var advertisement := RoomDirectory.advertise("public-room", identity, "203.0.113.20", 24567, 11, "control_center", 4102444800)
	var invite := RoomDirectory.encode(advertisement, 4102444700)
	var decoded_advertisement := RoomDirectory.decode(invite, 4102444700)
	check(not invite.is_empty() and decoded_advertisement.get("room_id", "") == "public-room" and decoded_advertisement.host.get("fingerprint", "") == identity.fingerprint and not decoded_advertisement.host.has("credential_hash"), "room advertisement invite round trips without credentials")
	check(RoomDirectory.validate(advertisement, 4102444801) == "ROOM ADVERTISEMENT EXPIRED", "expired room advertisement is rejected")
	var invalid_advertisement := advertisement.duplicate(true)
	invalid_advertisement.host.fingerprint = "not-a-fingerprint"
	check(RoomDirectory.encode(invalid_advertisement).is_empty(), "room advertisement rejects malformed host fingerprint")
	lobby_probe.identity = identity
	lobby_probe.is_host = true
	lobby_probe.server_port = 24567
	check(RoomDirectory.decode(lobby_probe.room_invite("203.0.113.20", 4102444800), 4102444700).get("room_id", "") == str(room.id), "lobby exposes an expiring public room invite")
	check(lobby_probe.connect_invite("not-an-invite", 4102444700) == "INVALID ROOM INVITE", "lobby validates an invite before connecting")
	check(lobby_probe.connect_invite(invite, 4102444801) == "INVALID ROOM INVITE", "lobby rejects an expired invite before connecting")
	check(lobby_probe.list_public_rooms("directory.invalid") == "INVALID DIRECTORY URL" and lobby_probe.publish_public_room("directory.invalid", "203.0.113.20", 4102444800) == "INVALID DIRECTORY URL", "lobby validates optional directory endpoints")
	AccountStore.remove_identity(identity_path)
	var trust_path := "user://open_battle_trusted_test.json"
	AccountStore.remove_trusted_identities(trust_path)
	check(AccountStore.save_trusted_identity(identity, trust_path).is_empty() and AccountStore.load_trusted_identities(trust_path).size() == 1 and AccountStore.load_trusted_identities(trust_path)[0].fingerprint == identity.fingerprint, "trusted peer identity persists for P2P pairing")
	AccountStore.remove_trusted_identities(trust_path)
	var abandoned_room := Room.leave(room, "player_gold")
	check(abandoned_room.ok and abandoned_room.room.status == Room.ABANDONED, "room marks active player leave")
	var ai_models: Array = [
		{"model_id": "ai_gold", "unit_id": "ai_gold_unit", "team": 0, "position": Vector2(10, 10), "radius": 0.5, "movement_inches": 6.0, "spent": 0.0, "wounds": 3, "toughness": 4, "save_on": 4, "leadership": 7, "objective_control": 1, "weapons": [{"name": "ai cannon", "range_inches": 24.0, "attacks": 6, "hit_on": 2, "strength": 8, "damage": 3}]},
		{"model_id": "ai_blue", "unit_id": "ai_blue_unit", "team": 1, "position": Vector2(20, 10), "radius": 0.5, "movement_inches": 6.0, "spent": 0.0, "wounds": 4, "toughness": 4, "save_on": 7, "leadership": 7, "objective_control": 1, "weapons": [{"name": "blue blade", "range_inches": 0.0, "attacks": 1, "hit_on": 4, "strength": 3, "damage": 1}]}
	]
	var ai_session := BattleSession.create(ai_models, 11, 0)
	var ai_turn := AIPlayer.play_turn(ai_session, 0, 2026, 32)
	check(ai_turn.ok and ai_turn.state.active_team == 1 and ai_turn.commands.size() > 5, "single-player AI completes a deterministic turn")
	var invalid_model := {"model_id": "bad_m001", "unit_id": "bad", "team": 0, "position": Vector2(INF, 2)}
	check(ModelState.validate_models([invalid_model]).has("INVALID MODEL POSITION bad_m001"), "model state rejects non-finite position")
	check(ModelState.validate_models([{ "model_id": "advance_m001", "unit_id": "advance", "team": 0, "position": Vector2.ZERO, "advance_bonus": 4 }]).is_empty(), "model state accepts advance metadata")
	check(ModelState.validate_models([{ "model_id": "fall_m001", "unit_id": "fall", "team": 0, "position": Vector2.ZERO, "fell_back": true }]).is_empty(), "model state accepts fall back metadata")
	check(Deployment.zone_reason(Vector2(10, 6), 1.0, 0, Rules.BOARD_SIZE, 12.0).is_empty(), "gold deployment zone accepts legal base")
	check(Deployment.zone_reason(Vector2(10, 20), 1.0, 0, Rules.BOARD_SIZE, 12.0) == "OUTSIDE DEPLOYMENT ZONE", "gold deployment zone rejects midfield base")
	check(Deployment.zone_reason(Vector2(10, 38), 1.0, 1, Rules.BOARD_SIZE, 12.0).is_empty(), "blue deployment zone accepts legal base")
	var coherent_unit: Array = [
		{"position": Vector2(10, 10)},
		{"position": Vector2(11.5, 10)},
		{"position": Vector2(11.5, 11.5)}
	]
	check(UnitValidation.coherency_reason(coherent_unit).is_empty(), "coherent unit passes")
	var incoherent_unit := coherent_unit.duplicate(true)
	incoherent_unit[2].position = Vector2(20, 20)
	check(UnitValidation.coherency_reason(incoherent_unit) == "MODEL OUT OF COHERENCY", "coherency failure is reported")
	var grouped_models: Array = [
		{"unit_id": "alpha", "position": Vector2.ZERO},
		{"unit_id": "alpha", "position": Vector2(1, 0)},
		{"unit_id": "beta", "position": Vector2(20, 20)}
	]
	check(UnitValidation.group_by_unit(grouped_models).size() == 2, "models group by unit id")
	var dice_rng := RandomNumberGenerator.new()
	dice_rng.seed = 77
	var dice_result := Dice.roll_d6(dice_rng, 3, 1)
	check(dice_result.rolls.size() == 3 and dice_result.total == dice_result.rolls[0] + dice_result.rolls[1] + dice_result.rolls[2] + 1, "dice rolls are deterministic and totaled")
	var expression := Dice.roll_expression(dice_rng, "D6+2")
	check(expression.valid and expression.rolls.size() == 1 and expression.total >= 3 and expression.total <= 8, "dice expressions resolve")
	check(Dice.parse_expression(2.0).valid and Dice.parse_expression(2.0).modifier == 2, "numeric JSON dice values resolve")
	check(not Dice.parse_expression("D3+bad").valid, "invalid dice expression is rejected")
	var variable_attack := Combat.resolve_ranged_attack({"attacks": "D3", "hit_on": 7, "strength": 4, "damage": "D6"}, {"toughness": 4, "save_on": 7}, dice_rng)
	check(variable_attack.attacks >= 1 and variable_attack.attacks <= 3 and variable_attack.attack_roll.valid, "combat accepts variable attack dice")
	check(Dice.succeeds(4, 4) and not Dice.succeeds(3, 4), "target threshold resolves")
	check(UnitAbilities.validate(["stealth", "reroll_hit_ones"]).is_empty(), "known abilities validate")
	check(UnitAbilities.canonical_id("隐匿") == "stealth" and UnitAbilities.canonical_id("深入打击") == "deep_strike", "localized ability aliases normalize")
	check(UnitAbilities.validate(["隐匿", "斥候6英寸"]).is_empty(), "localized ability aliases validate")
	var movement_exception_mods := UnitAbilities.modifiers(["撤退后可射击", "撤退后可冲锋", "前进后可射击"])
	check(movement_exception_mods.fall_back_and_shoot and movement_exception_mods.fall_back_and_charge and movement_exception_mods.shoot_after_advance, "movement exception abilities expose executable modifiers")
	var fallback_shooter := {"team": 0, "fell_back": true, "ability_ids": ["fall_back_and_shoot"]}
	var fallback_target := {"team": 1}
	check(Combat.target_reason(fallback_shooter, fallback_target, 10.0, {"range_inches": 24.0, "abilities": []}, 0).is_empty(), "fall back and shoot ability bypasses the normal shooting lock")
	var ability_mods := UnitAbilities.modifiers(["stealth", "objective_control_plus_1", "reroll_hit_ones"])
	check(ability_mods.cover_bonus == 1 and ability_mods.objective_control_bonus == 1 and ability_mods.hit_rerolls == 0 and ability_mods.hit_reroll_ones == 1, "ability modifiers aggregate")
	var stealth_target_abilities := UnitAbilities.modifiers(["stealth"])
	var stealth_context := WeaponRules.context({"range_inches": 24.0, "attacks": 1, "hit_on": 4}, 10.0, int(stealth_target_abilities.cover_bonus), 1)
	check(stealth_context.cover_bonus == 1, "target stealth contributes to shared cover context")
	var reroll_mods := UnitAbilities.modifiers(["reroll_wound_ones", "reroll_save_ones"])
	check(reroll_mods.wound_reroll_ones == 1 and reroll_mods.save_reroll_ones == 1 and UnitAbilities.modifiers(["reroll_hit"]).hit_rerolls == 1, "ability reroll ones and full reroll modifiers are executable")
	var faction_profile: Dictionary = {"abilities": []}
	faction_profile.faction_abilities = ["stealth"]
	faction_profile.faction_stratagems = ["command_reroll"]
	check(FactionRules.validate(faction_profile).is_empty() and FactionRules.abilities(faction_profile).has("stealth") and FactionRules.stratagems(faction_profile).size() == 1, "faction abilities and stratagems load through one profile contract")
	var inline_ability := {"id": "local_faction_rule", "modifiers": {"cover_bonus": 2}, "events": {"before_attack": {"when": {"phase": "SHOOTING"}, "modifiers": {"hit_rerolls": 1}, "effects": ["MARKED_TARGET"]}}}
	check(UnitAbilities.validate([inline_ability]).is_empty(), "inline faction ability schema validates")
	var inline_event := UnitAbilities.event_modifiers([inline_ability], "before_attack", {"phase": "SHOOTING"})
	check(inline_event.cover_bonus == 2 and inline_event.hit_rerolls == 1 and UnitAbilities.event_effects([inline_ability], "before_attack", {"phase": "SHOOTING"}).has("MARKED_TARGET"), "inline faction ability event resolves")
	var reduced_damage := Damage.apply_to_model({"wounds": 5, "damage_reduction": 1}, 3)
	check(reduced_damage.damage == 2 and reduced_damage.wounds_after == 3, "ability damage reduction modifies applied damage")
	var fnp_damage := Damage.apply_to_model({"wounds": 5, "feel_no_pain": 5}, 3, [5, 2, 6])
	check(fnp_damage.damage == 1 and fnp_damage.feel_no_pain_ignored == 2, "feel no pain reduces applied damage from verified rolls")
	var fnp_rng := RandomNumberGenerator.new()
	fnp_rng.seed = 18
	var fnp_unit: Array = [{"wounds": 5, "feel_no_pain": 5}]
	var fnp_allocation := Damage.allocate_to_unit(fnp_unit, 2, 0, fnp_rng)
	check(fnp_allocation.feel_no_pain_rolls.size() == 2 and fnp_unit[0].wounds <= 5, "scene damage allocation rolls feel no pain")
	check(UnitAbilities.validate(["not_real"]).size() == 1, "unknown ability is reported")
	check(UnitKeywords.canonical_id("飞行") == "fly" and UnitKeywords.canonical_id("史诗英雄") == "epic_hero", "localized unit keywords normalize")
	check(UnitKeywords.validate(["步兵", "fly"]).is_empty(), "known unit keywords validate")
	var weapon_context := WeaponRules.context({"range_inches": 12.0, "attacks": 2, "hit_on": 4, "abilities": ["喷射", "忽略掩体"]}, 6.0, 1)
	check(weapon_context.weapon.hit_on == 1 and weapon_context.cover_bonus == 0, "weapon keywords modify hit and cover")
	var rapid_context := WeaponRules.context({"range_inches": 24.0, "attacks": 2, "hit_on": 3, "abilities": ["速射"]}, 12.0)
	check(rapid_context.weapon.attacks == 4, "rapid fire doubles attacks at half range")
	var rapid_numeric := WeaponRules.context({"range_inches": 24.0, "attacks": 2, "abilities": ["速射1"]}, 12.0)
	check(rapid_numeric.weapon.attacks == 3 and rapid_numeric.keywords.has("rapid_fire_1"), "numeric rapid fire adds attacks at half range")
	var rapid_dice := WeaponRules.context({"range_inches": 24.0, "attacks": "D6", "abilities": ["rapid fire 2"]}, 12.0)
	check(rapid_dice.weapon.attacks == "D6+2", "numeric rapid fire modifies dice attack expression")
	var rapid_variable := WeaponRules.context({"range_inches": 24.0, "attacks": 3, "abilities": ["速射D3"]}, 12.0)
	check(rapid_variable.weapon.attacks == "D3+3" and rapid_variable.keywords.has("rapid_fire_d3"), "variable rapid fire adds a dice expression")
	var melta_close := WeaponRules.context({"range_inches": 12.0, "damage": "D6", "abilities": ["热熔2"]}, 6.0)
	var melta_far := WeaponRules.context({"range_inches": 12.0, "damage": "D6", "abilities": ["热熔2"]}, 7.0)
	check(melta_close.weapon.damage == "D6+2" and melta_close.keywords.has("melta_2") and melta_far.weapon.damage == "D6", "melta adds damage only at half range")
	var hazardous_context := WeaponRules.context({"range_inches": 12.0, "attacks": 1, "hit_on": 4, "damage": 2, "abilities": ["危险"]}, 8.0)
	check(hazardous_context.weapon.hazardous and hazardous_context.weapon.hazardous_damage == 3, "hazardous weapon context is explicit")
	var hazardous_rng := RandomNumberGenerator.new()
	hazardous_rng.seed = 9
	var hazardous_attack := Combat.resolve_ranged_attack({"attacks": 1, "hit_on": 4, "strength": 4, "damage": 1, "hazardous": true}, {"toughness": 4, "save_on": 7}, hazardous_rng, 1)
	check(hazardous_attack.hazardous_failures == 1 and hazardous_attack.hits == 1, "hazardous checks unmodified hit after reroll")
	var blast_context := WeaponRules.context({"range_inches": 24.0, "attacks": 3, "hit_on": 4, "abilities": ["爆炸"]}, 10.0, 0, 10)
	check(blast_context.weapon.attacks == 5, "blast adds attacks for large units")
	var devastating_context := WeaponRules.context({"range_inches": 24.0, "attacks": 1, "hit_on": 4, "abilities": ["毁灭伤害"]}, 10.0)
	check(devastating_context.weapon.devastating_wounds, "devastating wounds context is explicit")
	check(WeaponRules.canonical_id("针对步兵 4+") == "anti_infantry_4" and WeaponRules.canonical_id("双联") == "twin_linked" and WeaponRules.canonical_id("手枪") == "pistol", "anti, twin-linked and pistol keywords normalize")
	check(WeaponRules.canonical_id("反步兵4+") == "anti_infantry_4", "anti keyword accepts reverse Chinese alias")
	check(WeaponRules.canonical_id("熱熔2") == "melta_2" and WeaponRules.canonical_id("連擊1") == "rapid_fire_1" and WeaponRules.canonical_id("連擊D3") == "rapid_fire_d3" and WeaponRules.canonical_id("無視掩體") == "ignores_cover", "weapon aliases normalize traditional Chinese")
	var anti_context := WeaponRules.context({"range_inches": 24.0, "attacks": 1, "hit_on": 4, "abilities": ["针对步兵4+", "致命一击", "双联", "持续命中1"]}, 10.0, 0, 1, ["步兵"])
	check(anti_context.weapon.anti_wound_on == 4 and anti_context.weapon.lethal_hits and anti_context.weapon.twin_linked and anti_context.weapon.sustained_hits == 1, "anti, lethal, twin-linked and sustained hits apply to matching target")
	var anti_miss := WeaponRules.context({"range_inches": 24.0, "attacks": 1, "hit_on": 4, "abilities": ["针对步兵4+"]}, 10.0, 0, 1, ["载具"])
	check(not anti_miss.weapon.has("anti_wound_on"), "anti keyword does not affect a non-matching target")
	var anti_attack := Combat.resolve_ranged_attack({"attacks": 0, "hit_on": 4, "strength": 10, "anti_wound_on": 4, "damage": 1}, {"toughness": 4, "save_on": 7}, dice_rng)
	check(anti_attack.wound_on == 4, "anti wound threshold is used by combat resolver")
	var heavy_stationary := WeaponRules.context({"range_inches": 24.0, "attacks": 1, "hit_on": 4, "abilities": ["重型"]}, 10.0, 0, 1, [], true)
	var heavy_moved := WeaponRules.context({"range_inches": 24.0, "attacks": 1, "hit_on": 4, "abilities": ["重型"]}, 10.0, 0, 1, [], false)
	check(heavy_stationary.weapon.hit_on == 3 and heavy_moved.weapon.hit_on == 4, "heavy improves stationary hit and loses the bonus after movement")
	var precision_context := WeaponRules.context({"range_inches": 24.0, "attacks": 1, "hit_on": 4, "abilities": ["精准"]}, 10.0)
	check(precision_context.weapon.precision and precision_context.keywords.has("precision"), "precision weapon context is executable")
	var lance_context := WeaponRules.context({"range_inches": 0.0, "attacks": 1, "hit_on": 4, "strength": 4, "damage": 1, "abilities": ["长枪"]}, INF)
	lance_context.weapon.wound_bonus = 1
	var lance_attack := Combat.resolve_ranged_attack(lance_context.weapon, {"toughness": 5, "save_on": 7}, dice_rng)
	check(lance_context.weapon.lance and lance_attack.wound_on == 4, "lance improves melee wound threshold after a charge")
	var indirect_context := WeaponRules.context({"range_inches": 60.0, "attacks": 1, "hit_on": 4, "abilities": ["曲射"]}, 30.0, 0, 1, [], true, false)
	check(indirect_context.weapon.indirect and indirect_context.weapon.hit_on == 5 and indirect_context.cover_bonus == 1, "indirect fire allows blocked targets with hit and cover modifiers")
	var one_shot_context := WeaponRules.context({"range_inches": 24.0, "attacks": 1, "hit_on": 4, "abilities": ["一次性"]}, 10.0)
	check(one_shot_context.weapon.one_shot, "one-shot weapon context is explicit")
	var compound_context := WeaponRules.context({"range_inches": 24.0, "attacks": 1, "hit_on": 4, "abilities": ["曲射，双联"]}, 10.0, 0, 1, [], true, false)
	check(compound_context.weapon.indirect and compound_context.weapon.twin_linked, "compound weapon keywords are executable")
	var replay_models: Array = [{"unit_id": "u", "team": 0, "position": Vector2(1, 1)}]
	var replay_log: Array = []
	replay_log = CommandLog.append(replay_log, 0, "MOVE", {"unit_id": "u", "delta": [2, 0]})
	var replay_result := Replay.replay(Replay.initial_state(replay_models), replay_log)
	check(replay_result.ok and replay_result.state.models[0].position == Vector2(3, 1), "replay reconstructs movement")
	var fnp_models: Array = [{"model_id": "fnp_attacker", "unit_id": "fnp_a", "team": 0, "position": Vector2(1, 1), "wounds": 5, "feel_no_pain": 5}, {"model_id": "fnp_target", "unit_id": "fnp_t", "team": 1, "position": Vector2(2, 1), "wounds": 5, "feel_no_pain": 5}]
	var fnp_log: Array = []
	fnp_log = CommandLog.append(fnp_log, 0, "SHOOT", {"attacker_id": "fnp_attacker", "target_id": "fnp_target", "damage": 3, "feel_no_pain_rolls": [5, 2, 6]})
	var fnp_replay := Replay.replay(Replay.initial_state(fnp_models, "SHOOTING", 0), fnp_log)
	check(fnp_replay.ok and fnp_replay.state.models[1].wounds == 4, "replay verifies feel no pain rolls")
	var hazardous_replay_log: Array = []
	hazardous_replay_log = CommandLog.append(hazardous_replay_log, 0, "SHOOT", {"attacker_id": "fnp_attacker", "target_id": "fnp_target", "damage": 1, "feel_no_pain_rolls": [1], "hazardous_damage": 3, "hazardous_feel_no_pain_rolls": [5, 2, 6]})
	var hazardous_replay := Replay.replay(Replay.initial_state(fnp_models, "SHOOTING", 0), hazardous_replay_log)
	check(hazardous_replay.ok and hazardous_replay.state.models[0].wounds == 4 and hazardous_replay.state.models[1].wounds == 4, "replay applies hazardous self damage with verified rolls")
	var advance_replay_log: Array = []
	advance_replay_log = CommandLog.append(advance_replay_log, 0, "ADVANCE", {"unit_id": "u", "roll": 4})
	var advance_replay := Replay.replay(Replay.initial_state(replay_models), advance_replay_log)
	check(advance_replay.ok and advance_replay.state.models[0].advanced and advance_replay.state.models[0].advance_bonus == 4, "replay applies advance metadata")
	var reserve_models: Array = [{"model_id": "reserve_m001", "unit_id": "reserve_unit", "team": 0, "position": Vector2(3, 3), "radius": 0.5, "ability_ids": ["deep_strike"], "reserve_status": "reserve"}, {"model_id": "reserve_enemy_m001", "unit_id": "reserve_enemy", "team": 1, "position": Vector2(40, 30), "radius": 0.5}]
	check(Reserves.has_deep_strike(reserve_models[0]) and Reserves.in_reserve(reserve_models[0]), "deep strike reserve metadata is recognized")
	var reserve_arrival_log: Array = []
	reserve_arrival_log = CommandLog.append(reserve_arrival_log, 0, "DEPLOY_RESERVE", {"unit_id": "reserve_unit", "positions": [[20, 20]]})
	var reserve_arrival := Replay.replay(Replay.initial_state(reserve_models, "MOVEMENT", 0), reserve_arrival_log)
	check(reserve_arrival.ok and reserve_arrival.state.models[0].reserve_status == "deployed" and reserve_arrival.state.models[0].position == Vector2(20, 20), "replay deploys deep strike reserve")
	var reserve_too_close_log: Array = []
	reserve_too_close_log = CommandLog.append(reserve_too_close_log, 0, "DEPLOY_RESERVE", {"unit_id": "reserve_unit", "positions": [[39, 30]]})
	var reserve_too_close := Replay.replay(Replay.initial_state(reserve_models, "MOVEMENT", 0), reserve_too_close_log)
	check(not reserve_too_close.ok and reserve_too_close.reason == "TOO CLOSE TO ENEMY", "deep strike enforces enemy distance")
	var reserve_move_log: Array = []
	reserve_move_log = CommandLog.append(reserve_move_log, 0, "MOVE", {"unit_id": "reserve_unit", "delta": [1, 0]})
	var reserve_move := Replay.replay(Replay.initial_state(reserve_models, "MOVEMENT", 0), reserve_move_log)
	check(not reserve_move.ok and reserve_move.reason == "UNIT IN RESERVE", "reserve unit cannot move before arrival")
	var transport_models: Array = [{"model_id": "transport_m001", "unit_id": "transport", "team": 0, "position": Vector2(5, 5), "radius": 1.0, "movement_inches": 10.0, "transport_capacity": 5, "wounds": 8}, {"model_id": "passenger_m001", "unit_id": "passenger", "team": 0, "position": Vector2(6, 5), "radius": 0.5, "wounds": 3}, {"model_id": "transport_enemy_m001", "unit_id": "transport_enemy", "team": 1, "position": Vector2(40, 30), "radius": 0.5, "wounds": 3}]
	var embark_log: Array = []
	embark_log = CommandLog.append(embark_log, 0, "EMBARK", {"unit_id": "passenger", "transport_id": "transport_m001"})
	embark_log = CommandLog.append(embark_log, 0, "TRANSPORT_MOVE", {"transport_id": "transport_m001", "delta": [3, 0]})
	var embarked_replay := Replay.replay(Replay.initial_state(transport_models, "MOVEMENT", 0), embark_log)
	check(embarked_replay.ok and embarked_replay.state.models[1].embarked_in == "transport_m001" and embarked_replay.state.models[1].position == Vector2(9, 5) and embarked_replay.state.models[0].transport_moved, "replay moves embarked passengers with transport")
	var bad_disembark_log := embark_log.duplicate(true)
	bad_disembark_log = CommandLog.append(bad_disembark_log, 0, "DISEMBARK", {"unit_id": "passenger", "positions": [[8, 5]]})
	var bad_disembark := Replay.replay(Replay.initial_state(transport_models, "MOVEMENT", 0), bad_disembark_log)
	check(not bad_disembark.ok and bad_disembark.reason == "TRANSPORT ALREADY MOVED", "replay blocks disembark after transport movement")
	var valid_disembark_log: Array = []
	valid_disembark_log = CommandLog.append(valid_disembark_log, 0, "EMBARK", {"unit_id": "passenger", "transport_id": "transport_m001"})
	valid_disembark_log = CommandLog.append(valid_disembark_log, 0, "DISEMBARK", {"unit_id": "passenger", "positions": [[8, 5]]})
	var valid_disembark := Replay.replay(Replay.initial_state(transport_models, "MOVEMENT", 0), valid_disembark_log)
	check(valid_disembark.ok and valid_disembark.state.models[1].embarked_in.is_empty() and valid_disembark.state.models[1].position == Vector2(8, 5), "replay disembarks within transport range")
	var scout_models: Array = [{"model_id": "scout_m001", "unit_id": "scout_unit", "team": 0, "position": Vector2(5, 5), "radius": 0.5, "ability_ids": ["scout_6"]}, {"model_id": "scout_enemy_m001", "unit_id": "scout_enemy", "team": 1, "position": Vector2(30, 30), "radius": 0.5}]
	var scout_log: Array = []
	scout_log = CommandLog.append(scout_log, 0, "SCOUT", {"unit_id": "scout_unit", "delta": [3, 0]})
	var scout_replay := Replay.replay(Replay.initial_state(scout_models, "COMMAND", 0), scout_log)
	check(scout_replay.ok and scout_replay.state.models[0].position == Vector2(8, 5) and scout_replay.state.models[0].scouted, "replay applies scout move")
	var repeated_scout_log := scout_log.duplicate(true)
	repeated_scout_log = CommandLog.append(repeated_scout_log, 0, "SCOUT", {"unit_id": "scout_unit", "delta": [1, 0]})
	var repeated_scout := Replay.replay(Replay.initial_state(scout_models, "COMMAND", 0), repeated_scout_log)
	check(not repeated_scout.ok and repeated_scout.reason == "UNIT ALREADY SCOUTED", "replay blocks repeated scout")
	var attachment_models: Array = [{"model_id": "leader_m001", "unit_id": "leader", "team": 0, "position": Vector2(5, 5), "radius": 0.5, "movement_inches": 6.0, "wounds": 3, "leader": true, "leader_for": ["bodyguard"]}, {"model_id": "bodyguard_m001", "unit_id": "bodyguard", "team": 0, "position": Vector2(6.2, 5), "radius": 0.5, "movement_inches": 6.0, "wounds": 3, "keywords": ["bodyguard"]}, {"model_id": "attachment_enemy_m001", "unit_id": "attachment_enemy", "team": 1, "position": Vector2(40, 30), "radius": 0.5}]
	check(Attachments.attach_reason(attachment_models, "leader", "bodyguard", 0).is_empty(), "leader attachment eligibility")
	var attachment_log: Array = []
	attachment_log = CommandLog.append(attachment_log, 0, "ATTACH", {"leader_unit_id": "leader", "bodyguard_unit_id": "bodyguard"})
	var attachment_replay := Replay.replay(Replay.initial_state(attachment_models, "COMMAND", 0), attachment_log)
	check(attachment_replay.ok and attachment_replay.state.models[0].attached_to == "bodyguard" and attachment_replay.state.models[1].attached_leader_id == "leader", "replay applies leader attachment")
	var attachment_move_log: Array = attachment_log.duplicate(true)
	attachment_move_log = CommandLog.append(attachment_move_log, 0, "PHASE_ADVANCE", {"from": "COMMAND", "to": "MOVEMENT"})
	attachment_move_log = CommandLog.append(attachment_move_log, 0, "MOVE", {"unit_id": "bodyguard", "delta": [1, 0]})
	var attachment_move := Replay.replay(Replay.initial_state(attachment_models, "COMMAND", 0), attachment_move_log)
	check(attachment_move.ok and attachment_move.state.models[0].position == Vector2(6, 5) and attachment_move.state.models[1].position == Vector2(7.2, 5), "attached leader and bodyguard move together")
	var detach_log: Array = attachment_log.duplicate(true)
	detach_log = CommandLog.append(detach_log, 0, "DETACH", {"leader_unit_id": "leader"})
	var detach_replay := Replay.replay(Replay.initial_state(attachment_models, "COMMAND", 0), detach_log)
	check(detach_replay.ok and detach_replay.state.models[0].attached_to.is_empty() and detach_replay.state.models[1].attached_leader_id.is_empty(), "replay clears leader attachment")
	var repeated_advance_log := advance_replay_log.duplicate(true)
	repeated_advance_log = CommandLog.append(repeated_advance_log, 0, "ADVANCE", {"unit_id": "u", "roll": 3})
	var repeated_advance := Replay.replay(Replay.initial_state(replay_models), repeated_advance_log)
	check(not repeated_advance.ok and repeated_advance.reason == "UNIT ALREADY ADVANCED", "replay blocks repeated advance")
	var engaged_advance_models: Array = [{"model_id": "advance_engaged_m001", "unit_id": "advance_engaged", "team": 0, "position": Vector2(8, 8), "radius": 0.5}, {"model_id": "advance_enemy_m001", "unit_id": "advance_enemy", "team": 1, "position": Vector2(9, 8), "radius": 0.5}]
	var engaged_advance_log: Array = []
	engaged_advance_log = CommandLog.append(engaged_advance_log, 0, "ADVANCE", {"unit_id": "advance_engaged", "roll": 4})
	var engaged_advance := Replay.replay(Replay.initial_state(engaged_advance_models, "MOVEMENT", 0), engaged_advance_log)
	check(not engaged_advance.ok and engaged_advance.reason == "ENGAGED UNIT MUST FALL BACK", "replay blocks advance while engaged")
	var foreign_advance := Replay.replay(Replay.initial_state(replay_models), [{"sequence": 0, "team": 1, "kind": "ADVANCE", "payload": {"unit_id": "u", "roll": 4}}])
	check(not foreign_advance.ok and foreign_advance.reason == "NOT ACTIVE TEAM", "replay rejects foreign advance")
	var bad_replay := Replay.replay(Replay.initial_state(replay_models), [{"sequence": 1, "team": 0, "kind": "MOVE", "payload": {}}])
	check(not bad_replay.ok and bad_replay.reason == "SEQUENCE GAP", "replay rejects sequence gaps")
	var shock_replay_log: Array = []
	shock_replay_log = CommandLog.append(shock_replay_log, 0, "BATTLE_SHOCK", {"unit_id": "u", "passed": false})
	var shock_replay := Replay.replay(Replay.initial_state(replay_models), shock_replay_log)
	check(shock_replay.ok and shock_replay.state.models[0].battle_shocked and not shock_replay.state.models[0].can_control, "replay applies battle shock")
	var valid_shock_roll_log: Array = []
	valid_shock_roll_log = CommandLog.append(valid_shock_roll_log, 0, "BATTLE_SHOCK", {"unit_id": "u", "rolls": [3, 4], "total": 7, "passed": true})
	var valid_shock_roll := Replay.replay(Replay.initial_state(replay_models), valid_shock_roll_log)
	check(valid_shock_roll.ok and not valid_shock_roll.state.models[0].battle_shocked, "replay validates battle shock roll")
	var invalid_shock_roll_log: Array = []
	invalid_shock_roll_log = CommandLog.append(invalid_shock_roll_log, 0, "BATTLE_SHOCK", {"unit_id": "u", "rolls": [3, 4], "total": 7, "passed": false})
	var invalid_shock_roll := Replay.replay(Replay.initial_state(replay_models), invalid_shock_roll_log)
	check(not invalid_shock_roll.ok and invalid_shock_roll.reason == "INVALID BATTLE SHOCK RESULT", "replay rejects forged battle shock result")
	var combat_replay_models: Array = [{"model_id": "attacker_m001", "unit_id": "attacker", "team": 0, "wounds": 3}, {"model_id": "target_m001", "unit_id": "target", "team": 1, "wounds": 4}]
	var combat_replay_log: Array = []
	combat_replay_log = CommandLog.append(combat_replay_log, 0, "SHOOT", {"attacker": 0, "attacker_id": "attacker_m001", "target": 1, "target_id": "target_m001", "damage": 3})
	var combat_replay := Replay.replay(Replay.initial_state(combat_replay_models, "SHOOTING", 0), combat_replay_log)
	check(combat_replay.ok and combat_replay.state.models[1].wounds == 1, "replay applies shooting damage")
	var one_shot_models: Array = [{"model_id": "shot_m001", "unit_id": "shot", "team": 0, "wounds": 3}, {"model_id": "shot_target_m001", "unit_id": "shot_target", "team": 1, "wounds": 4}]
	var one_shot_log: Array = []
	one_shot_log = CommandLog.append(one_shot_log, 0, "SHOOT", {"attacker": 0, "attacker_id": "shot_m001", "target": 1, "target_id": "shot_target_m001", "weapon": "Single-use weapon", "one_shot": true, "damage": 1})
	one_shot_log = CommandLog.append(one_shot_log, 0, "SHOOT", {"attacker": 0, "attacker_id": "shot_m001", "target": 1, "target_id": "shot_target_m001", "weapon": "Single-use weapon", "one_shot": true, "damage": 1})
	var one_shot_replay := Replay.replay(Replay.initial_state(one_shot_models, "SHOOTING", 0), one_shot_log)
	check(not one_shot_replay.ok and one_shot_replay.reason == "ONE SHOT ALREADY USED", "replay rejects repeated one-shot weapon")
	var one_shot_fight_log: Array = []
	one_shot_fight_log = CommandLog.append(one_shot_fight_log, 0, "FIGHT", {"attacker": 0, "attacker_id": "shot_m001", "target": 1, "target_id": "shot_target_m001", "weapon": "Single-use melee", "one_shot": true, "damage": 1})
	one_shot_fight_log = CommandLog.append(one_shot_fight_log, 0, "FIGHT", {"attacker": 0, "attacker_id": "shot_m001", "target": 1, "target_id": "shot_target_m001", "weapon": "Single-use melee", "one_shot": true, "damage": 1})
	var one_shot_fight_replay := Replay.replay(Replay.initial_state(one_shot_models, "FIGHT", 0), one_shot_fight_log)
	check(not one_shot_fight_replay.ok and one_shot_fight_replay.reason == "ONE SHOT ALREADY USED", "replay rejects repeated one-shot melee weapon")
	var fall_back_models: Array = [{"model_id": "fall_m001", "unit_id": "fall", "team": 0, "position": Vector2(8, 8), "radius": 0.5}, {"model_id": "fall_enemy_m001", "unit_id": "fall_enemy", "team": 1, "position": Vector2(9, 8), "radius": 0.5}]
	var blocked_move_log: Array = []
	blocked_move_log = CommandLog.append(blocked_move_log, 0, "MOVE", {"unit_id": "fall", "delta": [-2, 0]})
	var blocked_move_replay := Replay.replay(Replay.initial_state(fall_back_models, "MOVEMENT", 0), blocked_move_log)
	check(not blocked_move_replay.ok and blocked_move_replay.reason == "ENGAGED UNIT MUST FALL BACK", "replay blocks normal movement while engaged")
	var fall_back_log: Array = []
	fall_back_log = CommandLog.append(fall_back_log, 0, "FALL_BACK", {"unit_id": "fall", "delta": [-2, 0]})
	var fall_back_replay := Replay.replay(Replay.initial_state(fall_back_models, "MOVEMENT", 0), fall_back_log)
	check(fall_back_replay.ok and fall_back_replay.state.models[0].position == Vector2(6, 8) and fall_back_replay.state.models[0].fell_back and is_equal_approx(fall_back_replay.state.models[0].spent, 2.0), "replay applies fall back metadata")
	var repeated_fall_back_move_log := fall_back_log.duplicate(true)
	repeated_fall_back_move_log = CommandLog.append(repeated_fall_back_move_log, 0, "MOVE", {"unit_id": "fall", "delta": [-1, 0]})
	var repeated_fall_back_move := Replay.replay(Replay.initial_state(fall_back_models, "MOVEMENT", 0), repeated_fall_back_move_log)
	check(not repeated_fall_back_move.ok and repeated_fall_back_move.reason == "FELL BACK", "replay blocks movement after fall back")
	var limited_move_models: Array = [{"model_id": "limited_m001", "unit_id": "limited", "team": 0, "position": Vector2(8, 8), "movement_inches": 2.0, "spent": 0.0}]
	var limited_move_log: Array = []
	limited_move_log = CommandLog.append(limited_move_log, 0, "MOVE", {"unit_id": "limited", "delta": [3, 0]})
	var limited_move_replay := Replay.replay(Replay.initial_state(limited_move_models, "MOVEMENT", 0), limited_move_log)
	check(not limited_move_replay.ok and limited_move_replay.reason == "MOVE LIMIT EXCEEDED", "replay enforces movement allowance")
	var terrain_replay_models: Array = [{"model_id": "terrain_m001", "unit_id": "terrain", "team": 0, "position": Vector2(2, 5), "radius": 0.5, "movement_inches": 10.0}, {"model_id": "terrain_enemy_m001", "unit_id": "terrain_enemy", "team": 1, "position": Vector2(20, 20), "radius": 0.5}]
	var terrain_replay_log: Array = []
	terrain_replay_log = CommandLog.append(terrain_replay_log, 0, "MOVE", {"unit_id": "terrain", "delta": [6, 0]})
	var terrain_replay := Replay.replay(Replay.initial_state(terrain_replay_models, "MOVEMENT", 0, [{"id": "wall", "x": 4.0, "y": 4.0, "width": 2.0, "height": 2.0}]), terrain_replay_log)
	check(not terrain_replay.ok and terrain_replay.reason == "TERRAIN BLOCKED", "replay blocks terrain crossing")
	var base_replay_models: Array = [{"model_id": "base_m001", "unit_id": "base", "team": 0, "position": Vector2(2, 5), "radius": 0.5, "movement_inches": 10.0}, {"model_id": "base_enemy_m001", "unit_id": "base_enemy", "team": 1, "position": Vector2(5, 5), "radius": 0.5}]
	var base_replay_log: Array = []
	base_replay_log = CommandLog.append(base_replay_log, 0, "MOVE", {"unit_id": "base", "delta": [6, 0]})
	var base_replay := Replay.replay(Replay.initial_state(base_replay_models, "MOVEMENT", 0), base_replay_log)
	check(not base_replay.ok and base_replay.reason == "PATH BLOCKED", "replay blocks base crossing")
	var charge_replay_models: Array = [{"model_id": "charge_m001", "unit_id": "charge", "team": 0, "position": Vector2(5, 5), "radius": 0.5}, {"model_id": "charge_target_m001", "unit_id": "charge_target", "team": 1, "position": Vector2(8, 5), "radius": 0.5}]
	var charge_replay_log: Array = []
	charge_replay_log = CommandLog.append(charge_replay_log, 0, "CHARGE", {"model": 0, "model_id": "charge_m001", "target": 1, "target_id": "charge_target_m001", "roll": [2, 2], "to": [7.0, 5.0]})
	var charge_replay := Replay.replay(Replay.initial_state(charge_replay_models, "CHARGE", 0), charge_replay_log)
	check(charge_replay.ok and charge_replay.state.models[0].position == Vector2(7, 5), "replay validates charge distance and engagement")
	var bad_charge_log: Array = []
	bad_charge_log = CommandLog.append(bad_charge_log, 0, "CHARGE", {"model": 0, "model_id": "charge_m001", "target": 1, "target_id": "charge_target_m001", "roll": [6, 6], "to": [5.0, 12.0]})
	var bad_charge := Replay.replay(Replay.initial_state(charge_replay_models, "CHARGE", 0), bad_charge_log)
	check(not bad_charge.ok and bad_charge.reason == "NOT IN ENGAGEMENT", "replay rejects invalid charge endpoint")
	var weapon_replay_models: Array = [{"model_id": "weapon_m001", "unit_id": "weapon", "team": 0, "position": Vector2(5, 5), "radius": 0.5, "weapons": [{"name": "Test Rifle", "range_inches": 6.0}]}, {"model_id": "weapon_target_m001", "unit_id": "weapon_target", "team": 1, "position": Vector2(8, 5), "radius": 0.5, "wounds": 3}]
	var weapon_replay_log: Array = []
	weapon_replay_log = CommandLog.append(weapon_replay_log, 0, "SHOOT", {"attacker": 0, "attacker_id": "weapon_m001", "target": 1, "target_id": "weapon_target_m001", "weapon": "Test Rifle", "damage": 1})
	var weapon_replay := Replay.replay(Replay.initial_state(weapon_replay_models, "SHOOTING", 0), weapon_replay_log)
	check(weapon_replay.ok and weapon_replay.state.models[1].wounds == 2, "replay validates named weapon range")
	var protected_target_models: Array = [{"model_id": "precision_attacker_m001", "unit_id": "precision_attacker", "team": 0, "position": Vector2(5, 5), "radius": 0.5, "weapons": [{"name": "Basic Rifle", "range_inches": 6.0}]}, {"model_id": "precision_leader_m001", "unit_id": "precision_leader", "team": 1, "position": Vector2(8, 5), "radius": 0.5, "attached_to": "precision_bodyguard", "wounds": 3}, {"model_id": "precision_bodyguard_m001", "unit_id": "precision_bodyguard", "team": 1, "position": Vector2(8.8, 5), "radius": 0.5, "attached_leader_id": "precision_leader", "wounds": 3}]
	var protected_target_log: Array = []
	protected_target_log = CommandLog.append(protected_target_log, 0, "SHOOT", {"attacker": 0, "attacker_id": "precision_attacker_m001", "target": 1, "target_id": "precision_leader_m001", "weapon": "Basic Rifle", "damage": 1})
	var protected_target_replay := Replay.replay(Replay.initial_state(protected_target_models, "SHOOTING", 0), protected_target_log)
	check(not protected_target_replay.ok and protected_target_replay.reason == "PRECISION REQUIRED", "replay protects attached leader from non-precision fire")
	var out_of_range_models := weapon_replay_models.duplicate(true)
	out_of_range_models[1].position = Vector2(20, 5)
	var out_of_range := Replay.replay(Replay.initial_state(out_of_range_models, "SHOOTING", 0), weapon_replay_log)
	check(not out_of_range.ok and out_of_range.reason == "OUT OF RANGE", "replay rejects out of range weapon")
	var missing_weapon_log: Array = []
	missing_weapon_log = CommandLog.append(missing_weapon_log, 0, "SHOOT", {"attacker": 0, "attacker_id": "weapon_m001", "target": 1, "target_id": "weapon_target_m001", "damage": 1})
	var missing_weapon := Replay.replay(Replay.initial_state(weapon_replay_models, "SHOOTING", 0), missing_weapon_log)
	check(not missing_weapon.ok and missing_weapon.reason == "MISSING WEAPON", "replay requires named weapon for profiled model")
	var melee_replay_models: Array = weapon_replay_models.duplicate(true)
	melee_replay_models[1].position = Vector2(5.9, 5)
	melee_replay_models[0].weapons = [{"name": "Test Blade"}]
	var melee_replay_log: Array = []
	melee_replay_log = CommandLog.append(melee_replay_log, 0, "FIGHT", {"attacker": 0, "attacker_id": "weapon_m001", "target": 1, "target_id": "weapon_target_m001", "weapon": "Test Blade", "damage": 1})
	var melee_replay := Replay.replay(Replay.initial_state(melee_replay_models, "FIGHT", 0), melee_replay_log)
	check(melee_replay.ok and melee_replay.state.models[1].wounds == 2, "replay validates melee engagement")
	var repeated_melee_log := melee_replay_log.duplicate(true)
	repeated_melee_log = CommandLog.append(repeated_melee_log, 0, "FIGHT", {"attacker": 0, "attacker_id": "weapon_m001", "target": 1, "target_id": "weapon_target_m001", "weapon": "Test Blade", "damage": 1})
	var repeated_melee := Replay.replay(Replay.initial_state(melee_replay_models, "FIGHT", 0), repeated_melee_log)
	check(not repeated_melee.ok and repeated_melee.reason == "UNIT ALREADY FOUGHT", "replay blocks a second fight activation in one phase")
	var fights_first_models: Array = [{"model_id": "normal_fighter_m001", "unit_id": "normal_fighter", "team": 0, "position": Vector2(5, 5), "radius": 0.5, "weapons": [{"name": "Test Blade"}]}, {"model_id": "first_fighter_m001", "unit_id": "first_fighter", "team": 0, "position": Vector2(5, 5.5), "radius": 0.5, "ability_ids": ["fights_first"], "weapons": [{"name": "Test Blade"}]}, {"model_id": "first_target_m001", "unit_id": "first_target", "team": 1, "position": Vector2(5, 6), "radius": 0.5, "wounds": 3}]
	var normal_before_first := Replay.replay(Replay.initial_state(fights_first_models, "FIGHT", 0), [{"sequence": 0, "team": 0, "kind": "FIGHT", "payload": {"attacker": 0, "attacker_id": "normal_fighter_m001", "target": 2, "target_id": "first_target_m001", "weapon": "Test Blade", "damage": 1}}])
	check(not normal_before_first.ok and normal_before_first.reason == "FIGHTS FIRST UNIT MUST ACTIVATE", "replay enforces fights first priority")
	var first_attack := Replay.replay(Replay.initial_state(fights_first_models, "FIGHT", 0), [{"sequence": 0, "team": 0, "kind": "FIGHT", "payload": {"attacker": 1, "attacker_id": "first_fighter_m001", "target": 2, "target_id": "first_target_m001", "weapon": "Test Blade", "damage": 1}}])
	check(first_attack.ok and first_attack.state.models[1].fought, "replay allows fights first activation")
	var stratagem_state := Replay.initial_state(one_shot_models, "SHOOTING", 0)
	stratagem_state.command_points = [1, 0]
	var stratagem_log: Array = []
	stratagem_log = CommandLog.append(stratagem_log, 0, "STRATAGEM", {"id": "command_reroll", "phase": "SHOOTING"})
	stratagem_log = CommandLog.append(stratagem_log, 0, "STRATAGEM", {"id": "command_reroll", "phase": "SHOOTING"})
	var stratagem_replay := Replay.replay(stratagem_state, stratagem_log)
	check(not stratagem_replay.ok and stratagem_replay.reason == "NOT ENOUGH COMMAND POINTS", "replay enforces stratagem command points")
	var cover_state := Replay.initial_state(one_shot_models, "SHOOTING", 0)
	cover_state.command_points = [1, 0]
	var cover_log: Array = []
	cover_log = CommandLog.append(cover_log, 0, "STRATAGEM", {"id": "go_to_ground", "phase": "SHOOTING", "unit_id": "shot"})
	var cover_replay := Replay.replay(cover_state, cover_log)
	check(cover_replay.ok and int(cover_replay.state.models[0].get("temporary_cover_bonus", 0)) == 1, "replay applies temporary cover stratagem")
	var bravery_state := Replay.initial_state(one_shot_models, "COMMAND", 0)
	bravery_state.command_points = [1, 0]
	var bravery_log: Array = []
	bravery_log = CommandLog.append(bravery_log, 0, "STRATAGEM", {"id": "insane_bravery", "phase": "COMMAND", "unit_id": "shot"})
	bravery_log = CommandLog.append(bravery_log, 0, "BATTLE_SHOCK", {"unit_id": "shot", "passed": true})
	var bravery_replay := Replay.replay(bravery_state, bravery_log)
	check(bravery_replay.ok and not bool(bravery_replay.state.models[0].get("battle_shocked", false)), "replay applies automatic battle shock pass stratagem")
	var faction_stratagem_models: Array = one_shot_models.duplicate(true)
	faction_stratagem_models[0].faction_stratagems = [{"id": "faction_cover", "cost": 1, "phase": "SHOOTING", "effect": "TEMPORARY_COVER", "timing": "SHOOTING"}]
	var faction_stratagem_state := Replay.initial_state(faction_stratagem_models, "SHOOTING", 0)
	faction_stratagem_state.command_points = [1, 0]
	var faction_stratagem_log: Array = []
	faction_stratagem_log = CommandLog.append(faction_stratagem_log, 0, "STRATAGEM", {"id": "faction_cover", "phase": "SHOOTING", "unit_id": "shot"})
	var faction_stratagem_replay := Replay.replay(faction_stratagem_state, faction_stratagem_log)
	check(faction_stratagem_replay.ok and int(faction_stratagem_replay.state.models[0].get("temporary_cover_bonus", 0)) == 1, "replay resolves faction-declared stratagem")
	var phase_replay_log: Array = []
	phase_replay_log = CommandLog.append(phase_replay_log, 0, "PHASE_ADVANCE", {"from": "MOVEMENT", "to": "SHOOTING"})
	phase_replay_log = CommandLog.append(phase_replay_log, 0, "SHOOT", {"attacker": 0, "attacker_id": "attacker_m001", "target": 1, "target_id": "target_m001", "damage": 1})
	var phase_replay := Replay.replay(Replay.initial_state(combat_replay_models, "MOVEMENT", 0), phase_replay_log)
	check(phase_replay.ok and phase_replay.state.phase == "SHOOTING" and phase_replay.state.models[1].wounds == 3, "replay reconstructs phase transition before shooting")
	var friendly_damage_log: Array = []
	var friendly_models := combat_replay_models.duplicate(true)
	friendly_models.append({"model_id": "friendly_m001", "unit_id": "friendly", "team": 0, "wounds": 3})
	friendly_damage_log = CommandLog.append(friendly_damage_log, 0, "SHOOT", {"attacker": 0, "attacker_id": "attacker_m001", "target": 2, "target_id": "friendly_m001", "damage": 1})
	var friendly_damage := Replay.replay(Replay.initial_state(friendly_models, "SHOOTING", 0), friendly_damage_log)
	check(not friendly_damage.ok and friendly_damage.reason == "FRIENDLY TARGET", "replay rejects friendly damage target")
	var foreign_attacker_log: Array = []
	foreign_attacker_log = CommandLog.append(foreign_attacker_log, 1, "SHOOT", {"attacker": 0, "attacker_id": "attacker_m001", "target": 1, "target_id": "target_m001", "damage": 1})
	var foreign_attacker := Replay.replay(Replay.initial_state(combat_replay_models, "SHOOTING", 1), foreign_attacker_log)
	check(not foreign_attacker.ok and foreign_attacker.reason == "NOT ACTIVE TEAM", "replay rejects foreign attacker")
	var destroyed_replay_log: Array = []
	destroyed_replay_log = CommandLog.append(destroyed_replay_log, 0, "SHOOT", {"attacker": 0, "attacker_id": "attacker_m001", "target": 1, "target_id": "target_m001", "damage": 4})
	var destroyed_replay := Replay.replay(Replay.initial_state(combat_replay_models, "SHOOTING", 0), destroyed_replay_log)
	check(destroyed_replay.ok and destroyed_replay.state.models.size() == 1 and destroyed_replay.state.models[0].model_id == "attacker_m001", "replay removes destroyed model by stable id")
	var turn := TurnState.new_state(0)
	check(TurnState.is_valid(turn) and turn.phase == "COMMAND", "turn state starts in command phase")
	for expected in ["MOVEMENT", "SHOOTING", "CHARGE", "FIGHT"]:
		turn = TurnState.advance(turn)
		check(turn.phase == expected, "turn advances to %s" % expected)
	turn = TurnState.advance(turn)
	check(turn.round == 2 and turn.active_team == 1 and turn.phase == "COMMAND", "turn wraps to next round and side")
	var profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/custodian_guard_profile.json"))
	check(DatasheetValidation.validate_profile(profile).is_empty(), "versioned datasheet validates")
	var ap_profile: Dictionary = profile.duplicate(true)
	ap_profile.weapons[0].ap = -2
	check(DatasheetValidation.validate_profile(ap_profile).is_empty(), "profile accepts signed nonpositive AP")
	ap_profile.weapons[0].ap = 2
	check(DatasheetValidation.validate_profile(ap_profile) == "INVALID WEAPON AP", "profile rejects positive AP convention mismatch")
	ap_profile.weapons[0].ap = -1.5
	check(DatasheetValidation.validate_profile(ap_profile) == "INVALID WEAPON AP", "profile rejects fractional AP")

	check(RulesetCatalog.supported(10) and RulesetCatalog.get_ruleset(11).id == "wh40k_11e" and RulesetCatalog.phases(11).size() == 5, "ruleset catalog exposes supported editions")
	var unsupported_edition := profile.duplicate(true)
	unsupported_edition.edition = 12
	check(DatasheetValidation.validate_profile(unsupported_edition) == "UNSUPPORTED EDITION 12", "datasheet rejects unregistered edition")
	var invalid_weapon_dice := profile.duplicate(true)
	invalid_weapon_dice.weapons[0].attacks = "D4"
	check(DatasheetValidation.validate_profile(invalid_weapon_dice) == "INVALID DICE ATTACKS", "datasheet rejects unsupported weapon dice")
	check(DatasheetValidation.points_total(profile) == 100, "datasheet points total")
	var invalid_profile: Dictionary = profile.duplicate(true)
	invalid_profile.models[0].erase("wounds")
	check(DatasheetValidation.validate_profile(invalid_profile) == "MODEL MISSING WOUNDS", "datasheet reports missing model field")
	var ability_profile: Dictionary = profile.duplicate(true)
	ability_profile.abilities = ["stealth", "reroll_hit_ones"]
	check(DatasheetValidation.validate_profile(ability_profile).is_empty(), "datasheet validates executable abilities")
	ability_profile.abilities = ["unknown_ability"]
	check(DatasheetValidation.validate_profile(ability_profile) == "UNKNOWN ABILITY unknown_ability", "datasheet rejects unknown ability")
	var faction_data_profile: Dictionary = profile.duplicate(true)
	faction_data_profile.faction_abilities = ["stealth"]
	faction_data_profile.faction_stratagems = ["command_reroll"]
	check(DatasheetValidation.validate_profile(faction_data_profile).is_empty(), "datasheet validates faction ability and stratagem declarations")
	faction_data_profile.faction_stratagems = ["unknown_faction_stratagem"]
	check(DatasheetValidation.validate_profile(faction_data_profile) == "UNKNOWN STRATAGEM unknown_faction_stratagem", "datasheet rejects unknown faction stratagem")
	var keyword_profile: Dictionary = profile.duplicate(true)
	keyword_profile.keywords = ["步兵", "飞行"]
	keyword_profile.faction_keywords = ["钛帝国"]
	check(DatasheetValidation.validate_profile(keyword_profile).is_empty(), "datasheet validates unit keywords")
	keyword_profile.keywords = ["not_a_keyword"]
	check(DatasheetValidation.validate_profile(keyword_profile) == "UNKNOWN KEYWORD not_a_keyword", "datasheet rejects unknown keyword")
	var leader_profile: Dictionary = profile.duplicate(true)
	leader_profile.leader = true
	leader_profile.leader_for = ["custodian_guard"]
	check(DatasheetValidation.validate_profile(leader_profile).is_empty(), "datasheet validates leader metadata")
	leader_profile.leader_for = "custodian_guard"
	check(DatasheetValidation.validate_profile(leader_profile) == "INVALID LEADER_FOR", "datasheet rejects malformed leader metadata")
	var charge_rng := RandomNumberGenerator.new()
	charge_rng.seed = 12
	var charge_roll := Charge.charge_distance(charge_rng)
	check(charge_roll.rolls.size() == 2 and charge_roll.distance == charge_roll.rolls[0] + charge_roll.rolls[1], "charge rolls 2D6")
	var charge_attacker := {"team": 0, "base_radius": 0.8}
	var charge_target := {"team": 1, "base_radius": 0.8}
	check(Charge.target_reason(charge_attacker, charge_target, 0, 5.0, 8).is_empty(), "charge target in range")
	check(Charge.target_reason(charge_attacker, charge_target, 0, 15.0, 8) == "OUT OF CHARGE RANGE", "charge target out of range")
	var advance_charge_attacker := {"team": 0, "base_radius": 0.8, "advanced": true}
	check(Charge.target_reason(advance_charge_attacker, charge_target, 0, 5.0, 8) == "ADVANCED CANNOT CHARGE" and Charge.target_reason(advance_charge_attacker, charge_target, 0, 5.0, 8, 1.0, true).is_empty(), "advance and charge ability unlocks charge")
	var fallback_charge_attacker := {"team": 0, "base_radius": 0.8, "fell_back": true}
	check(Charge.target_reason(fallback_charge_attacker, charge_target, 0, 5.0, 8) == "FELL BACK" and Charge.target_reason(fallback_charge_attacker, charge_target, 0, 5.0, 8, 1.0, false, true).is_empty(), "fall back and charge ability unlocks charge")
	check(Charge.end_reason(Vector2(10, 10), Vector2(10.8, 10)).is_empty(), "charge ends in engagement")
	check(Charge.end_reason(Vector2(10, 10), Vector2(13.5, 10), 1.0, 2.0, 1.0).is_empty(), "charge engagement includes base radii")
	var melee_attacker := {"team": 0, "distance_to_target": 0.8}
	var melee_target := {"team": 1}
	check(Melee.target_reason(melee_attacker, melee_target, 0).is_empty(), "melee target is engaged")
	var positioned_attacker := {"team": 0, "position": Vector2(10, 10), "radius": 2.0}
	var positioned_target := {"team": 1, "position": Vector2(13.5, 10), "radius": 1.0}
	check(is_equal_approx(Engagement.separation(positioned_attacker, positioned_target), 0.5) and Engagement.in_engagement(positioned_attacker, positioned_target), "engagement subtracts both base radii")
	check(is_equal_approx(Engagement.separation({"position": [10, 10], "radius": 2.0}, {"position": [13.5, 10], "radius": 1.0}), 0.5), "engagement accepts JSON coordinates")
	check(Melee.target_reason(positioned_attacker, positioned_target, 0).is_empty(), "melee uses positioned engagement geometry")
	var melee_keyword_result := Melee.resolve_attack({"attacks": 0, "hit_on": 4, "strength": 4, "damage": 1, "abilities": ["针对步兵4+"]}, {"toughness": 8, "save_on": 7}, combat_rng, 0, ["步兵"])
	check(melee_keyword_result.wound_on == 4, "melee resolves weapon keyword context")
	var obstacles: Array = [{"x": 4.0, "y": 4.0, "width": 2.0, "height": 2.0}]
	check(Terrain.circle_reason(Vector2(5, 5), 0.5, obstacles) == "TERRAIN BLOCKED", "terrain blocks base placement")
	check(Terrain.path_reason(Vector2(2, 5), Vector2(8, 5), 0.5, obstacles) == "TERRAIN BLOCKED", "terrain blocks movement path")
	var flying_model := {"position": Vector2(2, 5), "radius": 0.5, "spent": 0.0, "keywords": ["飞行"]}
	check(Rules.movement_reason_for_model(flying_model, Vector2(8, 5), 10.0, [], -1, obstacles).is_empty(), "fly unit crosses terrain path")
	check(Rules.movement_reason_for_model(flying_model, Vector2(5, 5), 10.0, [], -1, obstacles) == "TERRAIN BLOCKED", "fly unit still cannot end inside terrain")
	check(Visibility.blocked(Vector2(2, 5), Vector2(8, 5), obstacles), "terrain blocks line of sight")
	check(not Visibility.blocked(Vector2(2, 2), Vector2(8, 2), obstacles), "clear line of sight passes")
	var covered_obstacle: Array = [{"x": 4.0, "y": 4.0, "width": 2.0, "height": 2.0, "cover_bonus": 1}]
	check(Visibility.cover_bonus(Vector2(2, 5), Vector2(8, 5), covered_obstacle) == 1, "terrain cover bonus is detected")
	check(Combat.resolve_ranged_attack({"attacks": 0, "hit_on": 4, "strength": 4, "damage": 1}, {"toughness": 4, "save_on": 4, "cover_save_bonus": 1}, combat_rng).save_on == 3, "cover improves save threshold from four to three")
	var damage_model := {"wounds": 3}
	var damage_result := Damage.apply_to_model(damage_model, 2)
	check(damage_result.wounds_after == 1 and not damage_result.destroyed, "damage reduces model wounds")
	var damage_unit: Array = [{"wounds": 2}, {"wounds": 1}]
	var destroyed_result := Damage.allocate_to_unit(damage_unit, 2, 0)
	check(destroyed_result.destroyed == 1 and damage_unit.size() == 1, "destroyed model is removed from unit")
	var objective_models: Array = [
		{"team": 0, "position": Vector2(10, 10)},
		{"team": 1, "position": Vector2(10.5, 10)}
	]
	check(MissionRules.controller(Vector2(10, 10), objective_models, 3.0) == -1, "contested objective has no controller")
	var shocked_controller := [{"position": Vector2(10, 10), "team": 0, "objective_control": 5, "battle_shocked": true}]
	check(MissionRules.controller(Vector2(10, 10), shocked_controller, 3.0) == -1, "battle shocked model cannot control objective")
	objective_models.remove_at(1)
	check(MissionRules.controller(Vector2(10, 10), objective_models, 3.0) == 0, "objective controller is detected")
	var mission_score := MissionRules.score_objectives([{"position": Vector2(10, 10), "points": 2}], objective_models, 3.0)
	check(mission_score.score[0] == 2 and mission_score.controllers[0] == 0, "objective value is scored")
	var oc_aura := {"id": "fixture_oc_aura", "aura": {"radius_inches": 3.0, "event": "objective_control", "include_self": false, "keywords": ["INFANTRY"], "when": {"phase": "COMMAND", "kind": "OBJECTIVE_CONTROL"}, "modifiers": {"objective_control_bonus": 2}}}
	var oc_source := {"model_id": "oc_source", "unit_id": "oc_source_unit", "team": 0, "position": Vector2(10, 10), "radius": 0.5, "wounds": 3, "objective_control": 1, "ability_ids": [oc_aura]}
	var oc_recipient := {"model_id": "oc_recipient", "unit_id": "oc_recipient_unit", "team": 0, "position": Vector2(12, 10), "radius": 0.5, "wounds": 3, "objective_control": 1, "keywords": ["INFANTRY"], "ability_ids": []}
	var oc_enemy := {"model_id": "oc_enemy", "unit_id": "oc_enemy_unit", "team": 1, "position": Vector2(10, 10), "radius": 0.5, "wounds": 3, "objective_control": 3, "ability_ids": []}
	check(UnitAbilities.validate([oc_aura]).is_empty(), "objective control aura schema accepts timing and bonus")
	check(MissionRules.controller(Vector2(10, 10), [oc_source, oc_recipient, oc_enemy], 3.0) == 0, "objective control aura changes authoritative controller")
	oc_recipient.position = Vector2(20, 10)
	check(MissionRules.controller(Vector2(10, 10), [oc_source, oc_recipient, oc_enemy], 3.0) == 1, "objective control aura expires outside radius")
	oc_recipient.position = Vector2(12, 10)
	oc_recipient.keywords = []
	check(MissionRules.controller(Vector2(10, 10), [oc_source, oc_recipient, oc_enemy], 3.0) == 1, "objective control aura enforces keywords")
	check(MissionRules.controller(Vector2(10, 10), [oc_source, oc_recipient, oc_enemy], 3.0, {"phase": "MOVEMENT", "kind": "OBJECTIVE_CONTROL"}) == 1, "objective control aura enforces phase")
	oc_recipient.keywords = ["INFANTRY"]
	var aura_scored_session := BattleSession.create([oc_source, oc_recipient, oc_enemy], 11, 0, [], [{"position": Vector2(10, 10), "points": 1}], 3.0, 5)
	var aura_scored_turn := BattleSession.submit(aura_scored_session, 0, "END_TURN", {})
	check(aura_scored_turn.ok and aura_scored_turn.state.score[0] == 1 and aura_scored_turn.state.score[1] == 0, "authoritative replay scores objective control aura")
	check(MissionRules.winner([5, 2], 5) == 0 and MissionRules.winner([2, 2], 5) == -1, "mission winner is detected")
	var command_points := CommandPoints.new_state()
	command_points = CommandPoints.gain(command_points, 0)
	check(command_points[0] == 1 and CommandPoints.can_spend(command_points, 0, 1), "command points are gained")
	var spent_cp := CommandPoints.spend(command_points, 0, 1)
	check(spent_cp.ok and spent_cp.points[0] == 0, "command points can be spent")
	var stratagem := {"id": "prototype_reroll", "cost": 1, "phase": "SHOOTING"}
	check(CommandPoints.validate_stratagem(stratagem, "SHOOTING", 0, spent_cp.points) == "NOT ENOUGH COMMAND POINTS", "stratagem checks resource")
	check(TurnState.advance(TurnState.new_state(0)).command_points[0] == 0, "phase advance preserves command points")
	var shock_rng := RandomNumberGenerator.new()
	shock_rng.seed = 21
	var shock_result := BattleShock.test(7, shock_rng)
	check(shock_result.rolls.size() == 2 and shock_result.total == shock_result.rolls[0] + shock_result.rolls[1], "battle shock rolls 2D6")
	var shocked_unit := BattleShock.apply({"battle_shocked": false}, {"passed": false})
	check(shocked_unit.battle_shocked and not BattleShock.can_control_objective(shocked_unit), "failed battle shock blocks objective control")
	var steady_unit := BattleShock.apply({"battle_shocked": true}, {"passed": true})
	check(not steady_unit.battle_shocked and BattleShock.can_control_objective(steady_unit), "passed battle shock restores control")
	check(BattleShock.required(5, 10) and not BattleShock.required(6, 10), "battle shock half-strength threshold")
	var shocked_models := BattleShock.apply_to_models([{"unit_id": "u1", "can_control": true}, {"unit_id": "u2", "can_control": true}], "u1", {"passed": false})
	check(not shocked_models[0].can_control and shocked_models[1].can_control, "battle shock applies to one unit")
	var profiles := {profile.id: profile}
	var invulnerable_profile := profile.duplicate(true)
	invulnerable_profile.models[0].invulnerable_save = 4
	var build_result := ArmyBuilder.build({"edition": 11, "points_limit": 1000, "units": [{"unit_id": profile.id, "count": 1}]}, profiles, 1)
	var invulnerable_build := ArmyBuilder.build({"edition": 11, "points_limit": 1000, "units": [{"unit_id": invulnerable_profile.id, "count": 1}]}, {invulnerable_profile.id: invulnerable_profile}, 1)
	check(build_result.valid and build_result.points == 100 and build_result.units[0].models.size() == 1 and build_result.units[0].models[0].has("save_on") and build_result.units[0].models[0].has("weapons"), "army builder expands profile")
	check(invulnerable_build.valid and invulnerable_build.units[0].models[0].invulnerable_save == 4, "army builder carries invulnerable save")
	var multi_build := ArmyBuilder.build({"edition": 11, "points_limit": 1000, "units": [{"unit_id": profile.id, "count": 10}]}, profiles, 0)
	check(multi_build.valid and multi_build.points == 1000 and multi_build.units.size() == 10, "army builder expands unit count")
	var multi_entry := ArmyBuilder.build({"edition": 11, "points_limit": 1100, "units": [{"unit_id": profile.id, "count": 10}, {"unit_id": profile.id, "count": 1}]}, profiles, 0)
	check(multi_entry.valid and multi_entry.units.size() == 11 and multi_entry.units[0].unit_id != multi_entry.units[10].unit_id, "army builder keeps multiple entries unique")
	var wrong_edition := ArmyBuilder.build({"edition": 10, "points_limit": 1000, "units": [{"unit_id": profile.id, "count": 1}]}, profiles)
	check(not wrong_edition.valid and wrong_edition.errors[0] == "EDITION MISMATCH " + profile.id, "army builder enforces edition")
	var pending_profile := profile.duplicate(true)
	pending_profile.id = "pending_profile"
	pending_profile.import_status = "pending_manual_review"
	var pending_build := ArmyBuilder.build({"edition": 11, "points_limit": 1000, "units": [{"unit_id": pending_profile.id, "count": 1}]}, {pending_profile.id: pending_profile})
	check(not pending_build.valid and pending_build.errors[0] == "PROFILE NOT READY pending_profile", "army builder rejects unreviewed profile")
	var faction_roster := {"edition": 11, "faction": "Other Faction", "points_limit": 1000, "units": [{"unit_id": profile.id, "count": 1}]}
	check(not ArmyBuilder.build(faction_roster, profiles).valid and ArmyBuilder.build(faction_roster, profiles).errors[0] == "FACTION MISMATCH " + profile.id, "army builder enforces faction")
	var incomplete_profile := profile.duplicate(true)
	incomplete_profile.id = "incomplete_profile"
	incomplete_profile.models = []
	check(not ArmyBuilder.build({"edition": 11, "points_limit": 1000, "units": [{"unit_id": incomplete_profile.id, "count": 1}]}, {incomplete_profile.id: incomplete_profile}).valid, "army builder rejects incomplete profile")
	var unique_profile := profile.duplicate(true)
	unique_profile.id = "unique_profile"
	unique_profile.organization = {"unique": true, "role": "character"}
	var unique_profiles := {unique_profile.id: unique_profile}
	var duplicate_unique := {"edition": 11, "points_limit": 1000, "units": [{"unit_id": unique_profile.id, "count": 2}]}
	check(not ArmyBuilder.build(duplicate_unique, unique_profiles).valid and ArmyBuilder.build(duplicate_unique, unique_profiles).errors[0] == "UNIT COPY LIMIT unique_profile (2/1)", "army builder enforces unique organization")
	var required_role := {"edition": 11, "points_limit": 1000, "organization": {"minimum_roles": ["battleline"]}, "units": [{"unit_id": unique_profile.id, "count": 1}]}
	check(RosterEditor.validate(required_role, unique_profiles).has("MISSING REQUIRED ROLE battleline"), "organization role validation reports missing role")
	var editable_roster := RosterEditor.create("Test Roster", 11, 1000)
	var added := RosterEditor.add_unit(editable_roster, profiles, profile.id, 1)
	check(added.ok and RosterEditor.total_points(added.roster) == 100, "roster editor adds validated unit")
	var removed := RosterEditor.remove_unit(added.roster, 0)
	check(removed.ok and removed.roster.units.is_empty(), "roster editor removes unit")
	var resized := RosterEditor.set_unit_count(added.roster, profiles, 0, 2)
	check(resized.ok and resized.roster.units[0].count == 2 and RosterEditor.total_points(resized.roster) == 200, "roster editor changes unit count")
	var lower_limit := RosterEditor.set_points_limit(resized.roster, profiles, 100)
	check(not lower_limit.ok and lower_limit.roster.points_limit == 1000, "roster editor rejects over-limit edit")
	var higher_limit := RosterEditor.set_points_limit(resized.roster, profiles, 1200)
	check(higher_limit.ok and higher_limit.roster.points_limit == 1200, "roster editor changes points limit")
	var faction_set := RosterEditor.set_faction(resized.roster, profiles, "prototype_gold")
	check(faction_set.ok and faction_set.roster.faction == "prototype_gold", "roster editor sets faction")
	var faction_blocked := RosterEditor.set_faction(resized.roster, profiles, "other_faction")
	check(not faction_blocked.ok and not faction_blocked.roster.has("faction"), "roster editor rolls back faction mismatch")
	var blocked_add := RosterEditor.add_unit(editable_roster, {pending_profile.id: pending_profile}, pending_profile.id, 1)
	check(not blocked_add.ok and blocked_add.reason == "PROFILE NOT READY pending_profile", "roster editor blocks unreviewed unit")
	var roster_json := RosterEditor.encode(resized.roster)
	var decoded_roster := RosterEditor.decode(roster_json)
	check(decoded_roster.get("display_name", "") == "Test Roster" and decoded_roster.units[0].count == 2, "roster editor JSON round trip")
	var moving_unit: Array = [
		{"position": Vector2(10, 10), "radius": 0.5, "coherency_inches": 2.0},
		{"position": Vector2(11, 10), "radius": 0.5, "coherency_inches": 2.0}
	]
	check(UnitMovement.movement_reason(moving_unit, Vector2(2, 0), 0, 6, moving_unit).is_empty(), "unit movement validates as a group")
	var moved_unit := UnitMovement.translate(moving_unit, Vector2(2, 0))
	check(moved_unit[0].position == Vector2(12, 10) and moved_unit[1].position == Vector2(13, 10), "unit translation preserves formation")
	check(UnitMovement.movement_reason(moving_unit, Vector2(7, 0), 0, 6, moving_unit) == "MOVE LIMIT EXCEEDED", "unit movement enforces allowance")
	var reroll_points := [1, 0]
	var reroll_use := Stratagems.use(Stratagems.command_reroll(), "SHOOTING", 0, reroll_points)
	check(reroll_use.ok and reroll_use.points[0] == 0 and reroll_use.effect == "REROLL_HIT", "command reroll spends resource")
	var no_reroll := Stratagems.use(Stratagems.command_reroll(), "SHOOTING", 0, reroll_use.points)
	check(not no_reroll.ok and no_reroll.reason == "NOT ENOUGH COMMAND POINTS", "command reroll requires points")
	var counter := Stratagems.definition("counter-offensive")
	check(counter.id == "counter_offensive" and Stratagems.validate(counter).is_empty(), "stratagem aliases resolve to registered definitions")
	var stratagem_phase_state := Replay.initial_state([], "FIGHT", 0)
	stratagem_phase_state.command_points = [2, 0]
	var counter_log: Array = []
	counter_log = CommandLog.append(counter_log, 0, "STRATAGEM", {"id": "counter_offensive", "phase": "FIGHT"})
	var counter_replay := Replay.replay(stratagem_phase_state, counter_log)
	check(counter_replay.ok and counter_replay.state.stratagem_effects.size() == 1 and counter_replay.state.stratagem_effects[0].effect == "FIGHT_NEXT", "replay records registered stratagem effects")
	var counter_models: Array = fights_first_models.duplicate(true)
	var counter_state := Replay.initial_state(counter_models, "FIGHT", 0)
	counter_state.command_points = [2, 0]
	var counter_fight_log: Array = []
	counter_fight_log = CommandLog.append(counter_fight_log, 0, "STRATAGEM", {"id": "counter_offensive", "phase": "FIGHT"})
	counter_fight_log = CommandLog.append(counter_fight_log, 0, "FIGHT", {"attacker": 0, "attacker_id": "normal_fighter_m001", "target": 2, "target_id": "first_target_m001", "weapon": "Test Blade", "damage": 1})
	var counter_fight := Replay.replay(counter_state, counter_fight_log)
	check(counter_fight.ok and counter_fight.state.models[0].fought and counter_fight.state.stratagem_effects[0].consumed, "counter offensive unlocks and consumes next fight activation")
	var reroll_state := Replay.initial_state(combat_replay_models, "SHOOTING", 0)
	reroll_state.command_points = [1, 0]
	var reroll_log: Array = []
	reroll_log = CommandLog.append(reroll_log, 0, "STRATAGEM", {"id": "command_reroll", "phase": "SHOOTING"})
	reroll_log = CommandLog.append(reroll_log, 0, "SHOOT", {"attacker": 0, "attacker_id": "attacker_m001", "target": 1, "target_id": "target_m001", "damage": 1})
	var reroll_replay := Replay.replay(reroll_state, reroll_log)
	check(reroll_replay.ok and reroll_replay.state.stratagem_effects[0].consumed, "replay consumes command reroll on the next attack")
	var source_manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sources/manifest.json"))
	check(SourceManifest.validate(source_manifest).is_empty() and source_manifest.sources.size() == 30, "PDF source manifest validates")
	var catalog_profiles: Array = [profile, {"id": "other", "display_name": "Other", "edition": 10, "faction": "other", "models": [], "weapons": []}]
	var catalog := ProfileCatalog.build(catalog_profiles)
	check(catalog.size() == 2 and catalog[profile.id].display_name == "Custodian Guard", "profile catalog indexes profiles")
	check(ProfileCatalog.filter(catalog, 11, "prototype_gold").size() == 1, "profile catalog filters edition and faction")
	check(ProfileCatalog.load_directory("res://data/units").has("custodian_guard_fixture"), "profile catalog loads unit directory")
	var tree_catalog := ProfileCatalog.load_tree("res://data/units", true)
	check(tree_catalog.size() >= 31 and tree_catalog.has("custodian_guard_fixture"), "profile catalog loads nested unit directories")
	var generated_catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/units/catalog.json"))
	check(generated_catalog.profiles.size() >= 31 and generated_catalog.profiles[0].path.begins_with("res://data/units/"), "generated profile catalog is complete")
	var pending_catalog := ProfileCatalog.load_directory("res://data/units/pending", true)
	check(pending_catalog.size() == 30 and not ProfileCatalog.is_ready(pending_catalog.values()[0]), "pending profile catalog preserves review status")
	check(ProfileCatalog.ready_only(pending_catalog).is_empty(), "pending profiles excluded from ready catalog")
	var invalid_ready := profile.duplicate(true)
	invalid_ready.import_status = "ready"
	invalid_ready.keywords = ["unsupported_keyword"]
	check(not ProfileCatalog.is_ready(invalid_ready), "ready catalog rejects structurally invalid profile")
	var nat_service := NatMapping.new()
	root.add_child(nat_service)
	var fake_nat := FakeNAT.new()
	check(not nat_service.start_mapping(80, fake_nat).is_empty() and fake_nat.added.is_empty(), "UPnP rejects reserved port before router calls")
	check(nat_service.start_mapping(24567, fake_nat).is_empty(), "UPnP starts asynchronous mapping worker")
	check(await await_nat_state(nat_service, "MAPPED"), "UPnP worker publishes mapped endpoint")
	check(fake_nat.added == [[24567, 24567, "UDP", 600]] and nat_service.status.address == "203.0.113.1", "UPnP maps only ENet UDP with finite lease")
	check(nat_service.start_mapping(24568, fake_nat) == "UPNP BUSY", "UPnP refuses overlapping mapping ownership")
	var stale_nat_generation: int = nat_service.generation
	nat_service.stop_mapping()
	check(await await_nat_state(nat_service, "CLOSED"), "UPnP closes mapping asynchronously")
	check(fake_nat.deleted == [[24567, "UDP"]], "UPnP cleanup deletes only acquired UDP mapping")
	nat_service._publish(stale_nat_generation, {"state": "MAPPED"})
	check(nat_service.status.state == "CLOSED", "late discovery callback cannot resurrect closed mapping")
	fake_nat = FakeNAT.new()
	fake_nat.discover_error = 27
	nat_service.start_mapping(24567, fake_nat)
	check(await await_nat_state(nat_service, "ERROR") and fake_nat.added.is_empty() and fake_nat.deleted.is_empty(), "UPnP discovery failure never edits router mappings")
	fake_nat = FakeNAT.new()
	fake_nat.mapping_error = 13
	nat_service.start_mapping(24567, fake_nat)
	check(await await_nat_state(nat_service, "ERROR") and fake_nat.deleted.is_empty(), "UPnP mapping conflict never deletes another mapping")
	fake_nat = FakeNAT.new()
	fake_nat.gate = Semaphore.new()
	nat_service.start_mapping(24567, fake_nat)
	nat_service.stop_mapping()
	fake_nat.gate.post()
	check(await await_nat_state(nat_service, "CLOSED") and fake_nat.added.is_empty(), "cancel during discovery prevents port mapping")
	fake_nat = FakeNAT.new()
	fake_nat.cleanup_error = 23
	nat_service.start_mapping(24567, fake_nat)
	await await_nat_state(nat_service, "MAPPED")
	nat_service.stop_mapping()
	check(await await_nat_state(nat_service, "ERROR") and nat_service.status.step == "cleanup", "UPnP reports cleanup failure without claiming port closed")
	fake_nat = FakeNAT.new()
	fake_nat.renewal_error = 23
	nat_service._renew_interval_ms = 1
	nat_service.start_mapping(24567, fake_nat)
	check(await await_nat_state(nat_service, "ERROR") and nat_service.status.step == "renewal" and fake_nat.added.size() == 2 and fake_nat.deleted.size() == 1, "UPnP failed renewal cleans owned mapping and reports failure")
	nat_service.queue_free()
	var lobby_scene = load("res://client/lobby/lobby_screen.tscn").instantiate()
	root.add_child(lobby_scene)
	await process_frame
	check(lobby_scene.status != null and lobby_scene.lobby != null, "lobby screen builds account and P2P controls")
	check(not lobby_scene.upnp_option.button_pressed and lobby_scene.nat_status != null, "lobby UPnP remains explicitly opt in")
	check(lobby_scene.directory_url != null and lobby_scene.directory_status != null and lobby_scene.room_results != null, "lobby exposes optional public room directory controls")
	var lobby_models := BattleSetup.default_models()
	check(lobby_models.size() == 20 and lobby_models[0].has("model_id") and lobby_models[0].has("weapons"), "lobby builds a complete shared prototype battle setup")
	lobby_scene.queue_free()
	var scene = load("res://client/battlefield/tabletop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.models.size() == 20, "scene starts with twenty bases")
	var ui_bridge = root.get_node_or_null("NetworkBridge")
	if ui_bridge != null:
		var prior_room: Dictionary = ui_bridge.lobby.room.duplicate(true)
		var prior_player: String = ui_bridge.lobby.player_id
		ui_bridge.lobby.room = trigger_result.room
		ui_bridge.lobby.player_id = "player_blue"
		scene.show_reaction_controls(waiting_state)
		check(scene.get_node("ReactionPanel").get_child(0).get_child_count() == 5, "responding player sees strategy target execute and pass controls")
		scene.show_reaction_controls(shot_waiting.room.session)
		check(scene.get_node("ReactionPanel").get_child(0).get_child_count() == 7, "reaction shooting panel offers shooter weapon and moved target choices")
		var filtered_ui_state: Dictionary = filtered_shot_room.session.duplicate(true)
		var ui_grant := {"id": "fixture_ui_grant", "cost": 1, "phase": "MOVEMENT", "timing": "AFTER_ENEMY_MOVE", "effect": "GRANT_ABILITY", "ability": "stealth", "duration": "PHASE", "target": "FRIENDLY_UNIT", "target_keywords": ["ELITE"]}
		filtered_ui_state.models[1].faction_stratagems.append(ui_grant)
		filtered_ui_state.reaction_window.stratagem_ids.append("fixture_ui_grant")
		scene.show_reaction_controls(filtered_ui_state)
		var reaction_box = scene.get_node("ReactionPanel").get_child(0)
		check(reaction_box.get_node("Shooters").item_count == 1 and not reaction_box.get_node("UseStrategy").disabled, "reaction UI shows eligible keyword matched shooter")
		var strategy_selector = reaction_box.get_child(1)
		strategy_selector.select(1)
		strategy_selector.item_selected.emit(1)
		check(reaction_box.get_node("Recipients").item_count == 0 and reaction_box.get_node("UseStrategy").disabled and not reaction_box.get_node("Shooters").visible, "switching strategy refreshes filters and disables missing recipient")
		strategy_selector.select(0)
		strategy_selector.item_selected.emit(0)
		check(reaction_box.get_node("Shooters").item_count == 1 and not reaction_box.get_node("UseStrategy").disabled and not reaction_box.get_node("Recipients").visible, "switching back restores shot choices without stale grant selection")
		filtered_ui_state.models[1].embarked_in = "fixture_transport"
		scene.show_reaction_controls(filtered_ui_state)
		reaction_box = scene.get_node("ReactionPanel").get_child(0)
		check(reaction_box.get_node("Shooters").item_count == 0 and reaction_box.get_node("UseStrategy").disabled, "embarked shooter absent from reaction UI")
		check(not reaction_box.get_child(reaction_box.get_child_count() - 1).disabled, "pass remains available when reaction candidates disappear")
		filtered_ui_state.models[1].erase("embarked_in")
		filtered_ui_state.models[1].reserve_status = "reserve"
		check(FactionRules.strategy_recipient_groups(filtered_ui_state.models, 1, filtered_ui_state.models[1].faction_stratagems[0]).is_empty(), "shared strategy candidates exclude reserves")
		filtered_ui_state.models[1].reserve_status = "deployed"
		filtered_ui_state.models[1].wounds = 0
		check(FactionRules.strategy_recipient_groups(filtered_ui_state.models, 1, filtered_ui_state.models[1].faction_stratagems[0]).is_empty(), "shared strategy candidates exclude destroyed models")
		scene.show_reaction_controls(passed_response.state)
		check(scene.get_node_or_null("ReactionPanel") == null, "reaction panel closes when authoritative window closes")
		ui_bridge.lobby.room = prior_room
		ui_bridge.lobby.player_id = prior_player
	check(scene.models[0].has("unit_id"), "models carry unit ids")
	check(scene.models[0].has("model_id") and not str(scene.models[0].model_id).is_empty(), "models carry stable ids")
	check(scene.phase == "MOVEMENT" and scene.active_team == 0 and TurnState.is_valid(scene.turn_state), "scene starts in gold movement phase")
	var network_fixture_session := BattleSession.create(scene.models, 11, 0, scene.terrain)
	scene.apply_network_snapshot(network_fixture_session)
	check(scene.network_active and scene.models.size() == network_fixture_session.models.size() and scene.phase == "COMMAND", "tabletop applies a verified network snapshot")
	scene.reset_table()
	check(scene.objectives.size() == 1 and scene.score == [0, 0], "scene starts with one neutral objective")
	check(scene.objective_values.size() == 1 and scene.objective_values[0] == 2, "scene loads objective point values")
	check(scene.ready_profile_count >= 1 and scene.pending_profile_count == 30, "scene reports profile catalog status")
	check(scene.pending_candidate_count == 643, "scene reports pending candidate count")
	check(scene.ready_profiles.size() == scene.ready_profile_count and scene.unit_profile.id == "custodian_guard_fixture", "scene loads ready profile catalog")
	check(scene.roster.faction == scene.unit_profile.faction, "scene applies profile faction to roster")
	check(scene.pending_profile_count == ProfileCatalog.load_tree("res://data/units/pending", true).size(), "scene counts recursive pending profile catalog")
	check(scene.fixture.weapon.name == scene.unit_profile.weapons[0].name, "scene loads profile weapon")
	check(scene.models[0].toughness == scene.unit_profile.models[0].toughness and scene.models[0].wounds == scene.unit_profile.models[0].wounds, "scene applies profile defensive stats")
	check(scene.models[0].has("leadership") and scene.models[0].has("invulnerable_save") and scene.models[0].has("weapons") and scene.models[0].has("keywords"), "scene carries expanded model metadata")
	check(scene.weapon_for_model(scene.models[0]).name == scene.unit_profile.weapons[0].name, "attacks use model weapon profile")
	scene.cycle_profile_weapon()
	check(scene.fixture.weapon.name == scene.unit_profile.weapons[0].name, "scene cycles profile weapon")
	scene.toggle_roster_panel()
	check(scene.show_roster_panel, "scene toggles roster panel")
	scene.toggle_roster_panel()
	check(scene.terrain.size() == 2, "mission terrain loads")
	check(scene.mission.id == "control_center_prototype" and scene.score_to_win == 5, "mission data loads from JSON")
	check(MissionValidation.validate(scene.mission).is_empty(), "mission data passes structural validation")
	var invalid_mission: Dictionary = scene.mission.duplicate(true)
	invalid_mission.objectives[0].points = 0
	check(MissionValidation.validate(invalid_mission).has("INVALID OBJECTIVE POINTS center"), "mission validation rejects invalid objective points")
	var invalid_terrain: Dictionary = scene.mission.duplicate(true)
	invalid_terrain.terrain[0].x = 59.0
	check(MissionValidation.validate(invalid_terrain).has("INVALID TERRAIN BOUNDS ruin_west"), "mission validation rejects terrain outside board")
	check(scene.pick(Vector2(6, 6)) == 0, "base selection")
	for i in range(scene.models.size()):
		check(Rules.placement_reason(scene.models[i].position, radius, scene.models, i).is_empty(), "initial base %d valid" % i)
	scene.selected = 0
	scene.dragging = true
	scene.preview = Vector2(7, 6)
	scene.finish_drag()
	check(scene.models[0].position == Vector2(7, 6) and is_equal_approx(scene.models[0].spent, 1.0), "legal drag committed")
	check(scene.command_log.size() == 1 and scene.command_log[0].kind == "MOVE", "move is recorded")
	scene.undo_last()
	check(scene.models[0].position == Vector2(6, 6) and is_zero_approx(scene.models[0].spent), "last move can be undone")
	scene.selected = -1
	scene.end_turn()
	check(scene.active_team == 1, "turn passes to the other side")
	check(scene.pick(Vector2(6, 6)) == 0 and scene.models[0].team != scene.active_team, "opponent base is distinguishable")
	scene.new_phase()
	check(scene.phase == "MOVEMENT", "command phase advances into movement")
	scene.models[10].position = Vector2(8, 6)
	scene.models[1].position = Vector2(12, 6)
	scene.selected = 10
	scene.enter_shooting()
	check(scene.phase == "SHOOTING" and scene.turn_state.phase_index == TurnState.phase_index("SHOOTING"), "movement can enter shooting phase")
	scene.enter_charge()
	check(scene.phase == "CHARGE" and scene.turn_state.phase_index == TurnState.phase_index("CHARGE"), "shooting can enter charge phase")
	scene.charge_selected()
	check(scene.command_log[-1].kind == "CHARGE" and scene.models[10].position.distance_to(scene.models[0].position) <= 3.0, "charge action moves into engagement")
	scene.enter_fight()
	check(scene.phase == "FIGHT" and scene.turn_state.phase_index == TurnState.phase_index("FIGHT"), "charge can enter fight phase")
	scene.command_points = [0, 1]
	scene.turn_state.command_points = [0, 1]
	scene.use_command_reroll()
	check(scene.command_points == [0, 0] and scene.turn_state.command_points == [0, 0], "command reroll syncs turn state resources")
	scene.fight_selected()
	check(scene.command_log[-1].kind == "FIGHT", "fight action records melee attack")
	scene.end_turn()
	check(scene.phase == "COMMAND", "ending turn starts command phase")
	scene.new_phase()
	scene.models[1].position = Vector2(30, 22)
	scene.end_turn()
	check(scene.score[0] == 2, "objective scores for a controlling team")
	scene.score_to_win = 2
	scene.new_phase()
	scene.end_turn()
	check(scene.message.contains("金方") and scene.message.contains("任务完成"), "victory message names the scoring team")
	scene.dragging = true
	scene.selected = 0
	scene.preview = Vector2(14, 6)
	scene.finish_drag()
	check(scene.models[0].position == Vector2(6, 6) and is_zero_approx(scene.models[0].spent), "illegal drag restores position and budget")
	scene.dragging = true
	scene.preview = Vector2(12, 6)
	scene.finish_drag()
	check(scene.models[0].position == Vector2(6, 6), "occupied destination rejected")
	scene.new_phase()
	check(is_zero_approx(scene.models[0].spent), "phase resets budget")
	scene.models[0].position = Vector2(22, 22)
	scene.score = [2, 1]
	scene.save_state()
	scene.models[0].position = Vector2(1, 1)
	scene.score = [0, 0]
	scene.load_state()
	check(scene.models[0].position.distance_to(Vector2(22, 22)) < 0.001 and int(scene.score[0]) == 2 and int(scene.score[1]) == 1, "saved state restores position and score")
	check(scene.models[0].unit_id == "custodian_guard_fixture_t0_01", "saved state restores unit id")
	check(CommandLog.validate(scene.command_log).is_empty(), "saved command log validates")
	scene.add_model(Vector2(30, 22), 1)
	check(scene.models.size() == 21 and scene.pick(Vector2(30, 22)) == 20, "placed base selectable")
	scene.models[1].unit_id = scene.models[0].unit_id
	scene.models[0].position = Vector2(6, 6)
	scene.models[1].position = Vector2(8, 6)
	scene.models[10].position = Vector2(30, 30)
	scene.selected = 0
	scene.dragging = true
	scene.preview = Vector2(7, 6)
	scene.finish_drag()
	check(scene.models[0].position == Vector2(7, 6) and scene.models[1].position == Vector2(9, 6), "unit drag moves all models")
	scene.roster.points_limit = 1200
	scene.add_roster_entry()
	check(scene.roster.units.size() == 2 and scene.models.size() == 22, "scene adds roster entry")
	scene.remove_roster_entry()
	check(scene.roster.units.size() == 1 and scene.models.size() == 20, "scene removes roster entry")
	scene.adjust_points_limit(-300)
	check(scene.roster.points_limit == 1200, "scene rejects lower points limit below total")
	scene.adjust_points_limit(-100)
	check(scene.roster.points_limit == 1100, "scene lowers points limit within total")
	scene.adjust_roster_count(-1)
	check(scene.roster.units[0].count == 9 and scene.models.size() == 18, "scene applies roster count edit")
	scene.adjust_roster_count(1)
	check(scene.roster.units[0].count == 10 and scene.models.size() == 20, "scene restores roster count edit")
	scene.save_state()
	scene.roster.units[0].count = 1
	scene.load_state()
	check(scene.roster.units[0].count == 10 and scene.roster.points_limit == 1100 and scene.unit_profile.id == "custodian_guard_fixture", "saved state restores roster and profile")
	scene.save_roster()
	scene.roster.units[0].count = 1
	scene.load_roster()
	check(scene.roster.units[0].count == 10 and scene.roster.points_limit == 1100, "roster file round trip")
	scene.save_state()
	var corrupt_save := FileAccess.open("user://open_battle_save.json", FileAccess.WRITE)
	corrupt_save.store_string(JSON.stringify({"command_log": [{"sequence": 4, "team": 0, "kind": "MOVE", "payload": {}}]}))
	corrupt_save.close()
	scene.load_state()
	check(scene.message.begins_with("对局加载失败"), "corrupt save is rejected")
	scene.save_state()
	var invalid_phase_save := FileAccess.open("user://open_battle_save.json", FileAccess.WRITE)
	invalid_phase_save.store_string(JSON.stringify({"active_team": 0, "phase": "UNKNOWN", "command_log": []}))
	invalid_phase_save.close()
	scene.load_state()
	check(scene.message.begins_with("对局加载失败"), "invalid phase save is rejected")
	scene.save_state()
	scene.reset_table()
	check(scene.models.size() == 20 and scene.selected == -1, "reset restores fixture")
	scene.terrain = []
	scene.models.clear()
	scene.add_model(Vector2(8, 8), 0, "fall_scene")
	scene.add_model(Vector2(9, 8), 1, "fall_enemy_scene")
	scene.selected = 0
	scene.preview = Vector2(6, 8)
	check(scene.preview_reason() == "ENGAGED UNIT MUST FALL BACK", "scene blocks normal movement while engaged")
	scene.fall_back_selected()
	check(scene.falling_back, "scene enters fall back mode")
	scene.dragging = true
	scene.finish_drag()
	var fall_back_last_kind := "" if scene.command_log.is_empty() else str(scene.command_log[-1].get("kind", ""))
	check(scene.models[0].fell_back and fall_back_last_kind == "FALL_BACK", "scene records fall back movement")
	scene.selected = 0
	scene.preview = Vector2(5, 8)
	check(scene.preview_reason() == "FELL BACK", "scene blocks movement after fall back")
	scene.new_phase()
	check(not scene.models[0].fell_back, "new movement phase clears fall back state")
	# Mixed movement values must constrain every member, even when the fast model is selected.
	var saved_terrain: Array = scene.terrain.duplicate(true)
	scene.terrain = []
	scene.models.clear()
	scene.add_model(Vector2(6, 6), 0, "mixed", {"movement_inches": 8.0, "base_diameter_mm": 25.4, "wounds": 4, "toughness": 9, "save_on": 2, "objective_control": 3, "weapons": [{"name": "Snapshot weapon", "range_inches": 18, "damage": 2}]})
	scene.add_model(Vector2(8, 6), 0, "mixed", {"movement_inches": 4.0, "base_diameter_mm": 25.4})
	scene.models[0].spent = 1.0
	scene.models[1].spent = 1.0
	scene.selected = 0
	scene.preview = Vector2(6, 10)
	check(scene.preview_reason() == "MOVE LIMIT EXCEEDED", "fast leader cannot exceed slower member allowance")
	check(is_equal_approx(scene.selected_unit_remaining_movement(), 3.0), "movement ring uses limiting member remaining allowance")
	scene.dragging = true
	scene.finish_drag()
	check(scene.models[0].position == Vector2(6, 6) and scene.models[1].position == Vector2(8, 6) and scene.models[0].spent == 1.0, "illegal group move leaves every member unchanged")
	scene.models[1].movement_inches = 8.0
	scene.models[1].spent = 6.0
	scene.preview = Vector2(6, 9)
	check(scene.preview_reason() == "MOVE LIMIT EXCEEDED", "group movement checks each member spent budget")
	scene.models[1].movement_inches = 4.0
	scene.models[1].spent = 1.0
	check(scene.preview_reason().is_empty(), "group can move exactly slower member remaining allowance")
	scene.dragging = true
	scene.finish_drag()
	check(scene.models[0].position == Vector2(6, 9) and scene.models[1].position == Vector2(8, 9) and scene.models[1].spent == 4.0, "legal group move updates all positions and individual budgets")
	scene.save_state()
	scene.models[0].movement_inches = 99.0
	scene.models[0].weapons = []
	scene.load_state()
	check(scene.models[0].movement_inches == 8.0 and scene.models[1].movement_inches == 4.0 and scene.models[1].spent == 4.0, "save restores individual movement allowances and spending")
	check(scene.models[0].radius == 0.5 and scene.models[0].toughness == 9 and scene.models[0].save_on == 2 and scene.models[0].objective_control == 3 and scene.weapon_for_model(scene.models[0]).name == "Snapshot weapon", "save preserves per-model geometry defense control and weapon")
	scene.selected = 0
	scene.preview = Vector2(6, 10)
	check(scene.preview_reason() == "MOVE LIMIT EXCEEDED" and is_zero_approx(scene.selected_unit_remaining_movement()), "load cannot refresh exhausted group movement budget")
	scene.models[1].unit_id = "separate"
	scene.preview = Vector2(6, 13)
	check(scene.preview_reason().is_empty(), "single model uses own eight-inch allowance instead of fixture six")
	scene.terrain = saved_terrain
	scene.reset_table()
	scene.selected = 0
	var base_movement := float(scene.models[0].movement_inches)
	scene.advance_selected()
	var advance_bonus := int(scene.models[0].advance_bonus)
	check(scene.models[0].advanced and advance_bonus >= 1 and advance_bonus <= 6 and is_equal_approx(scene.movement_for_model(scene.models[0]), base_movement + advance_bonus), "scene records advance roll and extends movement")
	check(scene.command_log[-1].kind == "ADVANCE", "scene records advance command")
	scene.new_phase()
	check(not scene.models[0].advanced and scene.models[0].advance_bonus == 0, "new movement phase clears advance state")
	scene.reset_table()
	scene.end_turn()
	scene.new_phase()
	var scene_ai_turn: Dictionary = scene.run_single_player_ai()
	check(scene_ai_turn.ok and scene.active_team == 0 and scene.phase == "COMMAND" and scene.command_log.size() > 5, "scene runs AI through authoritative single-player turn")
	var ai_reserve_models: Array = [{"model_id": "ai_reserve_m001", "unit_id": "ai_reserve", "team": 1, "position": Vector2(3, 40), "radius": 0.5, "ability_ids": ["deep_strike"], "reserve_status": "reserve", "wounds": 3}, {"model_id": "ai_enemy_m001", "unit_id": "ai_enemy", "team": 0, "position": Vector2(30, 22), "radius": 0.5, "wounds": 3}]
	var ai_reserve_state := Replay.initial_state(ai_reserve_models, "MOVEMENT", 1)
	var ai_reserve_turn := AIPlayer.play_turn(BattleSession.create(ai_reserve_models, 11, 1), 1, 77)
	var ai_reserve_deployed := false
	for ai_entry in ai_reserve_turn.commands:
		if str(ai_entry.get("kind", "")) == "DEPLOY_RESERVE":
			ai_reserve_deployed = true
	check(ai_reserve_turn.ok and ai_reserve_deployed, "single-player AI deploys deep strike reserves")
	var ai_transport_models: Array = [{"model_id": "ai_transport_m001", "unit_id": "ai_transport", "team": 1, "position": Vector2(30, 38), "radius": 1.0, "movement_inches": 8.0, "transport_capacity": 5, "wounds": 8}, {"model_id": "ai_passenger_m001", "unit_id": "ai_passenger", "team": 1, "position": Vector2(31, 38), "radius": 0.5, "wounds": 3}, {"model_id": "ai_transport_enemy_m001", "unit_id": "ai_transport_enemy", "team": 0, "position": Vector2(30, 5), "radius": 0.5, "wounds": 3}]
	var ai_transport_turn := AIPlayer.play_turn(BattleSession.create(ai_transport_models, 11, 1), 1, 81)
	var ai_embarked := false
	for ai_entry in ai_transport_turn.commands:
		if str(ai_entry.get("kind", "")) == "EMBARK":
			ai_embarked = true
	check(ai_transport_turn.ok and ai_embarked, "single-player AI embarks a nearby unit")
	var ai_scout_models: Array = [{"model_id": "ai_scout_m001", "unit_id": "ai_scout", "team": 1, "position": Vector2(30, 38), "radius": 0.5, "ability_ids": ["scout_6"], "wounds": 3}, {"model_id": "ai_scout_enemy_m001", "unit_id": "ai_scout_enemy", "team": 0, "position": Vector2(30, 5), "radius": 0.5, "wounds": 3}]
	var ai_scout_turn := AIPlayer.play_turn(BattleSession.create(ai_scout_models, 11, 1), 1, 79)
	var ai_scout_used := false
	for ai_entry in ai_scout_turn.commands:
		if str(ai_entry.get("kind", "")) == "SCOUT":
			ai_scout_used = true
	check(ai_scout_turn.ok and ai_scout_used, "single-player AI uses scout before the first turn")
	var ai_attachment_models: Array = [{"model_id": "ai_leader_m001", "unit_id": "ai_leader", "team": 1, "position": Vector2(30, 38), "radius": 0.5, "movement_inches": 6.0, "leader": true, "leader_for": ["ai_bodyguard"], "wounds": 3}, {"model_id": "ai_bodyguard_m001", "unit_id": "ai_bodyguard", "team": 1, "position": Vector2(31.2, 38), "radius": 0.5, "movement_inches": 6.0, "keywords": ["bodyguard"], "wounds": 3}, {"model_id": "ai_attachment_enemy_m001", "unit_id": "ai_attachment_enemy", "team": 0, "position": Vector2(30, 5), "radius": 0.5, "wounds": 3}]
	var ai_attachment_turn := AIPlayer.play_turn(BattleSession.create(ai_attachment_models, 11, 1), 1, 83)
	var ai_attached := false
	for ai_entry in ai_attachment_turn.commands:
		if str(ai_entry.get("kind", "")) == "ATTACH":
			ai_attached = true
	check(ai_attachment_turn.ok and ai_attached, "single-player AI attaches eligible leader")
	var ai_shock_models: Array = [{"model_id": "ai_shock_m001", "unit_id": "ai_shock", "team": 1, "position": Vector2(30, 38), "radius": 0.5, "movement_inches": 6.0, "battle_shocked": true, "can_control": false, "wounds": 3}, {"model_id": "ai_shock_enemy_m001", "unit_id": "ai_shock_enemy", "team": 0, "position": Vector2(30, 5), "radius": 0.5, "wounds": 3}]
	var ai_shock_state := BattleSession.create(ai_shock_models, 11, 1)
	ai_shock_state.command_points = [0, 1]
	var ai_shock_turn := AIPlayer.play_turn(ai_shock_state, 1, 89)
	var ai_used_bravery := false
	var ai_passed_shock := false
	for ai_entry in ai_shock_turn.commands:
		if str(ai_entry.get("kind", "")) == "STRATAGEM" and str(ai_entry.get("payload", {}).get("id", "")) == "insane_bravery":
			ai_used_bravery = true
		if str(ai_entry.get("kind", "")) == "BATTLE_SHOCK" and bool(ai_entry.get("payload", {}).get("passed", false)):
			ai_passed_shock = true
	check(ai_shock_turn.ok and ai_used_bravery and ai_passed_shock, "single-player AI clears battle shock with a stratagem")
	scene.save_state()
	scene.queue_free()
	await process_frame
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

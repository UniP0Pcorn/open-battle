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
const P2PTransport = preload("res://client/p2p_transport.gd")
const P2PLobby = preload("res://client/p2p_lobby.gd")
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
var failures := 0
var checks := 0

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + description)
	else:
		print("PASS: " + description)

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
	check(Combat.save_target(4, -1) == 3, "armor penetration modifies saves")
	check(Combat.save_target(4, -3, 4) == 2, "best invulnerable save is selected")
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
	var peer_session_id := PeerProtocol.hash_snapshot({"room_id": room.id, "mission": room.mission_id})
	var peer_snapshot := PeerProtocol.snapshot(room.id, "player_gold", peer_session_id, 1, room.session, joined_gold.reconnect_token)
	check(PeerProtocol.validate(peer_snapshot).is_empty(), "peer snapshot validates its integrity hash")
	var disconnect_result := Room.drop_connection(room, "player_gold")
	var reconnect_result := Room.reconnect(disconnect_result.room, "player_gold", joined_gold.reconnect_token, 1)
	check(disconnect_result.ok and reconnect_result.ok and reconnect_result.snapshot.state.phase == room.session.phase, "room restores a disconnected player from reconnect token")
	var command_packet := PeerProtocol.command(room.id, "player_gold", peer_session_id, 2, 1, {"sequence": 2, "team": 0, "kind": "PHASE_ADVANCE", "payload": {"from": "MOVEMENT", "to": "SHOOTING"}}, PeerProtocol.hash_snapshot(room.session))
	check(PeerProtocol.sequence_status(1, command_packet) == "NEXT", "peer command sequence advances without a gap")
	var synced := NetworkSync.host_command(room, command_packet, "player_gold")
	check(synced.ok and synced.room.session.phase == "SHOOTING", "host sync applies a verified peer command")
	var accepted_snapshot := NetworkSync.accept_snapshot(room.session, synced.snapshot)
	check(accepted_snapshot.ok and accepted_snapshot.state.phase == "SHOOTING", "client sync accepts an authoritative snapshot")
	var stale_packet := command_packet.duplicate(true)
	stale_packet.snapshot_hash = "stale"
	check(not NetworkSync.host_command(room, stale_packet, "player_gold").ok, "host sync rejects a stale peer snapshot")
	var attack_models: Array = [
		{"model_id": "net_attacker", "unit_id": "net_unit_a", "team": 0, "position": Vector2(5, 5), "radius": 0.5, "spent": 0.0, "wounds": 3, "toughness": 4, "save_on": 4, "weapons": [{"name": "net gun", "range_inches": 24.0, "attacks": 1, "hit_on": 4, "strength": 4, "damage": 1}]},
		{"model_id": "net_target", "unit_id": "net_unit_b", "team": 1, "position": Vector2(10, 5), "radius": 0.5, "spent": 0.0, "wounds": 3, "toughness": 4, "save_on": 7, "weapons": []}
	]
	var attack_room: Dictionary = Room.create("attack-room")
	attack_room.players = [{"id": "attacker", "team": 0, "ready": true}, {"id": "target", "team": 1, "ready": true}]
	attack_room.status = Room.ACTIVE
	attack_room.session = BattleSession.create(attack_models, 11, 0)
	attack_room.session.phase = "SHOOTING"
	attack_room.session.phase_index = TurnState.phase_index("SHOOTING")
	var intent_packet := PeerProtocol.command("attack-room", "attacker", "network-test", 0, -1, {"sequence": 0, "team": 0, "kind": "SHOOT", "payload": {"attacker": 0, "attacker_id": "net_attacker", "target": 1, "target_id": "net_target", "weapon": "net gun", "intent": true, "damage": 999, "hazardous_damage": 999, "feel_no_pain_rolls": [6]}}, PeerProtocol.hash_snapshot(attack_room.session))
	var intent_result := NetworkSync.host_command(attack_room, intent_packet, "attacker")
	check(intent_result.ok and intent_result.entry.payload.damage >= 0 and int(intent_result.entry.payload.damage) != 999 and int(intent_result.entry.payload.hazardous_damage) != 999 and intent_result.entry.payload.has("hazardous_damage") and not bool(intent_result.entry.payload.get("intent", false)), "host materializes network attack intent deterministically")
	var shock_room := Room.create("shock-room")
	shock_room = Room.join(shock_room, "shock_gold", 0).room
	shock_room = Room.join(shock_room, "shock_blue", 1).room
	shock_room = Room.set_ready(shock_room, "shock_gold").room
	shock_room = Room.set_ready(shock_room, "shock_blue").room
	var shock_started := Room.start(shock_room, [{"model_id": "shock_m001", "unit_id": "shock_unit", "team": 0, "position": Vector2(10, 10), "leadership": 7}, {"model_id": "shock_enemy_m001", "unit_id": "shock_enemy", "team": 1, "position": Vector2(30, 30)}])
	shock_room = shock_started.room
	var shock_session_id := PeerProtocol.hash_snapshot({"room_id": shock_room.id, "mission": shock_room.mission_id})
	var shock_packet := PeerProtocol.command(shock_room.id, "shock_gold", shock_session_id, 0, -1, {"sequence": 0, "team": 0, "kind": "BATTLE_SHOCK", "payload": {"unit_id": "shock_unit", "intent": true}}, PeerProtocol.hash_snapshot(shock_room.session))
	var network_shock_result := NetworkSync.host_command(shock_room, shock_packet, "shock_gold")
	check(network_shock_result.ok and not bool(network_shock_result.entry.payload.get("intent", false)) and network_shock_result.entry.payload.get("rolls", []).size() == 2, "host materializes network battle shock intent deterministically")
	var lobby_probe = P2PLobby.new()
	root.add_child(lobby_probe)
	await process_frame
	lobby_probe.room = room
	lobby_probe.player_id = "player_gold"
	var probe_error: String = lobby_probe.submit_command("PHASE_ADVANCE", {"from": "MOVEMENT", "to": "SHOOTING"})
	check(probe_error != "PLAYER TEAM UNKNOWN", "client lobby stamps the mapped team into command packets")
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
	check(ability_mods.cover_bonus == 1 and ability_mods.objective_control_bonus == 1 and ability_mods.hit_rerolls == 1, "ability modifiers aggregate")
	var stealth_target_abilities := UnitAbilities.modifiers(["stealth"])
	var stealth_context := WeaponRules.context({"range_inches": 24.0, "attacks": 1, "hit_on": 4}, 10.0, int(stealth_target_abilities.cover_bonus), 1)
	check(stealth_context.cover_bonus == 1, "target stealth contributes to shared cover context")
	var reroll_mods := UnitAbilities.modifiers(["reroll_wound_ones", "reroll_save_ones"])
	check(reroll_mods.wound_reroll_ones == 1 and reroll_mods.save_reroll_ones == 1, "ability reroll ones modifiers are executable")
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
	check(Combat.resolve_ranged_attack({"attacks": 0, "hit_on": 4, "strength": 4, "damage": 1}, {"toughness": 4, "save_on": 4, "cover_save_bonus": 1}, combat_rng).save_on == 5, "cover modifies save target")
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
	var lobby_scene = load("res://client/lobby/lobby_screen.tscn").instantiate()
	root.add_child(lobby_scene)
	await process_frame
	check(lobby_scene.status != null and lobby_scene.lobby != null, "lobby screen builds account and P2P controls")
	var lobby_models := BattleSetup.default_models()
	check(lobby_models.size() == 20 and lobby_models[0].has("model_id") and lobby_models[0].has("weapons"), "lobby builds a complete shared prototype battle setup")
	lobby_scene.queue_free()
	var scene = load("res://client/battlefield/tabletop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.models.size() == 20, "scene starts with twenty bases")
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

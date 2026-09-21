# SPDX-License-Identifier: AGPL-3.0-only
extends SceneTree
const Rules = preload("res://rules/movement.gd")
const Combat = preload("res://rules/combat.gd")
const ArmyValidation = preload("res://rules/army_validation.gd")
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
	check(Combat.wound_target(5, 5) == 4, "equal strength wounds on four")
	check(Combat.wound_target(10, 5) == 2, "double strength wounds on two")
	var combat_rng := RandomNumberGenerator.new()
	combat_rng.seed = 1
	var combat_result := Combat.resolve_ranged_attack({"attacks": 2, "hit_on": 3, "strength": 5, "damage": 2}, {"toughness": 5}, combat_rng)
	check(combat_result.has("hits") and combat_result.has("damage"), "combat result has hit and damage totals")
	var roster := {"points_limit": 1000, "units": [{"unit_id": "fixture", "count": 10, "points_each": 100}]}
	check(ArmyValidation.validate_roster(roster).is_empty(), "valid roster passes")
	check(ArmyValidation.total_points(roster) == 1000, "roster points total")
	roster.points_limit = 900
	check(not ArmyValidation.validate_roster(roster).is_empty(), "over-limit roster fails")
	var scene = load("res://client/battlefield/tabletop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.models.size() == 20, "scene starts with twenty bases")
	check(scene.phase == "MOVEMENT" and scene.active_team == 0, "scene starts in gold movement phase")
	check(scene.objectives.size() == 1 and scene.score == [0, 0], "scene starts with one neutral objective")
	check(scene.mission.id == "control_center_prototype" and scene.score_to_win == 5, "mission data loads from JSON")
	check(scene.pick(Vector2(6, 6)) == 0, "base selection")
	for i in range(scene.models.size()):
		check(Rules.placement_reason(scene.models[i].position, radius, scene.models, i).is_empty(), "initial base %d valid" % i)
	scene.selected = 0
	scene.dragging = true
	scene.preview = Vector2(7, 6)
	scene.finish_drag()
	check(scene.models[0].position == Vector2(7, 6) and is_equal_approx(scene.models[0].spent, 1.0), "legal drag committed")
	scene.undo_last()
	check(scene.models[0].position == Vector2(6, 6) and is_zero_approx(scene.models[0].spent), "last move can be undone")
	scene.selected = -1
	scene.end_turn()
	check(scene.active_team == 1, "turn passes to the other side")
	check(scene.pick(Vector2(6, 6)) == 0 and scene.models[0].team != scene.active_team, "opponent base is distinguishable")
	scene.enter_shooting()
	check(scene.phase == "SHOOTING", "movement can enter shooting phase")
	scene.end_turn()
	check(scene.phase == "MOVEMENT", "ending turn starts movement phase")
	scene.models[1].position = Vector2(30, 22)
	scene.end_turn()
	check(scene.score[0] == 1, "objective scores for a controlling team")
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
	scene.add_model(Vector2(30, 22), 1)
	check(scene.models.size() == 21 and scene.pick(Vector2(30, 22)) == 20, "placed base selectable")
	scene.reset_table()
	check(scene.models.size() == 20 and scene.selected == -1, "reset restores fixture")
	scene.queue_free()
	await process_frame
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

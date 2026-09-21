# SPDX-License-Identifier: AGPL-3.0-only
extends SceneTree
const Rules = preload("res://rules/movement.gd")
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
	var scene = load("res://client/battlefield/tabletop.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	check(scene.models.size() == 20, "scene starts with twenty bases")
	check(scene.pick(Vector2(6, 6)) == 0, "base selection")
	for i in range(scene.models.size()):
		check(Rules.placement_reason(scene.models[i].position, radius, scene.models, i).is_empty(), "initial base %d valid" % i)
	scene.selected = 0
	scene.dragging = true
	scene.preview = Vector2(7, 6)
	scene.finish_drag()
	check(scene.models[0].position == Vector2(7, 6) and is_equal_approx(scene.models[0].spent, 1.0), "legal drag committed")
	scene.dragging = true
	scene.preview = Vector2(14, 6)
	scene.finish_drag()
	check(scene.models[0].position == Vector2(7, 6) and is_equal_approx(scene.models[0].spent, 1.0), "illegal drag restores position and budget")
	scene.dragging = true
	scene.preview = Vector2(9, 6)
	scene.finish_drag()
	check(scene.models[0].position == Vector2(7, 6), "occupied destination rejected")
	scene.new_phase()
	check(is_zero_approx(scene.models[0].spent), "phase resets budget")
	scene.add_model(Vector2(30, 22), 1)
	check(scene.models.size() == 21 and scene.pick(Vector2(30, 22)) == 20, "placed base selectable")
	scene.reset_table()
	check(scene.models.size() == 20 and scene.selected == -1, "reset restores fixture")
	scene.queue_free()
	await process_frame
	print("RESULT: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

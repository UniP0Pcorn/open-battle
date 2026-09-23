# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Structural validation for data-driven missions before they reach the scene.

const Movement = preload("res://rules/movement.gd")

static func validate(mission: Dictionary, board_size: Vector2 = Movement.BOARD_SIZE) -> Array[String]:
	var errors: Array[String] = []
	for field in ["id", "display_name", "score_to_win", "control_radius_inches", "deployment_depth_inches", "objectives", "terrain"]:
		if not mission.has(field):
			errors.append("MISSING " + field.to_upper())
	if not errors.is_empty():
		return errors
	if str(mission.get("id", "")).is_empty() or str(mission.get("display_name", "")).is_empty():
		errors.append("EMPTY ID OR NAME")
	if int(mission.get("score_to_win", 0)) <= 0:
		errors.append("INVALID SCORE TO WIN")
	if float(mission.get("control_radius_inches", 0.0)) <= 0.0:
		errors.append("INVALID CONTROL RADIUS")
	var depth := float(mission.get("deployment_depth_inches", 0.0))
	if depth <= 0.0 or depth * 2.0 > board_size.y:
		errors.append("INVALID DEPLOYMENT DEPTH")
	errors.append_array(_validate_objectives(mission.get("objectives", []), board_size))
	errors.append_array(_validate_terrain(mission.get("terrain", []), board_size))
	return errors

static func _validate_objectives(objectives: Variant, board_size: Vector2) -> Array[String]:
	var errors: Array[String] = []
	if not (objectives is Array) or objectives.is_empty():
		return ["NO OBJECTIVES"]
	var ids: Dictionary = {}
	for index in range(objectives.size()):
		var objective = objectives[index]
		if not (objective is Dictionary):
			errors.append("INVALID OBJECTIVE %d" % index)
			continue
		var objective_id := str(objective.get("id", "objective_%d" % index))
		if objective_id.is_empty() or ids.has(objective_id):
			errors.append("DUPLICATE OBJECTIVE ID " + objective_id)
		ids[objective_id] = true
		var position: Variant = objective.get("position_inches", [])
		if not _point_inside(position, board_size):
			errors.append("INVALID OBJECTIVE POSITION " + objective_id)
		if int(objective.get("points", 0)) <= 0:
			errors.append("INVALID OBJECTIVE POINTS " + objective_id)
	return errors

static func _validate_terrain(terrain: Variant, board_size: Vector2) -> Array[String]:
	var errors: Array[String] = []
	if not (terrain is Array):
		return ["INVALID TERRAIN"]
	var ids: Dictionary = {}
	for index in range(terrain.size()):
		var obstacle = terrain[index]
		if not (obstacle is Dictionary):
			errors.append("INVALID TERRAIN %d" % index)
			continue
		var terrain_id := str(obstacle.get("id", "terrain_%d" % index))
		if terrain_id.is_empty() or ids.has(terrain_id):
			errors.append("DUPLICATE TERRAIN ID " + terrain_id)
		ids[terrain_id] = true
		var x := float(obstacle.get("x", -1.0))
		var y := float(obstacle.get("y", -1.0))
		var width := float(obstacle.get("width", 0.0))
		var height := float(obstacle.get("height", 0.0))
		if width <= 0.0 or height <= 0.0 or x < 0.0 or y < 0.0 or x + width > board_size.x or y + height > board_size.y:
			errors.append("INVALID TERRAIN BOUNDS " + terrain_id)
		if int(obstacle.get("cover_bonus", 0)) < 0:
			errors.append("INVALID TERRAIN COVER " + terrain_id)
	return errors

static func _point_inside(value: Variant, board_size: Vector2) -> bool:
	if not (value is Array) or value.size() != 2:
		return false
	var x := float(value[0])
	var y := float(value[1])
	return is_finite(x) and is_finite(y) and x >= 0.0 and y >= 0.0 and x <= board_size.x and y <= board_size.y

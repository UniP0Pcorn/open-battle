# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Rectangular terrain primitives in inch coordinates.

static func rect(terrain: Dictionary) -> Rect2:
	return Rect2(Vector2(float(terrain.get("x", 0.0)), float(terrain.get("y", 0.0))), Vector2(float(terrain.get("width", 0.0)), float(terrain.get("height", 0.0))))

static func circle_reason(position: Vector2, radius: float, terrain: Array) -> String:
	for obstacle in terrain:
		var area := rect(obstacle)
		var closest := Vector2(clampf(position.x, area.position.x, area.end.x), clampf(position.y, area.position.y, area.end.y))
		if position.distance_to(closest) < radius:
			return "TERRAIN BLOCKED"
	return ""

static func path_reason(origin: Vector2, destination: Vector2, radius: float, terrain: Array) -> String:
	var travel := origin.distance_to(destination)
	if travel <= 0.00001:
		return ""
	var steps := maxi(1, ceili(travel / maxf(radius, 0.25)))
	for step in range(1, steps + 1):
		var point := origin.lerp(destination, float(step) / float(steps))
		if not circle_reason(point, radius, terrain).is_empty():
			return "TERRAIN BLOCKED"
	return ""

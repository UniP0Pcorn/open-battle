# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Conservative sampled line-of-sight check for rectangular obscuring terrain.

static func blocked(origin: Vector2, destination: Vector2, terrain: Array, sample_inches: float = 0.25) -> bool:
	var distance := origin.distance_to(destination)
	if distance <= 0.00001:
		return false
	var steps := maxi(1, ceili(distance / maxf(sample_inches, 0.05)))
	for step in range(1, steps):
		var point := origin.lerp(destination, float(step) / float(steps))
		for obstacle in terrain:
			if terrain_rect(obstacle).has_point(point):
				return true
	return false

static func cover_bonus(origin: Vector2, destination: Vector2, terrain: Array, sample_inches: float = 0.25) -> int:
	var distance := origin.distance_to(destination)
	if distance <= 0.00001:
		return 0
	var steps := maxi(1, ceili(distance / maxf(sample_inches, 0.05)))
	var bonus := 0
	for step in range(1, steps):
		var point := origin.lerp(destination, float(step) / float(steps))
		for obstacle in terrain:
			if terrain_rect(obstacle).has_point(point):
				bonus = maxi(bonus, int(obstacle.get("cover_bonus", 0)))
	return bonus

static func terrain_rect(obstacle: Dictionary) -> Rect2:
	return Rect2(Vector2(float(obstacle.get("x", 0.0)), float(obstacle.get("y", 0.0))), Vector2(float(obstacle.get("width", 0.0)), float(obstacle.get("height", 0.0))))

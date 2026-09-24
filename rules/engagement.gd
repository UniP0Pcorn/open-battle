# SPDX-License-Identifier: AGPL-3.0-only
extends RefCounted
## Base-to-base engagement geometry in inches.

const EPSILON := 0.0001

static func separation(attacker: Dictionary, target: Dictionary) -> float:
	if not attacker.has("position") or not target.has("position"):
		return INF
	var center_distance: float = _position_of(attacker).distance_to(_position_of(target))
	return center_distance - float(attacker.get("radius", attacker.get("base_radius", 0.0))) - float(target.get("radius", target.get("base_radius", 0.0)))

static func in_engagement(attacker: Dictionary, target: Dictionary, engagement_range: float = 1.0) -> bool:
	return separation(attacker, target) <= engagement_range + EPSILON

static func _position_of(model: Dictionary) -> Vector2:
	var position: Variant = model.get("position", Vector2.ZERO)
	if position is Vector2:
		return position
	if position is Array and position.size() == 2:
		return Vector2(float(position[0]), float(position[1]))
	return Vector2.ZERO

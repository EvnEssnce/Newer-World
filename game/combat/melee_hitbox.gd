class_name MeleeHitbox
## Server-side melee hit test: the attack's box hitbox against a target's
## upright capsule. Pure math (no physics queries), so it's deterministic and
## unit tested (tests/test_melee_hitbox.gd).
##
## The box starts at the attacker's center and reaches hitbox_range forward
## (forward is -Z rotated by yaw), hitbox_width wide, from the attacker's feet up
## hitbox_height.


static func hits(attacker_pos: Vector3, yaw: float, attack: AttackParams,
		target_pos: Vector3, target_radius: float, target_height: float) -> bool:
	# Vertical: the capsule's [feet, top] must overlap the box's [feet, top].
	if target_pos.y > attacker_pos.y + attack.hitbox_height:
		return false
	if target_pos.y + target_height < attacker_pos.y:
		return false
	# Horizontal: rotate the target into the attacker's space (forward = -Z), then
	# check the distance from the capsule's center to the box's rectangle.
	var offset := target_pos - attacker_pos
	var local_x := offset.x * cos(yaw) - offset.z * sin(yaw)
	var local_z := offset.x * sin(yaw) + offset.z * cos(yaw)
	var half_width := attack.hitbox_width / 2.0
	var closest := Vector2(
			clampf(local_x, -half_width, half_width),
			clampf(local_z, -attack.hitbox_range, 0.0))
	return Vector2(local_x, local_z).distance_to(closest) <= target_radius

class_name MeleeHitbox
## Server-side melee hit test: the attack's hitbox against a target's upright
## capsule. Pure math (no physics queries), so it's deterministic and unit tested
## (tests/test_melee_hitbox.gd).
##
## Box (SHAPE_BOX): starts at the attacker's center and reaches hitbox_range
## forward (forward is -Z rotated by yaw), hitbox_width wide, from the attacker's
## feet up hitbox_height. Radial (SHAPE_RADIAL): a cylinder of radius
## hitbox_range around the attacker, hitbox_height tall, ignoring facing; with
## hitbox_arc (a cone, Seismic Slam), only that wide in front.


static func hits(attacker_pos: Vector3, yaw: float, attack: AttackParams,
		target_pos: Vector3, target_radius: float, target_height: float) -> bool:
	if attack.shape == AttackParams.SHAPE_NONE:
		return false
	# Vertical: the capsule's [feet, top] must overlap the hitbox's [feet, top].
	if target_pos.y > attacker_pos.y + attack.hitbox_height:
		return false
	if target_pos.y + target_height < attacker_pos.y:
		return false
	if attack.shape == AttackParams.SHAPE_RADIAL:
		# A circle of radius hitbox_range around the attacker, all the way round.
		var flat := Vector2(target_pos.x - attacker_pos.x, target_pos.z - attacker_pos.z)
		if flat.length() > attack.hitbox_range + target_radius:
			return false
		# A cone (hitbox_arc > 0): the target's center must be inside the arc.
		return attack.hitbox_arc <= 0.0 or is_in_front(attacker_pos, yaw, target_pos,
				attack.hitbox_arc)
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


## Shield Wall: true if `other_pos` stands inside the box straight behind a
## player at `pos` facing `yaw`: from their center back `depth` meters,
## `width` meters wide (centered), ignoring height. Pure XZ math.
static func is_behind(pos: Vector3, yaw: float, other_pos: Vector3, depth: float,
		width: float) -> bool:
	var offset := other_pos - pos
	# Same frame as hits(): forward is local -Z, so behind is local +Z.
	var local_x := offset.x * cos(yaw) - offset.z * sin(yaw)
	var local_z := offset.x * sin(yaw) + offset.z * cos(yaw)
	return local_z >= 0.0 and local_z <= depth and absf(local_x) <= width / 2.0


## True if `other_pos` is within the `arc` (full width, radians) in front of a
## player at `pos` facing `yaw`. Used for blocking: only frontal hits are blocked.
static func is_in_front(pos: Vector3, yaw: float, other_pos: Vector3, arc: float) -> bool:
	var to_other := Vector2(other_pos.x - pos.x, other_pos.z - pos.z)
	if to_other.is_zero_approx():
		return true  # standing inside each other: count it as in front
	var forward := Vector2(-sin(yaw), -cos(yaw))
	return absf(forward.angle_to(to_other)) <= arc / 2.0 + 0.0001

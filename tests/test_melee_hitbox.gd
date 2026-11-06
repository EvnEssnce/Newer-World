extends TestCase
## MeleeHitbox: a box 2 m forward, 1 m wide, 2 m tall (or, radial, a circle of
## 2 m radius, 2 m tall) against a 0.4 m radius, 1.8 m tall capsule.

const RADIUS := 0.4
const HEIGHT := 1.8

var attack: AttackParams


func before_each() -> void:
	attack = AttackParams.new()
	attack.hitbox_range = 2.0
	attack.hitbox_width = 1.0
	attack.hitbox_height = 2.0


func _hits(target: Vector3, yaw: float = 0.0) -> bool:
	return MeleeHitbox.hits(Vector3.ZERO, yaw, attack, target, RADIUS, HEIGHT)


func test_hits_target_in_front() -> void:
	assert_true(_hits(Vector3(0.0, 0.0, -1.5)))


func test_misses_target_behind() -> void:
	assert_false(_hits(Vector3(0.0, 0.0, 1.0)))


func test_reach_includes_target_radius() -> void:
	assert_true(_hits(Vector3(0.0, 0.0, -2.3)), "capsule edge inside the box")
	assert_false(_hits(Vector3(0.0, 0.0, -2.5)), "capsule edge past the box")


func test_width_includes_target_radius() -> void:
	assert_true(_hits(Vector3(0.85, 0.0, -1.0)))
	assert_false(_hits(Vector3(1.0, 0.0, -1.0)))


func test_follows_attacker_facing() -> void:
	var facing_right := PlayerState.yaw_for_direction(Vector2.RIGHT)
	assert_true(_hits(Vector3(1.5, 0.0, 0.0), facing_right), "in front after turning")
	assert_false(_hits(Vector3(0.0, 0.0, -1.5), facing_right), "now to the left")


func test_radial_hits_all_around() -> void:
	attack.shape = AttackParams.SHAPE_RADIAL
	for direction: Vector3 in [Vector3.FORWARD, Vector3.BACK, Vector3.LEFT, Vector3.RIGHT]:
		assert_true(_hits(direction * 1.5), "at %s" % direction)
	assert_true(_hits(Vector3(1.0, 0.0, 1.0)), "diagonal behind")


func test_radial_ignores_facing() -> void:
	attack.shape = AttackParams.SHAPE_RADIAL
	assert_true(_hits(Vector3(0.0, 0.0, 1.5), 0.0))
	assert_true(_hits(Vector3(0.0, 0.0, 1.5), PI / 2.0))


func test_radial_reach_includes_target_radius() -> void:
	attack.shape = AttackParams.SHAPE_RADIAL
	assert_true(_hits(Vector3(2.35, 0.0, 0.0)), "capsule edge inside the circle")
	assert_false(_hits(Vector3(2.45, 0.0, 0.0)), "capsule edge outside")
	assert_false(_hits(Vector3(1.8, 0.0, 1.8)), "diagonal: 2.55 m away")


func test_radial_vertical_overlap() -> void:
	attack.shape = AttackParams.SHAPE_RADIAL
	assert_true(_hits(Vector3(1.0, 1.5, 0.0)), "feet below the top")
	assert_false(_hits(Vector3(1.0, 2.5, 0.0)), "entirely above")
	assert_false(_hits(Vector3(1.0, -2.0, 0.0)), "entirely below")


func test_no_shape_never_hits() -> void:
	attack.shape = AttackParams.SHAPE_NONE
	assert_false(_hits(Vector3(0.0, 0.0, -1.0)))
	assert_false(_hits(Vector3.ZERO))


func test_is_behind_shield_wall_box() -> void:
	# Facing -Z (yaw 0): behind is +Z. Box 2.5 m deep, 1.8 m wide.
	var at := Vector3(10.0, 0.0, 5.0)
	assert_true(MeleeHitbox.is_behind(at, 0.0, at + Vector3(0.0, 0.0, 1.0), 2.5, 1.8))
	assert_true(MeleeHitbox.is_behind(at, 0.0, at + Vector3(0.85, 0.0, 2.4), 2.5, 1.8), "corner")
	assert_false(MeleeHitbox.is_behind(at, 0.0, at + Vector3(0.0, 0.0, -1.0), 2.5, 1.8), "in front")
	assert_false(MeleeHitbox.is_behind(at, 0.0, at + Vector3(0.0, 0.0, 2.6), 2.5, 1.8), "too far back")
	assert_false(MeleeHitbox.is_behind(at, 0.0, at + Vector3(1.0, 0.0, 1.0), 2.5, 1.8), "off to the side")
	# Facing +X (yaw -90 deg): behind is -X.
	var yaw := -PI / 2.0
	assert_true(MeleeHitbox.is_behind(at, yaw, at + Vector3(-1.5, 0.0, 0.0), 2.5, 1.8))
	assert_false(MeleeHitbox.is_behind(at, yaw, at + Vector3(1.5, 0.0, 0.0), 2.5, 1.8))
	assert_false(MeleeHitbox.is_behind(at, yaw, at + Vector3(0.0, 0.0, 1.5), 2.5, 1.8))


func test_vertical_overlap() -> void:
	assert_true(_hits(Vector3(0.0, 1.5, -1.0)), "feet below the box top")
	assert_false(_hits(Vector3(0.0, 2.5, -1.0)), "entirely above")
	assert_false(_hits(Vector3(0.0, -2.0, -1.0)), "entirely below")


# --- Aimed cone (Plumage Flash): the axis follows the aim, pitch included ---

func _cone_attack() -> AttackParams:
	var cone := AttackParams.new()
	cone.shape = AttackParams.SHAPE_RADIAL
	cone.hitbox_range = 6.0
	cone.hitbox_arc = deg_to_rad(70.0)
	cone.hitbox_height = 2.2
	cone.aimed_cone = true
	return cone


func _cone_touches(cone: AttackParams, direction: Vector3, target: Vector3) -> bool:
	var origin := Vector3(0.0, 1.4, 0.0)
	return MeleeHitbox.touches(Vector3.ZERO, 0.0, cone, PackedVector3Array([origin,
			direction.normalized()]), target, RADIUS, HEIGHT)


func test_aimed_cone_level_hits_in_front_only() -> void:
	var cone := _cone_attack()
	var ahead := Vector3(0.0, 0.0, -1.0)
	assert_true(_cone_touches(cone, ahead, Vector3(0.0, 0.0, -4.0)), "in front")
	assert_true(_cone_touches(cone, ahead, Vector3(2.0, 0.0, -4.0)), "inside the 35 degree half arc")
	assert_false(_cone_touches(cone, ahead, Vector3(5.0, 0.0, -2.0)), "off to the side")
	assert_false(_cone_touches(cone, ahead, Vector3(0.0, 0.0, 4.0)), "behind")
	assert_false(_cone_touches(cone, ahead, Vector3(0.0, 0.0, -7.0)), "past its range")


func test_aimed_cone_reaches_a_hovering_target_when_aimed_up() -> void:
	var cone := _cone_attack()
	var hovering := Vector3(0.0, 4.0, -3.0)  # feet 4 m up: over the level cone's 2.2 m
	assert_false(MeleeHitbox.hits(Vector3.ZERO, 0.0, cone, hovering, RADIUS, HEIGHT),
			"the level cone misses it")
	assert_false(_cone_touches(cone, Vector3(0.0, 0.0, -1.0), hovering),
			"aimed level, it misses too")
	var up := Vector3(0.0, 4.4, -3.0) - Vector3(0.0, 1.4, 0.0)  # at its middle
	assert_true(_cone_touches(cone, up, hovering), "aimed up at it, it hits")


func test_aimed_cone_aimed_up_misses_the_ground_in_front() -> void:
	var cone := _cone_attack()
	assert_false(_cone_touches(cone, Vector3(0.0, 1.0, 0.0), Vector3(0.0, 0.0, -4.0)),
			"aimed straight up, a target ahead on the ground is outside")


func test_aimed_cone_without_a_line_is_the_level_cone() -> void:
	var cone := _cone_attack()
	assert_true(MeleeHitbox.touches(Vector3.ZERO, 0.0, cone, PackedVector3Array(),
			Vector3(0.0, 0.0, -4.0), RADIUS, HEIGHT))
	assert_false(MeleeHitbox.touches(Vector3.ZERO, 0.0, cone, PackedVector3Array(),
			Vector3(0.0, 4.0, -3.0), RADIUS, HEIGHT))

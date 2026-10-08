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


func test_vertical_overlap() -> void:
	assert_true(_hits(Vector3(0.0, 1.5, -1.0)), "feet below the box top")
	assert_false(_hits(Vector3(0.0, 2.5, -1.0)), "entirely above")
	assert_false(_hits(Vector3(0.0, -2.0, -1.0)), "entirely below")

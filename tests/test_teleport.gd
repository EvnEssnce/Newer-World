extends TestCase
## Teleport abilities (teleport=true: Blink, Ashstep): the "input_forward"
## direction, the instant move through PlayerMovement (full distance, stopping
## at a wall, settling onto lower ground, once only, root), and how clients
## spot a teleport between two snapshots. Fixed params and a small physics
## scene, not the data files.

const Q := PlayerState.BUTTON_ABILITY_1
const DELTA := 1.0 / 60.0

var params: PlayerParams
var state: PlayerState
var blink: AbilityParams
var _nodes: Array[Node] = []


func before_each() -> void:
	params = PlayerParams.new()
	params.move_speed = 6.0
	params.ground_acceleration = 60.0
	params.ground_deceleration = 50.0
	params.air_acceleration = 12.0
	params.gravity = 18.0
	params.jump_velocity = 6.0
	params.turn_speed = TAU
	params.max_stamina = 100.0
	params.ability_buffer_ticks = 4
	var weapon := params.default_weapon
	weapon.attack_turn_speed = TAU
	blink = AbilityParams.new()
	blink.id = "blink"
	blink.windup_ticks = 1
	blink.active_ticks = 3
	blink.recovery_ticks = 6
	blink.move_multiplier = 0.0
	blink.cooldown_ticks = 30
	blink.shape = AttackParams.SHAPE_NONE
	blink.dash_from_input = true
	blink.dash_input_forward = true
	blink.teleport_distance = 7.0
	blink.teleport_tick = 0
	weapon.abilities = [blink]
	state = PlayerState.new()
	state.stamina = params.max_stamina
	state.set_loadout(PackedStringArray(), PackedInt32Array([0, -1, -1, -1, -1, -1]))


## Frees this test's physics nodes (the runner has no after_each).
func _cleanup() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.free()
	_nodes.clear()


# --- Direction ---

func test_input_forward_goes_the_way_you_move() -> void:
	var dir := PlayerState.dash_input_direction(Vector2(0.0, 1.0), 0.5, true)
	assert_true(dir.is_equal_approx(Vector2(0.0, 1.0)), str(dir))


func test_input_forward_goes_forward_with_no_input() -> void:
	var dir := PlayerState.dash_input_direction(Vector2.ZERO, 0.5, true)
	assert_true(dir.is_equal_approx(PlayerState.forward(0.5)), str(dir))


func test_plain_input_dash_still_goes_backward_with_no_input() -> void:
	var dir := PlayerState.dash_input_direction(Vector2.ZERO, 0.5, false)
	assert_true(dir.is_equal_approx(-PlayerState.forward(0.5)), "Vault: %s" % dir)


func test_teleport_ability_faces_forward_with_no_input() -> void:
	state.step(Vector2.ZERO, Q, 0.5, true, params, DELTA)
	assert_true(state.is_using_ability())
	assert_true(state.ability_dir.is_equal_approx(PlayerState.forward(0.5)), str(state.ability_dir))
	assert_almost(state.yaw, 0.5, 0.0001, "faces the aim")


func test_teleport_is_not_a_dash() -> void:
	assert_true(blink.is_teleport())
	assert_true(blink.moves_user())
	state.step(Vector2.ZERO, Q, 0.0, true, params, DELTA)
	assert_false(state.is_dashing(params), "no velocity burst")


# --- Physics ---

## A box of the given size centered at `center`, on the world layer.
func _box(center: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	body.position = center
	_add(body)
	return body


func _player(at: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.4
	capsule.height = 1.8
	shape.shape = capsule
	body.add_child(shape)
	body.collision_layer = 2
	body.collision_mask = 1
	body.position = at
	_add(body)
	return body


func _add(node: Node) -> void:
	(Engine.get_main_loop() as SceneTree).root.add_child(node)
	_nodes.append(node)


## A player standing on a flat floor (top at y = 0), settled onto it.
func _standing_player() -> CharacterBody3D:
	_box(Vector3(0.0, -0.5, 0.0), Vector3(60.0, 1.0, 60.0))
	var body := _player(Vector3(0.0, 0.95, 0.0))
	for i in 5:
		PlayerMovement.step(body, state, Vector2.ZERO, 0, 0.0, params, DELTA)
	assert_true(state.on_floor, "settled on the floor first")
	return body


func test_teleport_moves_the_whole_distance_in_one_step() -> void:
	var body := _standing_player()
	var start := body.global_position
	PlayerMovement.step(body, state, Vector2.ZERO, Q, 0.0, params, DELTA)  # yaw 0 faces -Z
	var moved := body.global_position - start
	assert_almost(-moved.z, 7.0, 0.05, "7 m forward at once: %s" % moved)
	assert_almost(moved.x, 0.0, 0.01, "no sideways drift")
	assert_almost(moved.y, 0.0, 0.05, "still on the ground")
	assert_true(state.on_floor, "on the floor after it")
	for i in 9:
		PlayerMovement.step(body, state, Vector2.ZERO, 0, 0.0, params, DELTA)
	assert_almost(-(body.global_position - start).z, 7.0, 0.1, "only once, no sliding on")
	_cleanup()


func test_teleport_follows_the_movement_input() -> void:
	var body := _standing_player()
	var start := body.global_position
	PlayerMovement.step(body, state, Vector2(1.0, 0.0), Q, 0.0, params, DELTA)
	var moved := body.global_position - start
	assert_true(moved.x > 6.9, "teleported along +X: %s" % moved)
	_cleanup()


func test_teleport_stops_short_of_a_wall() -> void:
	var body := _standing_player()
	# A wall 4 m ahead (its near face at z = -4), much thicker than the body.
	_box(Vector3(0.0, 2.0, -5.0), Vector3(10.0, 4.0, 2.0))
	PlayerMovement.step(body, state, Vector2.ZERO, Q, 0.0, params, DELTA)
	var z := body.global_position.z
	assert_true(z > -4.0 + 0.35, "stopped in front of the wall: z %s" % z)
	assert_true(z < -3.0, "got most of the way there: z %s" % z)
	_cleanup()


func test_teleport_settles_onto_lower_ground() -> void:
	# Floor top y = 0 near the start; from z = -3 on, a floor 0.6 m lower.
	_box(Vector3(0.0, -0.5, 10.0), Vector3(20.0, 1.0, 26.0))
	_box(Vector3(0.0, -1.1, -15.0), Vector3(20.0, 1.0, 24.0))
	var body := _player(Vector3(0.0, 0.95, 0.0))
	for i in 5:
		PlayerMovement.step(body, state, Vector2.ZERO, 0, 0.0, params, DELTA)
	assert_true(state.on_floor)
	var start := body.global_position
	PlayerMovement.step(body, state, Vector2.ZERO, Q, 0.0, params, DELTA)
	var moved := body.global_position - start
	assert_almost(moved.y, -0.6, 0.06, "down onto the lower floor: %s" % moved)
	assert_true(state.on_floor, "on the floor, not falling")
	_cleanup()


func test_teleport_in_the_air_stays_in_the_air() -> void:
	var body := _player(Vector3(0.0, 20.0, 0.0))
	state.on_floor = false
	var start := body.global_position
	PlayerMovement.step(body, state, Vector2.ZERO, Q, 0.0, params, DELTA)
	var moved := body.global_position - start
	assert_almost(-moved.z, 7.0, 0.05, "full distance")
	assert_true(moved.y <= 0.0 and moved.y > -0.1, "no snap down, just a tick of fall: %s" % moved)
	_cleanup()


func test_rooted_player_does_not_teleport() -> void:
	var body := _standing_player()
	var start := body.global_position
	# A root status: walking/dashing stopped (PlayerState.can_move).
	var defs := StatusDefs.new()
	var root := StatusDef.new()
	root.id = "root"
	root.stops_movement = true
	root.affects = StatusDef.AFFECTS_SIM
	root.duration_ticks = 60
	root.max_stacks = 1
	defs.add(root)
	params.statuses = defs
	state.statuses.apply(defs, defs.index_of("root"), 1)
	PlayerMovement.step(body, state, Vector2.ZERO, Q, 0.0, params, DELTA)
	assert_true(state.is_using_ability(), "the ability still starts")
	assert_true(body.global_position.distance_to(start) < 0.1, "but doesn't move")
	_cleanup()


# --- Clients: spotting a teleport between snapshots ---

func test_ticks_since_teleport_between_two_views() -> void:
	blink.teleport_tick = 2
	state.step(Vector2.ZERO, Q, 0.0, true, params, DELTA)  # tick 0
	var before := state.copy()
	assert_eq(state.ticks_since_teleport(null, params), -1, "not yet")
	state.step(Vector2.ZERO, 0, 0.0, true, params, DELTA)
	state.step(Vector2.ZERO, 0, 0.0, true, params, DELTA)
	state.step(Vector2.ZERO, 0, 0.0, true, params, DELTA)  # tick 3
	assert_eq(state.ticks_since_teleport(before, params), 1, "one tick ago")
	var after := state.copy()
	state.step(Vector2.ZERO, 0, 0.0, true, params, DELTA)
	assert_eq(state.ticks_since_teleport(after, params), -1, "already seen")
	var idle := PlayerState.new()
	assert_eq(state.ticks_since_teleport(idle, params), 2, "started after an idle view")

extends TestCase
## Physics side of a player step, using a real CharacterBody3D in empty space
## (no floor), so the player is always airborne.

const DODGE := PlayerState.BUTTON_DODGE
const DELTA := 1.0 / 60.0
const TICKS := 20

var params: PlayerParams


func before_each() -> void:
	params = PlayerParams.new()
	params.move_speed = 6.0
	params.air_acceleration = 12.0
	params.gravity = 18.0
	params.turn_speed = TAU
	params.max_stamina = 100.0
	params.dodge_stamina_cost = 30.0
	params.dodge_ticks = 30
	params.dodge_speed = 9.0
	params.max_air_dodges = 1


## Simulates a player launched upward, pressing `buttons` on the first tick.
## Returns [position, velocity] after TICKS ticks.
func _airborne_run(buttons: int) -> Array:
	var body := CharacterBody3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(body)
	body.velocity = Vector3(0.0, 5.0, 0.0)
	var state := PlayerState.new()
	state.stamina = params.max_stamina
	for i in TICKS:
		PlayerMovement.step(body, state, Vector2.RIGHT, buttons if i == 0 else 0, 0.0, params, DELTA)
	var result := [body.global_position, body.velocity]
	body.free()
	return result


func test_air_dodge_keeps_vertical_motion() -> void:
	var plain := _airborne_run(0)
	var dodged := _airborne_run(DODGE)
	assert_almost(dodged[1].y, plain[1].y, 0.0001, "vertical velocity")
	assert_almost(dodged[0].y, plain[0].y, 0.0001, "height")


func test_air_dodge_sets_horizontal_speed() -> void:
	var dodged := _airborne_run(DODGE)
	var horizontal := Vector2(dodged[1].x, dodged[1].z)
	assert_almost(horizontal.length(), params.dodge_speed, 0.0001)

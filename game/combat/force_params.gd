class_name ForceParams
extends RefCounted
## One attack's forced movement (the FORCE tag): how far a hit pushes, pulls or
## launches its target. Built from the force_* keys of an attack section
## (data/weapon_<id>.cfg, data/enemy_<kind>.cfg); tests build their own. Shared
## limits (max distance and height, pull gap) come from data/combat.cfg [force]
## through PlayerParams.
##
## The server turns it into a ForcedMotion on the target (displacement(),
## launch_speed(), ticks()); the motion itself is simulated by PlayerMovement
## (players, predicted) or Enemy (server only). Pure math, unit tested
## (tests/test_forced_movement.gd).

## Knockback: away from the attacker (its facing if they overlap).
const DIRECTION_AWAY := 0
## Pull: toward the attacker, stopping pull_gap short of them.
const DIRECTION_TOWARD := 1
## Push along the attacker's facing (a shove "forward", whatever the angle).
const DIRECTION_FORWARD := 2

var direction := DIRECTION_AWAY
## Horizontal meters moved.
var distance := 0.0
## Launch peak height, meters. 0 = no launch.
var height := 0.0
## Ticks the push lasts (the launch's airtime instead, if that's longer).
var duration_ticks := 1
## Only moves a target that was already staggered before this hit (Rising Cut).
var needs_stagger := false


## The attack section's force, or null if it has none (no force_* keys, or
## distance and height both 0).
static func from_tuning(file: String, section: String, tps: float) -> ForceParams:
	var distance: float = Tuning.get_optional(file, section, "force_distance", 0.0)
	var height: float = Tuning.get_optional(file, section, "force_height", 0.0)
	if distance <= 0.0 and height <= 0.0:
		return null
	var f := ForceParams.new()
	f.direction = direction_from_name(Tuning.get_optional(file, section, "force_direction", "away"))
	f.distance = maxf(0.0, distance)
	f.height = maxf(0.0, height)
	f.duration_ticks = maxi(1, roundi(Tuning.get_optional(file, section, "force_duration", 0.3) * tps))
	f.needs_stagger = Tuning.get_optional(file, section, "force_needs_stagger", false)
	return f


static func direction_from_name(direction_name: String) -> int:
	match direction_name:
		"away":
			return DIRECTION_AWAY
		"toward":
			return DIRECTION_TOWARD
		"forward":
			return DIRECTION_FORWARD
	push_error("ForceParams: unknown force_direction \"%s\"" % direction_name)
	return DIRECTION_AWAY


## A displacement made `bonus` (fraction) longer, capped at max_distance
## (Tempest Wings' "force_distance" passives). A bonus of 0 or less leaves it.
static func scaled(moved: Vector2, bonus: float, max_distance: float) -> Vector2:
	if bonus <= 0.0:
		return moved
	return (moved * (1.0 + bonus)).limit_length(maxf(moved.length(), max_distance))


## World-space XZ meters a target at target_pos is moved by an attacker at
## attacker_pos facing attacker_yaw. Capped at max_distance; a pull never takes
## the target closer than pull_gap (and never pushes it away).
func displacement(attacker_pos: Vector3, attacker_yaw: float, target_pos: Vector3,
		max_distance: float, pull_gap: float) -> Vector2:
	var meters := minf(distance, max_distance)
	var to_target := Vector2(target_pos.x - attacker_pos.x, target_pos.z - attacker_pos.z)
	var facing := PlayerState.forward(attacker_yaw)
	match direction:
		DIRECTION_FORWARD:
			return facing * meters
		DIRECTION_TOWARD:
			if to_target.is_zero_approx():
				return Vector2.ZERO
			return -to_target.normalized() * clampf(to_target.length() - pull_gap, 0.0, meters)
	var away := facing if to_target.is_zero_approx() else to_target.normalized()
	return away * meters


## Upward speed (m/s) that reaches `height` (capped at max_height) under
## gravity (m/s^2). 0 = no launch.
func launch_speed(gravity: float, max_height: float) -> float:
	var meters := minf(height, max_height)
	if meters <= 0.0 or gravity <= 0.0:
		return 0.0
	return sqrt(2.0 * gravity * meters)


## Ticks the target is moved (and can't act): duration_ticks, or the launch's
## airtime from flat ground if that's longer, so a launched target doesn't act
## before it's down.
func ticks(gravity: float, max_height: float, tps: float) -> int:
	var launch := launch_speed(gravity, max_height)
	var airtime := ceili(2.0 * launch / gravity * tps) if launch > 0.0 else 0
	return maxi(duration_ticks, airtime)

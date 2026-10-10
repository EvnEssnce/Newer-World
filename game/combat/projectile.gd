class_name Projectile
extends RefCounted
## One projectile in flight. Pure logic (no nodes, no physics queries), unit
## tested in tests/test_projectiles.gd. The server flies one per projectile and
## decides its hits (ProjectileSystem); clients fly a copy with the same math,
## one step per physics tick, for the visuals.
##
## A step moves it along its velocity (gravity bends it) from prev_position to
## position; hit tests sweep that segment (sweep_capsule), so a fast projectile
## can't tunnel through a thin target. Each target is hit at most once per leg
## (`results`); a returning projectile (a boomerang) flies out, turns after
## return_after_ticks (or early: a wall, or its pierce used up) and steers back
## toward a point the caller gives every step (its thrower), with a fresh
## `results` and pierce for the way back.

const END_NONE := 0
## Stopped by a target: its pierce used up, or a guard (stopped_by_guard).
const END_HIT := 1
## Stopped by the world.
const END_WALL := 2
## Lifetime over.
const END_EXPIRED := 3
## A returning projectile reached its thrower.
const END_CAUGHT := 4

const _EPSILON := 0.000001

var params: ProjectileParams
var id := 0
## Who threw it (a peer id; enemies' ids later).
var owner_id := 0
var origin := Vector3.ZERO
var position := Vector3.ZERO
## Where the last step started: the segment hit tests sweep.
var prev_position := Vector3.ZERO
var velocity := Vector3.ZERO
## Steps flown.
var age := 0
## On its way back (returning projectiles).
var returning := false
## END_*; END_NONE while flying.
var ended := END_NONE
## Targets it can still pass through on this leg (below 0 = stopped).
var pierce_left := 0
## Ricochets left (params.bounces), and whether the server changed its course
## this step (a bounce or homing turn; ProjectileSystem sends a redirect).
var bounces_left := 0
var redirected := false
## Homing: radians turned since the last redirect was sent.
var turned_since_sync := 0.0
## Targets on this leg: id -> true once hit, false after an evade (i-frames: it
## can still hit them later on the same leg). Ids are peer ids or enemy ids.
var results: Dictionary[int, bool] = {}

# Server only: what a hit does (the firing attack, scaled by the thrower's
# modifiers when it was released), and the thrower's on-hit statuses
# (Bloodlust), taken on its first damaging hit and shared by the rest.
var attack: AttackParams
var damage_scale := 1.0
## The thrower's execute bonus at release (Finishing Thrust; see
## MasteryTree.execute_multiplier), so a later weapon swap doesn't change it.
var execute := Vector2.ZERO
var on_hit: Array[Vector2i] = []
var on_hit_taken := false


func _init(p: ProjectileParams, from: Vector3, launch_velocity: Vector3) -> void:
	params = p
	origin = from
	position = from
	prev_position = from
	velocity = launch_velocity
	pierce_left = p.pierce
	bounces_left = p.bounces


## The launch velocity for a thrower facing `yaw` (forward is -Z rotated by
## yaw, as everywhere else), turned by yaw_offset (a spread) and tilted up by
## the kind's pitch.
static func launch_velocity_for(p: ProjectileParams, yaw: float, yaw_offset: float = 0.0) -> Vector3:
	var y := yaw + yaw_offset
	var flat := Vector2(-sin(y), -cos(y)) * cos(p.pitch)
	return Vector3(flat.x, sin(p.pitch), flat.y) * p.speed


## The release point for a thrower standing at `feet` facing `yaw`.
static func release_point(p: ProjectileParams, feet: Vector3, yaw: float) -> Vector3:
	return feet + Vector3(-sin(yaw), 0.0, -cos(yaw)) * p.release_forward + Vector3.UP * p.release_height


## One tick of flight. return_target: where a returning projectile steers on
## its way back (its thrower's hands). Turns at the start of the step once
## return_after_ticks have passed, so a step's segment always belongs to one leg.
func step(delta: float, return_target: Vector3) -> void:
	if ended != END_NONE:
		return
	if params.returns and not returning and age >= params.return_after_ticks:
		start_return()
	prev_position = position
	age += 1
	if returning:
		var to := return_target - position
		if not to.is_zero_approx():
			velocity = to.normalized() * params.return_speed
		position += to.limit_length(params.return_speed * delta)
		if position.distance_to(return_target) <= params.catch_radius:
			ended = END_CAUGHT
	else:
		velocity.y -= params.gravity * delta
		position += velocity * delta
	if ended == END_NONE and age >= params.lifetime_ticks:
		ended = END_EXPIRED


## Ricochet: a hit that stopped it sends it on toward `target` instead, at its
## speed, from where it is; uses a bounce.
func bounce_to(target: Vector3) -> void:
	var to := target - position
	if to.is_zero_approx():
		return
	velocity = to.normalized() * maxf(velocity.length(), params.speed)
	ended = END_NONE
	bounces_left -= 1
	redirected = true


## Homing: turns the horizontal velocity toward `target` by at most
## params.homing_turn x delta radians (the vertical part is kept). Returns the
## angle it turned.
func steer_toward(target: Vector3, delta: float) -> float:
	var flat := Vector2(velocity.x, velocity.z)
	var want := Vector2(target.x - position.x, target.z - position.z)
	if flat.is_zero_approx() or want.is_zero_approx():
		return 0.0
	var angle := flat.angle_to(want)
	var turn := clampf(angle, -params.homing_turn * delta, params.homing_turn * delta)
	flat = flat.rotated(turn)
	velocity = Vector3(flat.x, velocity.y, flat.y)
	turned_since_sync += absf(turn)
	return turn


## Turns a returning projectile back: a new leg, so every target can be hit
## once more and the pierce count starts again.
func start_return() -> void:
	returning = true
	results.clear()
	pierce_left = params.pierce


## True if the target can be hit now: not yet hit on this leg (an evade
## doesn't count).
func can_hit(target_id: int) -> bool:
	return not results.get(target_id, false)


## A target's i-frames made it miss: it can still be hit later on this leg.
func register_evade(target_id: int) -> void:
	if not results.has(target_id):
		results[target_id] = false


## A hit landed on target_id (guarded: blocked or parried). Uses up pierce; a
## guard stops it if stopped_by_guard. Stopping a returning projectile on its
## way out turns it back instead. Returns true if it's still on the same leg
## (keeps going through more targets this step).
func register_hit(target_id: int, guarded: bool) -> bool:
	results[target_id] = true
	if guarded and params.stopped_by_guard:
		_stop(END_HIT)
		return false
	pierce_left -= 1
	if pierce_left < 0:
		_stop(END_HIT)
		return false
	return true


## The world stopped it at `point` (on the last step's segment).
func hit_wall(point: Vector3) -> void:
	position = point
	_stop(END_WALL)


func _stop(reason: int) -> void:
	if params.returns and not returning:
		start_return()
	else:
		ended = reason


## Sweeps a sphere of `radius` along a→b against an upright capsule standing
## at `feet` (cap_radius, total height cap_height). Returns how far along the
## segment (0–1) it comes closest, or -1 if they never touch. The fraction
## orders several targets hit in one step (pierce) and compares with a wall.
static func sweep_capsule(a: Vector3, b: Vector3, radius: float, feet: Vector3,
		cap_radius: float, cap_height: float) -> float:
	var bottom := feet + Vector3.UP * cap_radius
	var top := feet + Vector3.UP * maxf(cap_radius, cap_height - cap_radius)
	var st := closest_on_segments(a, b, bottom, top)
	var on_path := a.lerp(b, st.x)
	var on_axis := bottom.lerp(top, st.y)
	var reach := radius + cap_radius
	return st.x if on_path.distance_squared_to(on_axis) <= reach * reach else -1.0


## The closest points of segments p1→q1 and p2→q2, as fractions (s along the
## first, t along the second). Real-Time Collision Detection (Ericson), 5.1.9.
static func closest_on_segments(p1: Vector3, q1: Vector3, p2: Vector3, q2: Vector3) -> Vector2:
	var d1 := q1 - p1
	var d2 := q2 - p2
	var r := p1 - p2
	var a := d1.dot(d1)
	var e := d2.dot(d2)
	var f := d2.dot(r)
	if a <= _EPSILON and e <= _EPSILON:
		return Vector2.ZERO
	if a <= _EPSILON:
		return Vector2(0.0, clampf(f / e, 0.0, 1.0))
	var c := d1.dot(r)
	if e <= _EPSILON:
		return Vector2(clampf(-c / a, 0.0, 1.0), 0.0)
	var b := d1.dot(d2)
	var denom := a * e - b * b
	var s := clampf((b * f - c * e) / denom, 0.0, 1.0) if denom > _EPSILON else 0.0
	var t := (b * s + f) / e
	if t < 0.0:
		t = 0.0
		s = clampf(-c / a, 0.0, 1.0)
	elif t > 1.0:
		t = 1.0
		s = clampf((b - c) / a, 0.0, 1.0)
	return Vector2(s, t)

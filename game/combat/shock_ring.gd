class_name ShockRing
extends RefCounted
## One expanding ring on the ground (the Earthshaker capstone's aftershock):
## its edge rolls outward from `center` at `speed` m/s until `max_radius`, and
## hits each target it passes once. Pure logic, unit tested; the server steps
## it (World, "Juggernaut: War Hammer capstones") and resolves the hits.
##
## Each step sweeps the band from (last radius - thickness) to the new radius,
## so a fast ring can't skip over a target between ticks.

var center := Vector3.ZERO
## Meters per second the edge moves outward.
var speed := 0.0
## Meters: where it stops.
var max_radius := 0.0
## Meters: depth of the band behind the edge that hits.
var thickness := 0.0
## Meters above the center's height a target's feet can be and still be hit.
var height := 0.0
## Current edge radius, and the one before the last step.
var radius := 0.0
var prev_radius := 0.0

# Server bookkeeping (set by whoever spawns it)
var owner_id := 0
var attack: AttackParams = null
var damage_scale := 1.0
var execute := Vector2.ZERO
## Target id -> true once hit (World.resolve_strike's `results`: an evade
## stores false, so a target in i-frames can still be hit later in the band).
var results: Dictionary[int, bool] = {}


func _init(at := Vector3.ZERO, edge_speed := 0.0, max_r := 0.0, band := 0.0,
		reach_up := 0.0) -> void:
	center = at
	speed = edge_speed
	max_radius = max_r
	thickness = band
	height = reach_up


## A ring at `at` with the ring_* keys of a weapon file section (e.g.
## weapon_war_hammer / ability_aftershock).
static func from_tuning(file: String, section: String, at: Vector3) -> ShockRing:
	return ShockRing.new(at, Tuning.get_value(file, section, "ring_speed"),
			Tuning.get_value(file, section, "ring_radius"),
			Tuning.get_value(file, section, "ring_thickness"),
			Tuning.get_value(file, section, "ring_height"))


## Moves the edge outward by speed x delta (never past max_radius).
func step(delta: float) -> void:
	prev_radius = radius
	radius = minf(max_radius, radius + speed * delta)


## True once the edge has reached max_radius (after the step that got there).
func is_done() -> bool:
	return radius >= max_radius


## True if a body (capsule of body_radius, feet at `feet`) is touched by the
## band swept this step: within the swept radii horizontally, and feet no more
## than `height` above (or 1 m below) the ring's ground.
func touches(feet: Vector3, body_radius: float) -> bool:
	var up := feet.y - center.y
	if up > height or up < -1.0:
		return false
	var d := Vector2(feet.x - center.x, feet.z - center.z).length()
	return d - body_radius <= radius and d + body_radius >= prev_radius - thickness


## True if `id` hasn't been hit yet (an evade doesn't count).
func can_hit(id: int) -> bool:
	return not results.get(id, false)


## Marks `id` as hit. Returns false if it already was.
func register_hit(id: int) -> bool:
	if not can_hit(id):
		return false
	results[id] = true
	return true


## Yaw (PlayerState convention) pointing from the center out toward `pos`: the
## "attacker facing" for a hit, so "forward" force pushes outward too.
func outward_yaw(pos: Vector3) -> float:
	var flat := Vector2(pos.x - center.x, pos.z - center.z)
	return PlayerState.yaw_for_direction(flat) if not flat.is_zero_approx() else 0.0

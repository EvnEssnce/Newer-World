class_name AttackParams
extends RefCounted
## One attack's tuning in simulation units (ticks, meters). Built from a weapon
## file's section (e.g. [light] in data/weapon_broadsword.cfg); tests build their
## own. Abilities extend this (AbilityParams).
##
## Timeline: windup, then `windows` hit windows of active_ticks each (one start
## every window_interval_ticks), then recovery. Most attacks have one window.

## Hitbox shapes (see MeleeHitbox).
const SHAPE_BOX := 0
const SHAPE_RADIAL := 1
## No hitbox (e.g. a parry stance).
const SHAPE_NONE := 2

var windup_ticks := 0
var active_ticks := 0
var recovery_ticks := 0
var windows := 1
## Ticks from the start of one hit window to the start of the next.
var window_interval_ticks := 0
var damage := 0.0
## Ticks the target is staggered on hit; 0 = none.
var stagger_ticks := 0
## Stamina a blocking target loses when this hits their guard.
var block_stamina_damage := 0.0
## Always breaks a block, regardless of the blocker's stamina.
var breaks_block := false
## Fraction of normal movement speed while attacking.
var move_multiplier := 0.0
var shape := SHAPE_BOX
## Box: from the attacker's center, hitbox_range forward, hitbox_width wide,
## from the feet up hitbox_height. Radial: hitbox_range is the radius.
var hitbox_range := 0.0
var hitbox_width := 0.0
var hitbox_height := 0.0
## Stops (skips to recovery) after hitting this many targets. 0 = no limit.
var max_targets := 0
## When max_targets stops it (a charge on contact), everything within this many
## meters of the attacker is hit too. 0 = only what the hitbox touches.
var impact_radius := 0.0
## Knockback / pull / launch on hit (force_* keys), or null for none.
var force: ForceParams = null
## This attack's own execute bonus (Executioner's Swing; execute_damage /
## execute_threshold keys): (amount, threshold) for
## MasteryTree.execute_multiplier on the target's health. Server only; zero =
## none. Multiplies with the attacker's tree bonus (Finishing Thrust).
var execute := Vector2.ZERO

# Statuses (data/status_effects.cfg ids; "" = none)
## Applied to whoever this damages (server), with status_stacks stacks, for
## status_duration_ticks (-1 = the status's own duration).
var applies_status := ""
var status_stacks := 1
var status_duration_ticks := -1
## Applied to the attacker when it starts, inside the predicted simulation
## (a self-buff such as Bloodlust), with self_status_stacks stacks.
var self_status := ""
var self_status_stacks := 1

# Projectiles (the PROJ tag; data/projectiles.cfg ids; "" = none)
## Thrown at projectile_tick (from the attack's start), projectile_count of
## them fanned over projectile_spread radians. Its hit uses this attack's
## damage, stagger, statuses and force (server). The release is predicted (the
## attack timeline); the projectile itself is server state (ProjectileSystem).
var projectile := ""
var projectile_tick := 0
var projectile_count := 1
var projectile_spread := 0.0


## First tick of recovery: after the last hit window.
func recovery_start_tick() -> int:
	return windup_ticks + (windows - 1) * window_interval_ticks + active_ticks


## True on the tick (from the attack's start) its projectiles are released.
func releases_projectile_at(tick: int) -> bool:
	return not projectile.is_empty() and tick == projectile_tick


func total_ticks() -> int:
	return recovery_start_tick() + recovery_ticks


## The hit window (0-based) that tick falls in, or -1 outside them all.
func window_at(tick: int) -> int:
	var since := tick - windup_ticks
	if since < 0 or tick >= recovery_start_tick():
		return -1
	if windows <= 1:
		return 0 if since < active_ticks else -1
	@warning_ignore("integer_division")
	var index := mini(since / window_interval_ticks, windows - 1)
	return index if since - index * window_interval_ticks < active_ticks else -1


static func from_tuning(file: String, section: String, tps: float) -> AttackParams:
	var a := AttackParams.new()
	a.load_from(file, section, tps)
	return a


func load_from(file: String, section: String, tps: float) -> void:
	windup_ticks = roundi(Tuning.get_value(file, section, "windup") * tps)
	active_ticks = maxi(1, roundi(Tuning.get_value(file, section, "active") * tps))
	recovery_ticks = roundi(Tuning.get_value(file, section, "recovery") * tps)
	windows = maxi(1, Tuning.get_optional(file, section, "windows", 1))
	window_interval_ticks = maxi(active_ticks,
			roundi(Tuning.get_optional(file, section, "window_interval", 0.0) * tps))
	damage = Tuning.get_value(file, section, "damage")
	stagger_ticks = roundi(Tuning.get_value(file, section, "stagger") * tps)
	block_stamina_damage = Tuning.get_value(file, section, "block_stamina_damage")
	breaks_block = Tuning.get_value(file, section, "breaks_block")
	move_multiplier = Tuning.get_value(file, section, "move_multiplier")
	shape = shape_from_name(Tuning.get_optional(file, section, "shape", "box"))
	hitbox_range = Tuning.get_value(file, section, "range")
	hitbox_width = Tuning.get_value(file, section, "width")
	hitbox_height = Tuning.get_value(file, section, "height")
	max_targets = Tuning.get_optional(file, section, "max_targets", 0)
	impact_radius = Tuning.get_optional(file, section, "impact_radius", 0.0)
	execute = Vector2(Tuning.get_optional(file, section, "execute_damage", 0.0),
			Tuning.get_optional(file, section, "execute_threshold", 0.0))
	_load_statuses(file, section, tps)
	force = ForceParams.from_tuning(file, section, tps)
	projectile = Tuning.get_optional(file, section, "projectile", "")
	if not projectile.is_empty():
		projectile_tick = roundi(Tuning.get_value(file, section, "projectile_time") * tps)
		projectile_count = maxi(1, Tuning.get_optional(file, section, "projectile_count", 1))
		projectile_spread = deg_to_rad(Tuning.get_optional(file, section, "projectile_spread", 0.0))


## The optional status keys (see data/status_effects.cfg).
func _load_statuses(file: String, section: String, tps: float) -> void:
	applies_status = Tuning.get_optional(file, section, "applies_status", "")
	status_stacks = Tuning.get_optional(file, section, "status_stacks", 1)
	var duration: float = Tuning.get_optional(file, section, "status_duration", -1.0)
	status_duration_ticks = roundi(duration * tps) if duration > 0.0 else -1
	self_status = Tuning.get_optional(file, section, "self_status", "")
	self_status_stacks = Tuning.get_optional(file, section, "self_status_stacks", 1)


static func shape_from_name(shape_name: String) -> int:
	match shape_name:
		"radial":
			return SHAPE_RADIAL
		"none":
			return SHAPE_NONE
		"box":
			return SHAPE_BOX
	push_error("AttackParams: unknown hitbox shape \"%s\"" % shape_name)
	return SHAPE_BOX


## A copy of this attack whose hitbox is a circle of `radius` meters around the
## attacker (same damage, stagger, statuses, force): a charge's impact.
func radial_copy(radius: float) -> AttackParams:
	var copy: AttackParams = get_script().new()
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			copy.set(property.name, get(property.name))
	copy.shape = SHAPE_RADIAL
	copy.hitbox_range = radius
	return copy


## A copy of this attack with its hitbox reaching `new_range` meters (same
## shape and everything else): a server-side range upgrade (Maelstrom).
func range_copy(new_range: float) -> AttackParams:
	var copy := radial_copy(new_range)
	copy.shape = shape
	return copy

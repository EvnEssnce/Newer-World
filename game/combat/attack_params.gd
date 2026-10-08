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
## Knockback / pull / launch on hit (force_* keys), or null for none.
var force: ForceParams = null


## First tick of recovery: after the last hit window.
func recovery_start_tick() -> int:
	return windup_ticks + (windows - 1) * window_interval_ticks + active_ticks


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
	force = ForceParams.from_tuning(file, section, tps)


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

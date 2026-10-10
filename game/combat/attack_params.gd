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
## Radial only: limits the circle to a cone this wide (full width, radians) in
## front of the attacker (Seismic Slam). 0 = all the way round.
var hitbox_arc := 0.0
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
## A second status for the same targets (applies_status_2, status_stacks_2,
## status_duration_2: Challenger's Roar taunts and slows).
var applies_status_2 := ""
var status_stacks_2 := 1
var status_duration_2_ticks := -1
## Applied to the attacker when it starts, inside the predicted simulation
## (a self-buff such as Bloodlust), with self_status_stacks stacks.
var self_status := ""
var self_status_stacks := 1
## Given to the attacker (server) when this attack "reads" a target: a player
## blocks or evades it, or an enemy is mid-swing when it lands (Feint).
var read_status := ""
## On a damaging hit, every stack of detonates_status on the target is used up
## for detonate_damage more damage each (server; Ignite on burn).
var detonates_status := ""
var detonate_damage := 0.0

# Healing and channels (server)
## Each hit window after the first deals this fraction more than the one before
## it adds up (Searing Ray: window i deals 1 + window_ramp x i as much).
var window_ramp := 0.0
## Fraction of the damage this deals that heals the attacker (Siphon).
var lifesteal := 0.0
## Allies (not the attacker) its hitbox touches are healed this much per hit
## window instead of being ignored (Mending Beam).
var ally_heal := 0.0
## The attacker and the allies its hitbox touches get Ward with this much
## absorb (a damage-absorbing shield).
var ally_shield := 0.0
## Its hitbox only reaches allies (Mending Beam, Ward): hostiles are skipped.
var allies_only := false
## Paladin support (server): heals the user once (Benediction); allies it
## touches (and the user) get ally_status; cleanses (removes debuffs from) the
## user and the allies it touches; grants the user and the allies it touches an
## extra Rebirth for blessing_ticks (Phoenix Blessing); its last hit window
## raises fallen allies it touches (Kindle Life).
var self_heal := 0.0
var ally_status := ""
var cleanses := false
var grants_rebirth := false
var blessing_ticks := 0
var revives := false
## A damaging hit also heals the lowest-health ally (the user included) within
## heal_radius m by this much (Uplifting Blow).
var heals_lowest_ally := 0.0
var heal_radius := 0.0

# Zones and summons (data/zones.cfg ids; "" = none; server, ZoneSystem)
## Placed zone_tick after the start, zone_distance m ahead of the user.
var zone := ""
var zone_tick := 0
var zone_distance := 0.0
## A projectile of this attack places this zone where it stops.
var zone_on_impact := ""

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
	hitbox_arc = deg_to_rad(Tuning.get_optional(file, section, "arc", 0.0))
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
	applies_status_2 = Tuning.get_optional(file, section, "applies_status_2", "")
	status_stacks_2 = Tuning.get_optional(file, section, "status_stacks_2", 1)
	var duration_2: float = Tuning.get_optional(file, section, "status_duration_2", -1.0)
	status_duration_2_ticks = roundi(duration_2 * tps) if duration_2 > 0.0 else -1
	self_status = Tuning.get_optional(file, section, "self_status", "")
	self_status_stacks = Tuning.get_optional(file, section, "self_status_stacks", 1)
	read_status = Tuning.get_optional(file, section, "read_status", "")
	detonates_status = Tuning.get_optional(file, section, "detonates_status", "")
	detonate_damage = Tuning.get_optional(file, section, "detonate_damage", 0.0)
	window_ramp = Tuning.get_optional(file, section, "window_ramp", 0.0)
	lifesteal = Tuning.get_optional(file, section, "lifesteal", 0.0)
	ally_heal = Tuning.get_optional(file, section, "ally_heal", 0.0)
	ally_shield = Tuning.get_optional(file, section, "ally_shield", 0.0)
	allies_only = Tuning.get_optional(file, section, "allies_only", false)
	self_heal = Tuning.get_optional(file, section, "self_heal", 0.0)
	ally_status = Tuning.get_optional(file, section, "ally_status", "")
	cleanses = Tuning.get_optional(file, section, "cleanses", false)
	grants_rebirth = Tuning.get_optional(file, section, "grants_rebirth", false)
	blessing_ticks = roundi(float(Tuning.get_optional(file, section, "blessing_time", 0.0)) * tps)
	revives = Tuning.get_optional(file, section, "revives", false)
	heals_lowest_ally = Tuning.get_optional(file, section, "heals_lowest_ally", 0.0)
	heal_radius = Tuning.get_optional(file, section, "heal_radius", 0.0)
	zone = Tuning.get_optional(file, section, "zone", "")
	zone_tick = roundi(float(Tuning.get_optional(file, section, "zone_time", 0.0)) * tps)
	zone_distance = Tuning.get_optional(file, section, "zone_distance", 0.0)
	zone_on_impact = Tuning.get_optional(file, section, "zone_on_impact", "")


## The statuses this gives whoever it damages, as [id, stacks, duration ticks
## (-1 = the status's own)] each: applies_status, then applies_status_2.
func target_statuses() -> Array[Array]:
	var result: Array[Array] = []
	if not applies_status.is_empty():
		result.append([applies_status, status_stacks, status_duration_ticks])
	if not applies_status_2.is_empty():
		result.append([applies_status_2, status_stacks_2, status_duration_2_ticks])
	return result


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
	var result := copy()
	result.shape = SHAPE_RADIAL
	result.hitbox_range = radius
	result.hitbox_arc = 0.0
	return result


## A copy of this attack (same script, every field), for a server-side variant
## (the Breaker capstone's block-breaking heavy).
func copy() -> AttackParams:
	var result: AttackParams = get_script().new()
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result.set(property.name, get(property.name))
	return result


## A copy of this attack with its hitbox reaching `new_range` meters (same
## shape and everything else): a server-side range upgrade (Maelstrom).
func range_copy(new_range: float) -> AttackParams:
	var result := copy()
	result.hitbox_range = new_range
	return result

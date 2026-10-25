class_name EnemyParams
extends RefCounted
## One enemy type's tuning in simulation units (ticks, m/s, radians), from
## data/enemy_<kind>.cfg. Tests build their own.

## Shown over it (its label). [stats] name, optional; default: the kind, capitalized.
var display_name := ""
var max_health := 0.0
var move_speed := 0.0
var wander_speed := 0.0
var return_speed := 0.0
## Radians per second.
var turn_speed := 0.0
var stagger_multiplier := 0.0
var respawn_ticks := 0
## Ticks without taking damage before it heals to full and goes back to its
## spot (0 = never). Also ends a fight on its DPS readout.
var reset_ticks := 0
## Its swings' gear score against players' armor (GearScore.mitigation).
var gear_score := 100

var aggro_range := 0.0
var leash_range := 0.0
var attack_range := 0.0
var attack_cooldown_ticks := 0
var wander_radius := 0.0
var wander_pause_ticks := 0
## Never moves, turns or swings (training dummy); hits still stagger it and
## forces still move it.
var stationary := false
## Counts as aware of every player: only hits from its rear arc backstab it,
## never the "unaware enemy" rule (training dummy, which never targets anyone).
var always_aware := false
## Between swings (while its attack cooldown runs) it backs away from its target
## when nearer than this (m): hit-and-run and casters. 0 = stands its ground.
var keep_distance := 0.0
## Speed while backing away (m/s).
var retreat_speed := 0.0
## A projectile attack aims at this height above its target's feet (m).
var aim_height := 1.0

# Navigation ([navigation]; see EnemyPath). Kinds without the section walk straight.
## Walks around obstacles on the navigation mesh (EnemyNavigation).
var paths := false
## Asks for a new path at least this often (ticks)...
var repath_ticks := 30
## ...or when its goal moved this far (m) from the goal of its current path.
var repath_distance := 1.0
## A path corner counts as reached within this distance (m).
var waypoint_reach := 0.3

# Threat ([threat]; see ThreatTable)
## Per point of damage it takes from a player (hits, projectiles, damage over time).
var threat_per_damage := 0.0
## Per point of health a player heals someone it has threat on.
var threat_per_heal := 0.0
## For coming within aggro_range while it isn't walking home.
var threat_proximity := 0.0
## A challenger needs more than this x the current target's threat to take it.
var threat_switch_ratio := 1.0
## Every threat is multiplied by this each tick (1 = no decay).
var threat_decay_factor := 1.0

var attack: AttackParams
## Loot table id (data/loot.cfg [table_<id>]) its killers roll, or "" for none.
var loot_table := ""
## Character XP each player who damaged it gets when it dies ([progression]).
var kill_xp := 0
## Weapon mastery XP each of them gets, split over the weapons that dealt their damage.
var mastery_xp := 0

static var _cache: Dictionary[String, EnemyParams] = {}
static var _cache_version := -1


## The tuning for an enemy kind (e.g. "husk"), loaded once (again when
## Tuning.version moves).
static func for_kind(kind: String) -> EnemyParams:
	if _cache_version != Tuning.version:
		_cache_version = Tuning.version
		_cache.clear()
	if not _cache.has(kind):
		_cache[kind] = from_tuning("enemy_" + kind)
		if _cache[kind].display_name.is_empty():
			_cache[kind].display_name = kind.capitalize()
	return _cache[kind]


static func from_tuning(file: String) -> EnemyParams:
	var tps := float(Engine.physics_ticks_per_second)
	var p := EnemyParams.new()
	p.display_name = Tuning.get_optional(file, "stats", "name", "")
	p.max_health = Tuning.get_value(file, "stats", "max_health")
	p.move_speed = Tuning.get_value(file, "stats", "move_speed")
	p.wander_speed = Tuning.get_value(file, "stats", "wander_speed")
	p.return_speed = Tuning.get_value(file, "stats", "return_speed")
	p.turn_speed = deg_to_rad(Tuning.get_value(file, "stats", "turn_speed"))
	p.stagger_multiplier = Tuning.get_value(file, "stats", "stagger_multiplier")
	p.respawn_ticks = roundi(Tuning.get_value(file, "stats", "respawn_time") * tps)
	p.reset_ticks = roundi(Tuning.get_value(file, "stats", "reset_time") * tps)
	p.gear_score = Tuning.get_optional(file, "stats", "gear_score", 100)

	p.aggro_range = Tuning.get_value(file, "ai", "aggro_range")
	p.leash_range = Tuning.get_value(file, "ai", "leash_range")
	p.attack_range = Tuning.get_value(file, "ai", "attack_range")
	p.attack_cooldown_ticks = roundi(Tuning.get_value(file, "ai", "attack_cooldown") * tps)
	p.wander_radius = Tuning.get_value(file, "ai", "wander_radius")
	p.wander_pause_ticks = roundi(Tuning.get_value(file, "ai", "wander_pause") * tps)
	p.stationary = Tuning.get_value(file, "ai", "stationary")
	p.always_aware = Tuning.get_optional(file, "ai", "always_aware", false)
	p.keep_distance = maxf(0.0, Tuning.get_optional(file, "ai", "keep_distance", 0.0))
	p.retreat_speed = Tuning.get_optional(file, "ai", "retreat_speed", p.move_speed)
	p.aim_height = Tuning.get_optional(file, "ai", "aim_height", 1.0)
	p.paths = Tuning.get_optional(file, "navigation", "enabled", false) and not p.stationary
	if p.paths:
		p.repath_ticks = maxi(1, roundi(Tuning.get_value(file, "navigation", "repath_interval") * tps))
		p.repath_distance = Tuning.get_value(file, "navigation", "repath_distance")
		p.waypoint_reach = Tuning.get_value(file, "navigation", "waypoint_reach")

	p.threat_per_damage = Tuning.get_value(file, "threat", "per_damage")
	p.threat_per_heal = Tuning.get_value(file, "threat", "per_heal")
	p.threat_proximity = Tuning.get_value(file, "threat", "proximity")
	p.threat_switch_ratio = maxf(1.0, Tuning.get_value(file, "threat", "switch_ratio"))
	var decay: float = clampf(Tuning.get_value(file, "threat", "decay_per_second"), 0.0, 1.0)
	p.threat_decay_factor = pow(1.0 - decay, 1.0 / tps)

	p.attack = AttackParams.from_tuning(file, "attack", tps)
	p.loot_table = Tuning.get_optional(file, "loot", "table", "")
	p.kill_xp = maxi(0, Tuning.get_optional(file, "progression", "kill_xp", 0))
	p.mastery_xp = maxi(0, Tuning.get_optional(file, "progression", "mastery_xp", 0))
	return p


## A copy of this kind's tuning for one placed at gear_score (its camp's):
## health, hit damage and block stamina damage, and kill/mastery XP grow by
## data/scaling.cfg's rates per 5 gear score away from the kind's own
## gear_score; nothing else changes. The same params when it's the kind's own.
func scaled_to(new_gear_score: int) -> EnemyParams:
	return scaled_by(new_gear_score,
			Tuning.get_value("scaling", "scaling", "health_per_5"),
			Tuning.get_value("scaling", "scaling", "damage_per_5"),
			Tuning.get_value("scaling", "scaling", "xp_per_5"))


## scaled_to with the rates given (fractions per 5 gear score). Pure.
func scaled_by(new_gear_score: int, health_rate: float, damage_rate: float,
		xp_rate: float) -> EnemyParams:
	if new_gear_score == gear_score:
		return self
	var steps := (new_gear_score - gear_score) / 5.0
	var result := copy()
	result.gear_score = new_gear_score
	result.max_health = max_health * pow(1.0 + health_rate, steps)
	var damage := pow(1.0 + damage_rate, steps)
	result.attack = attack.copy()
	result.attack.damage = attack.damage * damage
	result.attack.block_stamina_damage = attack.block_stamina_damage * damage
	var xp := pow(1.0 + xp_rate, steps)
	result.kill_xp = roundi(kill_xp * xp)
	result.mastery_xp = roundi(mastery_xp * xp)
	return result


## Every field copied (attack shared: copy it before changing it).
func copy() -> EnemyParams:
	var result := EnemyParams.new()
	for property in get_property_list():
		if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result.set(property.name, get(property.name))
	return result


## Problems with this kind's tuning, e.g. a loot table or projectile kind that
## doesn't exist (a unit test runs it on every data/enemy_*.cfg). `db`: the item
## database its loot table must be in.
func validate(db: ItemDatabase) -> PackedStringArray:
	var problems := PackedStringArray()
	if max_health <= 0.0:
		problems.append("max_health must be above 0")
	if not loot_table.is_empty() and not db.tables.has(loot_table):
		problems.append("unknown loot table '%s'" % loot_table)
	if attack == null or attack.total_ticks() <= 0:
		problems.append("[attack] has no length")
	elif not attack.projectile.is_empty():
		if ProjectileParams.get_kind(attack.projectile) == null:
			problems.append("unknown projectile '%s'" % attack.projectile)
		elif attack.projectile_tick >= attack.total_ticks():
			problems.append("projectile_time is after the swing ends")
	if not stationary:
		if aggro_range > leash_range:
			problems.append("aggro_range is beyond leash_range")
		if move_speed <= 0.0 or return_speed <= 0.0:
			problems.append("move_speed and return_speed must be above 0")
		if keep_distance > 0.0 and retreat_speed <= 0.0:
			problems.append("keep_distance needs a retreat_speed above 0")
	return problems

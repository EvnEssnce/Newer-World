class_name EnemyParams
extends RefCounted
## One enemy type's tuning in simulation units (ticks, m/s, radians), from
## data/enemy_<kind>.cfg. Tests build their own.

var max_health := 0.0
var move_speed := 0.0
var wander_speed := 0.0
var return_speed := 0.0
## Radians per second.
var turn_speed := 0.0
var stagger_multiplier := 0.0
var respawn_ticks := 0

var aggro_range := 0.0
var leash_range := 0.0
var attack_range := 0.0
var attack_cooldown_ticks := 0
var wander_radius := 0.0
var wander_pause_ticks := 0

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

static var _cache: Dictionary[String, EnemyParams] = {}


## The tuning for an enemy kind (e.g. "husk"), loaded once.
static func for_kind(kind: String) -> EnemyParams:
	if not _cache.has(kind):
		_cache[kind] = from_tuning("enemy_" + kind)
	return _cache[kind]


static func from_tuning(file: String) -> EnemyParams:
	var tps := float(Engine.physics_ticks_per_second)
	var p := EnemyParams.new()
	p.max_health = Tuning.get_value(file, "stats", "max_health")
	p.move_speed = Tuning.get_value(file, "stats", "move_speed")
	p.wander_speed = Tuning.get_value(file, "stats", "wander_speed")
	p.return_speed = Tuning.get_value(file, "stats", "return_speed")
	p.turn_speed = deg_to_rad(Tuning.get_value(file, "stats", "turn_speed"))
	p.stagger_multiplier = Tuning.get_value(file, "stats", "stagger_multiplier")
	p.respawn_ticks = roundi(Tuning.get_value(file, "stats", "respawn_time") * tps)

	p.aggro_range = Tuning.get_value(file, "ai", "aggro_range")
	p.leash_range = Tuning.get_value(file, "ai", "leash_range")
	p.attack_range = Tuning.get_value(file, "ai", "attack_range")
	p.attack_cooldown_ticks = roundi(Tuning.get_value(file, "ai", "attack_cooldown") * tps)
	p.wander_radius = Tuning.get_value(file, "ai", "wander_radius")
	p.wander_pause_ticks = roundi(Tuning.get_value(file, "ai", "wander_pause") * tps)

	p.threat_per_damage = Tuning.get_value(file, "threat", "per_damage")
	p.threat_per_heal = Tuning.get_value(file, "threat", "per_heal")
	p.threat_proximity = Tuning.get_value(file, "threat", "proximity")
	p.threat_switch_ratio = maxf(1.0, Tuning.get_value(file, "threat", "switch_ratio"))
	var decay: float = clampf(Tuning.get_value(file, "threat", "decay_per_second"), 0.0, 1.0)
	p.threat_decay_factor = pow(1.0 - decay, 1.0 / tps)

	p.attack = AttackParams.from_tuning(file, "attack", tps)
	p.loot_table = Tuning.get_optional(file, "loot", "table", "")
	return p

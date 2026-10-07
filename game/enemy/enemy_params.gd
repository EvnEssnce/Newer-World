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

var attack: AttackParams

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

	p.attack = AttackParams.from_tuning(file, "attack", tps)
	return p

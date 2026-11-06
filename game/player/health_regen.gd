class_name HealthRegen
extends RefCounted
## Out-of-combat health regeneration (data/combat.cfg [health_regen]): once a
## player has neither dealt nor taken damage for `delay` seconds, it heals a
## fraction of its max health every second, times its modifiers. Server only
## (health isn't predicted); one per Player. Pure logic, unit tested
## (tests/test_health_regen.gd).
##
## "In combat" is PlayerState.combat_ticks (set to the Ember file's combat_time
## on every damage dealt or taken, then counted down), so the time since the
## last fight is combat_time - combat_ticks while it runs, then counted here.

## Ticks without combat before regeneration starts.
var delay_ticks := 600
## Fraction of max health healed per tick, before modifiers.
var fraction_per_tick := 0.01 / 60.0
## Ticks since the player last dealt or took damage (capped at delay_ticks).
var since_combat := 0


static func from_tuning() -> HealthRegen:
	var r := HealthRegen.new()
	var tps := float(Engine.physics_ticks_per_second)
	r.delay_ticks = roundi(Tuning.get_value("combat", "health_regen", "delay") * tps)
	r.fraction_per_tick = Tuning.get_value("combat", "health_regen", "max_health_per_second") / tps
	return r


## One server tick: the health to add (0 while in combat, dead, waiting or at
## full). combat_ticks / combat_time_ticks: PlayerState.combat_ticks and the
## combat_time it starts from; multiplier: the player's regen modifiers.
func step(combat_ticks: int, combat_time_ticks: int, dead: bool, health: float,
		max_health: float, multiplier: float) -> float:
	if dead:
		since_combat = 0
		return 0.0
	if combat_ticks > 0:
		since_combat = maxi(0, combat_time_ticks - combat_ticks)
	else:
		since_combat = mini(since_combat + 1, delay_ticks)
	if since_combat < delay_ticks or health >= max_health:
		return 0.0
	return minf(max_health * fraction_per_tick * maxf(0.0, multiplier), max_health - health)

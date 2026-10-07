class_name AttackParams
extends RefCounted
## One attack's tuning in simulation units (ticks, meters). Built from a weapon
## file's section (e.g. [light] in data/weapon_sword.cfg); tests build their own.

var windup_ticks := 0
var active_ticks := 0
var recovery_ticks := 0
var damage := 0.0
## Ticks the target is staggered on hit; 0 = none.
var stagger_ticks := 0
## Stamina a blocking target loses when this hits their guard.
var block_stamina_damage := 0.0
## Always breaks a block, regardless of the blocker's stamina.
var breaks_block := false
## Fraction of normal movement speed while attacking.
var move_multiplier := 0.0
## Hitbox: from the attacker's center, hitbox_range forward, hitbox_width wide,
## from the feet up hitbox_height.
var hitbox_range := 0.0
var hitbox_width := 0.0
var hitbox_height := 0.0


func total_ticks() -> int:
	return windup_ticks + active_ticks + recovery_ticks


static func from_tuning(file: String, section: String, tps: float) -> AttackParams:
	var a := AttackParams.new()
	a.windup_ticks = roundi(Tuning.get_value(file, section, "windup") * tps)
	a.active_ticks = maxi(1, roundi(Tuning.get_value(file, section, "active") * tps))
	a.recovery_ticks = roundi(Tuning.get_value(file, section, "recovery") * tps)
	a.damage = Tuning.get_value(file, section, "damage")
	a.stagger_ticks = roundi(Tuning.get_value(file, section, "stagger") * tps)
	a.block_stamina_damage = Tuning.get_value(file, section, "block_stamina_damage")
	a.breaks_block = Tuning.get_value(file, section, "breaks_block")
	a.move_multiplier = Tuning.get_value(file, section, "move_multiplier")
	a.hitbox_range = Tuning.get_value(file, section, "range")
	a.hitbox_width = Tuning.get_value(file, section, "width")
	a.hitbox_height = Tuning.get_value(file, section, "height")
	return a

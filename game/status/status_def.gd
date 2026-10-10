class_name StatusDef
extends RefCounted
## One status effect's tuning in simulation units (ticks), from a [status_<id>]
## section of data/status_effects.cfg. Tests build their own. What each field
## does is explained in that file.

const CATEGORY_BUFF := "buff"
const CATEGORY_DEBUFF := "debuff"
## Changes movement or actions: lives in the predicted simulation.
const AFFECTS_SIM := "sim"
## Only changes damage numbers: worked out by the server.
const AFFECTS_DAMAGE := "damage"

var id := ""
var display_name := ""
var category := CATEGORY_DEBUFF
var affects := AFFECTS_DAMAGE
var duration_ticks := 0
var max_stacks := 1

# Sim effects
## Walking speed multiplier (1 = none).
var move_multiplier := 1.0
## Root: no walking, dodging, jumping or dashing.
var stops_movement := false
## Stun: staggers for the whole duration.
var stuns := false
## Light and heavy attacks play this many times faster (1 = none; Rampage);
## each stack adds attack_speed - 1 (Talon Storm), up to 2x in all...
var attack_speed := 1.0
## ...while stamina is at least this fraction of max.
var attack_speed_min_stamina := 0.0

# Damage effects (server)
## Per stack: fraction more damage taken / dealt.
var damage_taken := 0.0
var damage_dealt := 0.0
## Per stack: damage dealt every tick_interval_ticks (0 = no damage over time).
var damage_per_interval := 0.0
var tick_interval_ticks := 0
## Per stack: health healed every tick_interval_ticks (0 = no healing over time).
var heal_per_interval := 0.0
## The owner's damaging hits apply this status (id) with on_hit_stacks stacks.
var on_hit_status := ""
var on_hit_stacks := 0
## Each such hit uses up one stack of this status.
var consume_on_hit := false
## The owner's next hit crits (and uses the status up): Primed, from Feint.
var next_hit_crits := false
## Marked: the applier's next melee hit on the owner deals this fraction more
## damage and uses the status up. 0 = none.
var marked_bonus := 0.0
## Shield Wall: while the owner blocks, allies inside a box this deep (m,
## straight behind them) and cover_width wide (m) are covered: hits on them
## from within the owner's block arc are blocked by the owner. 0 = none.
var cover_depth := 0.0
var cover_width := 0.0

# Server-decided effects
## Taunt: an enemy with it targets the status's source (players: no effect).
var forces_target := false
## Immunities of the owner, checked by the server when something is applied:
## refuses knockback, pull and launch...
var force_immune := false
## ...refuses stagger (hits, guard breaks) and stuns...
var stagger_immune := false
## ...refuses crowd-control debuffs (is_crowd_control: slow, root, stun, taunt).
var cc_immune := false
## Brace: an attacker whose melee hit lands on the owner while it charges (it
## was dashing, or within charge_window_ticks of the status starting) is
## staggered this many ticks. 0 = none.
var charge_stagger_ticks := 0
var charge_window_ticks := 0
## Iron Hide: per stack, fraction more damage taken per hostile within
## crowd_radius meters, counting at most crowd_max (negative = less).
var crowd_damage_taken := 0.0
var crowd_radius := 0.0
var crowd_max := 0


func is_debuff() -> bool:
	return category == CATEGORY_DEBUFF


## A debuff that takes control away: slows, roots, stuns, taunts.
func is_crowd_control() -> bool:
	return is_debuff() and (move_multiplier < 1.0 or stops_movement or stuns or forces_target)


func deals_damage_over_time() -> bool:
	return damage_per_interval > 0.0 and tick_interval_ticks > 0


func heals_over_time() -> bool:
	return heal_per_interval > 0.0 and tick_interval_ticks > 0


static func from_tuning(file: String, status_id: String, tps: float) -> StatusDef:
	var section := "status_" + status_id
	var s := StatusDef.new()
	s.id = status_id
	s.display_name = Tuning.get_value(file, section, "name")
	s.category = Tuning.get_value(file, section, "category")
	s.affects = Tuning.get_value(file, section, "affects")
	s.duration_ticks = maxi(1, roundi(Tuning.get_value(file, section, "duration") * tps))
	s.max_stacks = maxi(1, Tuning.get_value(file, section, "max_stacks"))
	# Effect keys are optional: a status lists only what it does.
	s.move_multiplier = Tuning.get_optional(file, section, "move_multiplier", 1.0)
	s.stops_movement = Tuning.get_optional(file, section, "stops_movement", false)
	s.stuns = Tuning.get_optional(file, section, "stuns", false)
	s.attack_speed = Tuning.get_optional(file, section, "attack_speed", 1.0)
	s.attack_speed_min_stamina = Tuning.get_optional(file, section, "attack_speed_min_stamina", 0.0)
	s.cover_depth = Tuning.get_optional(file, section, "cover_depth", 0.0)
	s.cover_width = Tuning.get_optional(file, section, "cover_width", 0.0)
	s.damage_taken = Tuning.get_optional(file, section, "damage_taken", 0.0)
	s.damage_dealt = Tuning.get_optional(file, section, "damage_dealt", 0.0)
	var per_second: float = Tuning.get_optional(file, section, "damage_per_second", 0.0)
	var heal_per_second: float = Tuning.get_optional(file, section, "heal_per_second", 0.0)
	if per_second > 0.0 or heal_per_second > 0.0:
		s.tick_interval_ticks = maxi(1, roundi(Tuning.get_value(file, section, "tick_interval") * tps))
		s.damage_per_interval = per_second * s.tick_interval_ticks / tps
		s.heal_per_interval = heal_per_second * s.tick_interval_ticks / tps
	s.on_hit_status = Tuning.get_optional(file, section, "on_hit_status", "")
	s.on_hit_stacks = Tuning.get_optional(file, section, "on_hit_stacks", 1)
	s.consume_on_hit = Tuning.get_optional(file, section, "consume_on_hit", false)
	s.next_hit_crits = Tuning.get_optional(file, section, "next_hit_crits", false)
	s.marked_bonus = Tuning.get_optional(file, section, "marked_bonus", 0.0)
	s.forces_target = Tuning.get_optional(file, section, "forces_target", false)
	s.force_immune = Tuning.get_optional(file, section, "force_immune", false)
	s.stagger_immune = Tuning.get_optional(file, section, "stagger_immune", false)
	s.cc_immune = Tuning.get_optional(file, section, "cc_immune", false)
	s.charge_stagger_ticks = roundi(float(Tuning.get_optional(file, section, "charge_stagger", 0.0)) * tps)
	s.charge_window_ticks = roundi(float(Tuning.get_optional(file, section, "charge_window", 0.0)) * tps)
	s.crowd_damage_taken = Tuning.get_optional(file, section, "crowd_damage_taken", 0.0)
	s.crowd_radius = Tuning.get_optional(file, section, "crowd_radius", 0.0)
	s.crowd_max = Tuning.get_optional(file, section, "crowd_max", 0)
	return s

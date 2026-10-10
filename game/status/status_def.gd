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
## Walking speed multiplier (1 = none; below 1 a slow, above 1 a haste: Tailwind).
var move_multiplier := 1.0
## Roll speed multiplier, so the same roll goes farther (Gust Roll). 1 = none.
var dodge_speed_multiplier := 1.0
## Roll stamina cost multiplier (Tailwind: cheaper rolls). 1 = none.
var dodge_cost_multiplier := 1.0
## Gravity multiplier while falling (a slower descent). 1 = none.
var fall_gravity_multiplier := 1.0
## Hover: falling is capped at this many m/s (Updraft). 0 = none.
var max_fall_speed := 0.0
## Root: no walking, dodging, jumping or dashing.
var stops_movement := false
## Silence: no weapon or Wing abilities (light, heavy and block still work).
var silences := false
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
## Per stack: fraction more damage the owner takes from whoever applied it
## (Hunter's Mark).
var damage_taken_from_source := 0.0
## Blind (0..1): a player sees a white haze this strong over the screen
## (fading out at the end); an enemy's swings miss with this chance (Dazzled,
## Flare). 0 = none.
var blind := 0.0
## Fire Trail: each roll places this zone (data/zones.cfg) and uses a stack.
var roll_zone := ""
## Stealth (visual only for now): other players see the owner faint, with no
## nameplate (Ember Double's Veiled).
var veils := false
## Per stack: fraction more healing the owner receives (negative = less:
## Withering Touch) / deals (Phoenix Aura).
var healing_taken := 0.0
var healing_dealt := 0.0
## Ward: a damage-absorbing shield while the status lasts (the amount is on the
## server, Player.absorb).
var absorbs := false
## Consecrating Strikes: each step the owner's attack connects heals the owner
## and its allies within hit_heal_radius m this much.
var hit_heal := 0.0
var hit_heal_radius := 0.0
## Guardian Wing: this fraction of the damage hits deal to the owner goes to
## whoever applied it instead (while that player lives).
var damage_share := 0.0
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
	return is_debuff() and (move_multiplier < 1.0 or stops_movement or stuns or forces_target
			or silences)


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
	s.dodge_speed_multiplier = Tuning.get_optional(file, section, "dodge_speed_multiplier", 1.0)
	s.dodge_cost_multiplier = Tuning.get_optional(file, section, "dodge_cost_multiplier", 1.0)
	s.fall_gravity_multiplier = Tuning.get_optional(file, section, "fall_gravity_multiplier", 1.0)
	s.max_fall_speed = Tuning.get_optional(file, section, "max_fall_speed", 0.0)
	s.damage_taken_from_source = Tuning.get_optional(file, section, "damage_taken_from_source", 0.0)
	s.stops_movement = Tuning.get_optional(file, section, "stops_movement", false)
	s.stuns = Tuning.get_optional(file, section, "stuns", false)
	s.silences = Tuning.get_optional(file, section, "silences", false)
	s.healing_taken = Tuning.get_optional(file, section, "healing_taken", 0.0)
	s.healing_dealt = Tuning.get_optional(file, section, "healing_dealt", 0.0)
	s.absorbs = Tuning.get_optional(file, section, "absorbs", false)
	s.hit_heal = Tuning.get_optional(file, section, "hit_heal", 0.0)
	s.hit_heal_radius = Tuning.get_optional(file, section, "hit_heal_radius", 0.0)
	s.damage_share = clampf(Tuning.get_optional(file, section, "damage_share", 0.0), 0.0, 1.0)
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
	s.blind = clampf(Tuning.get_optional(file, section, "blind", 0.0), 0.0, 1.0)
	s.roll_zone = Tuning.get_optional(file, section, "roll_zone", "")
	s.veils = Tuning.get_optional(file, section, "veils", false)
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

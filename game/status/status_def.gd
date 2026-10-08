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

# Damage effects (server)
## Per stack: fraction more damage taken / dealt.
var damage_taken := 0.0
var damage_dealt := 0.0
## Per stack: damage dealt every tick_interval_ticks (0 = no damage over time).
var damage_per_interval := 0.0
var tick_interval_ticks := 0
## The owner's damaging hits apply this status (id) with on_hit_stacks stacks.
var on_hit_status := ""
var on_hit_stacks := 0
## Each such hit uses up one stack of this status.
var consume_on_hit := false


func is_debuff() -> bool:
	return category == CATEGORY_DEBUFF


func deals_damage_over_time() -> bool:
	return damage_per_interval > 0.0 and tick_interval_ticks > 0


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
	s.damage_taken = Tuning.get_optional(file, section, "damage_taken", 0.0)
	s.damage_dealt = Tuning.get_optional(file, section, "damage_dealt", 0.0)
	var per_second: float = Tuning.get_optional(file, section, "damage_per_second", 0.0)
	if per_second > 0.0:
		s.tick_interval_ticks = maxi(1, roundi(Tuning.get_value(file, section, "tick_interval") * tps))
		s.damage_per_interval = per_second * s.tick_interval_ticks / tps
	s.on_hit_status = Tuning.get_optional(file, section, "on_hit_status", "")
	s.on_hit_stacks = Tuning.get_optional(file, section, "on_hit_stacks", 1)
	s.consume_on_hit = Tuning.get_optional(file, section, "consume_on_hit", false)
	return s

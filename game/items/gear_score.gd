class_name GearScore
extends RefCounted
## Gear score math (data/gear.cfg), New World's curves: an item's main stat
## (weapon power, wing power, armor) grows by a compounding step per `step` gear
## score, slower above the soft cap; armor's damage reduction depends on the
## attacker's weapon gear score. Pure, unit tested (tests/test_equipment.gd).
## Tests build their own; the defaults are the real numbers.

var base := 100
var step := 5
var growth := 0.0112
var soft_cap := 500
var above_cap_fraction := 0.6667
var armor_gs_exponent := 1.2
## Shown in the inventory: your reduction against an attacker of this gear score.
var ui_attacker_gear_score := 120
## Ticks it takes to equip or take off a piece of gear.
var equip_ticks := 60
## Equip slot (Equipment.SLOTS) -> weight in the average gear score.
var average_weights: Dictionary = {}

static var _current: GearScore


static func current() -> GearScore:
	if _current == null:
		_current = from_tuning()
	return _current


static func from_tuning() -> GearScore:
	var g := GearScore.new()
	g.base = Tuning.get_value("gear", "gear_score", "base")
	g.step = maxi(1, Tuning.get_value("gear", "gear_score", "step"))
	g.growth = Tuning.get_value("gear", "gear_score", "growth")
	g.soft_cap = Tuning.get_value("gear", "gear_score", "soft_cap")
	g.above_cap_fraction = Tuning.get_value("gear", "gear_score", "above_cap_fraction")
	g.armor_gs_exponent = Tuning.get_value("gear", "armor", "gs_exponent")
	g.ui_attacker_gear_score = Tuning.get_value("gear", "armor", "ui_attacker_gear_score")
	g.equip_ticks = roundi(Tuning.get_value("gear", "equip", "time") * Engine.physics_ticks_per_second)
	g.average_weights = Tuning.get_value("gear", "average", "weights")
	return g


## How much an item's main stat is multiplied at this gear score: 1 at `base`
## (and below), x (1 + growth) per whole step up to the soft cap, then
## x (1 + growth x above_cap_fraction) per step above it.
func factor(gear_score: int) -> float:
	var below_cap := maxi(0, mini(gear_score, soft_cap) - base) / step
	var result := pow(1.0 + growth, below_cap)
	if gear_score > soft_cap:
		var above_cap := (gear_score - maxi(soft_cap, base)) / step
		result *= pow(1.0 + growth * above_cap_fraction, above_cap)
	return result


## Fraction of a hit's damage that `armor` stops against an attacker whose
## weapon has `attacker_gear_score`: armor / (armor + attacker_gs ^ exponent).
func mitigation(armor: float, attacker_gear_score: int) -> float:
	if armor <= 0.0:
		return 0.0
	return armor / (armor + pow(maxf(1.0, attacker_gear_score), armor_gs_exponent))

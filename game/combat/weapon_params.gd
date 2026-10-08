class_name WeaponParams
extends RefCounted
## One weapon's tuning in simulation units, from data/weapon_<id>.cfg: its light
## and heavy attacks and its ability pool. Tests build their own.

## Abilities per weapon, at most. PlayerState keeps a cooldown per pool entry.
const MAX_ABILITIES := 8

var id := ""
var display_name := ""
## Placeholder model to draw ("sword_shield", "dual_axes"). Cosmetic only.
var model := ""
var light_attack: AttackParams
var heavy_attack: AttackParams
var attack_buffer_ticks := 0
## Radians per second the facing tracks the aim during an attack.
var attack_turn_speed := 0.0
## Ticks the attack button must be held for a heavy attack.
var heavy_hold_ticks := 0
## Multiplies the stamina a blocked hit costs while this weapon is out.
var block_stamina_multiplier := 1.0
## The ability pool; PlayerState refers to abilities by index into it.
var abilities: Array[AbilityParams] = []


## The params for PlayerState.ATTACK_LIGHT / ATTACK_HEAVY, or null.
func attack(attack_type: int) -> AttackParams:
	match attack_type:
		PlayerState.ATTACK_LIGHT:
			return light_attack
		PlayerState.ATTACK_HEAVY:
			return heavy_attack
	return null


func ability(index: int) -> AbilityParams:
	return abilities[index] if index >= 0 and index < abilities.size() else null


func ability_index(ability_id: String) -> int:
	for i in abilities.size():
		if abilities[i].id == ability_id:
			return i
	return -1


static func from_tuning(weapon_id: String, tps: float) -> WeaponParams:
	var file := "weapon_" + weapon_id
	var w := WeaponParams.new()
	w.id = weapon_id
	w.display_name = Tuning.get_value(file, "weapon", "name")
	w.model = Tuning.get_value(file, "weapon", "model")
	w.block_stamina_multiplier = Tuning.get_value(file, "weapon", "block_stamina_multiplier")
	w.light_attack = AttackParams.from_tuning(file, "light", tps)
	w.heavy_attack = AttackParams.from_tuning(file, "heavy", tps)
	w.attack_buffer_ticks = roundi(Tuning.get_value(file, "attacks", "buffer") * tps)
	w.attack_turn_speed = deg_to_rad(Tuning.get_value(file, "attacks", "turn_speed"))
	w.heavy_hold_ticks = roundi(Tuning.get_value(file, "attacks", "heavy_hold_time") * tps)
	var ability_ids: Array = Tuning.get_value(file, "weapon", "abilities")
	for ability_id: String in ability_ids:
		if w.abilities.size() >= MAX_ABILITIES:
			push_error("%s.cfg: more than %d abilities" % [file, MAX_ABILITIES])
			break
		w.abilities.append(AbilityParams.ability_from_tuning(file, ability_id, tps))
	return w

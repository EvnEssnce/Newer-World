class_name WingParams
extends RefCounted
## One class's Wing abilities (data/wings_<class>.cfg): the pool the two Wing
## slots (Z / C) pick from. Same ability format as a weapon's pool, plus each
## ability's ember_cost. PlayerState refers to them by index into `abilities`.
## Tests build their own.

var id := ""
var display_name := ""
var abilities: Array[AbilityParams] = []


func ability(index: int) -> AbilityParams:
	return abilities[index] if index >= 0 and index < abilities.size() else null


func ability_index(ability_id: String) -> int:
	for i in abilities.size():
		if abilities[i].id == ability_id:
			return i
	return -1


## class_id: the class whose data/wings_<class_id>.cfg to load.
static func from_tuning(class_id: String, tps: float) -> WingParams:
	var file := "wings_" + class_id
	var w := WingParams.new()
	w.id = class_id
	w.display_name = Tuning.get_value(file, "wings", "name")
	var ability_ids: Array = Tuning.get_value(file, "wings", "abilities")
	for ability_id: String in ability_ids:
		if w.abilities.size() >= WeaponParams.MAX_ABILITIES:
			push_error("%s.cfg: more than %d abilities" % [file, WeaponParams.MAX_ABILITIES])
			break
		w.abilities.append(AbilityParams.ability_from_tuning(file, ability_id, tps))
	return w

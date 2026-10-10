class_name StatusDefs
extends RefCounted
## Every status effect (data/status_effects.cfg), in file order. StatusEffects
## and the network refer to a status by its index here, so the server and
## clients must read the same file. Tests build their own with add().

const FILE := "status_effects"

var defs: Array[StatusDef] = []

static var _current: StatusDefs


## The game's statuses, loaded once. Tuning edits need a restart.
static func current() -> StatusDefs:
	if _current == null:
		_current = from_tuning()
	return _current


static func from_tuning() -> StatusDefs:
	var tps := float(Engine.physics_ticks_per_second)
	var d := StatusDefs.new()
	for section in Tuning.get_sections(FILE):
		if section.begins_with("status_"):
			d.add(StatusDef.from_tuning(FILE, section.trim_prefix("status_"), tps))
	var error := d.validate()
	if not error.is_empty():
		push_error("%s.cfg: %s" % [FILE, error])
	return d


## Adds a status and returns its index.
func add(def: StatusDef) -> int:
	defs.append(def)
	return defs.size() - 1


func get_def(index: int) -> StatusDef:
	return defs[index] if index >= 0 and index < defs.size() else null


## The index of a status id, or -1 ("" or unknown).
func index_of(status_id: String) -> int:
	for i in defs.size():
		if defs[i].id == status_id:
			return i
	return -1


## Checks the definitions make sense together. "" if fine, else the first problem.
func validate() -> String:
	for def in defs:
		if not def.category in [StatusDef.CATEGORY_BUFF, StatusDef.CATEGORY_DEBUFF]:
			return "%s: category must be \"buff\" or \"debuff\"" % def.id
		if not def.affects in [StatusDef.AFFECTS_SIM, StatusDef.AFFECTS_DAMAGE]:
			return "%s: affects must be \"sim\" or \"damage\"" % def.id
		var sim_effect := (def.move_multiplier != 1.0 or def.stops_movement or def.stuns
				or def.silences
				or def.attack_speed != 1.0 or def.dodge_speed_multiplier != 1.0
				or def.dodge_cost_multiplier != 1.0 or def.fall_gravity_multiplier != 1.0)
		if sim_effect and def.affects != StatusDef.AFFECTS_SIM:
			return "%s: changes movement or actions, so affects must be \"sim\"" % def.id
		if def.move_multiplier < 0.0:
			return "%s: move_multiplier can't be negative" % def.id
		if (def.dodge_speed_multiplier <= 0.0 or def.dodge_cost_multiplier < 0.0
				or def.fall_gravity_multiplier < 0.0):
			return "%s: dodge and gravity multipliers must be positive" % def.id
		if def.forces_target and not def.is_debuff():
			return "%s: forces_target (a taunt) must be a debuff" % def.id
		if def.attack_speed < 1.0 or def.attack_speed > 2.0:
			return "%s: attack_speed must be between 1 and 2" % def.id
		if def.cover_depth < 0.0 or def.cover_width < 0.0:
			return "%s: cover_depth and cover_width can't be negative" % def.id
		if def.charge_stagger_ticks < 0 or def.charge_window_ticks < 0:
			return "%s: charge_stagger and charge_window can't be negative" % def.id
		if def.crowd_damage_taken != 0.0 and (def.crowd_radius <= 0.0 or def.crowd_max <= 0):
			return "%s: crowd_damage_taken needs a crowd_radius and crowd_max above 0" % def.id
		if not def.on_hit_status.is_empty() and index_of(def.on_hit_status) < 0:
			return "%s: on_hit_status \"%s\" doesn't exist" % [def.id, def.on_hit_status]
	return ""

class_name GatherNodeParams
extends RefCounted
## One kind of gathering node, from a [node_<kind>] section of data/gathering.cfg
## (every key explained there), in simulation units (ticks). Tests build their own.

const PREFIX := "node_"

static var _kinds: Dictionary[String, GatherNodeParams] = {}
static var _version := -1
static var _range_tolerance := 0.75

## The kind id (the section name without "node_"; a marker's metadata/kind).
var id := ""
var name := ""
## The prompt's verb ("Mine").
var action := "Gather"
## The resource item id (data/items.cfg, slot="resource").
var resource := ""
## The tradeskill a gather counts toward (mining, logging, harvesting).
var tradeskill := ""
var yield_min := 1
var yield_max := 1
## Gathers before it's depleted.
var charges := 1
var gather_ticks := 60
var respawn_ticks := 3600
## Meters (horizontal) from its center it can be gathered from.
var reach := 2.5
var visual := ""


## Ticks one gather takes with a tradeskill time multiplier (at least 1).
func ticks_for(multiplier: float) -> int:
	return maxi(1, roundi(gather_ticks * maxf(0.0, multiplier)))


## Resources one gather gives: yield_min..yield_max plus a tradeskill bonus.
func roll_yield(rng: RandomNumberGenerator, bonus: int) -> int:
	return maxi(0, rng.randi_range(yield_min, maxi(yield_min, yield_max)) + bonus)


## Problems with this kind against the item definitions; empty when fine.
func validate(db: ItemDatabase) -> PackedStringArray:
	var problems := PackedStringArray()
	var def: ItemDatabase.ItemDef = db.items.get(resource)
	if def == null:
		problems.append("node '%s' gives unknown item '%s'" % [id, resource])
	elif not def.is_resource():
		problems.append("node '%s' gives '%s', which isn't a resource" % [id, resource])
	if yield_min < 1 or yield_max < yield_min:
		problems.append("node '%s' needs 1 <= yield_min <= yield_max" % id)
	if charges < 1 or gather_ticks < 1 or reach <= 0.0:
		problems.append("node '%s' needs charges, gather_time and range above 0" % id)
	if tradeskill.is_empty():
		problems.append("node '%s' has no tradeskill" % id)
	return problems


## The kind, or null if data/gathering.cfg has no such section.
static func get_kind(kind: String) -> GatherNodeParams:
	_load()
	return _kinds.get(kind)


static func all_kinds() -> Array[GatherNodeParams]:
	_load()
	var kinds: Array[GatherNodeParams] = []
	kinds.assign(_kinds.values())
	return kinds


## [gather] range_tolerance (m).
static func range_tolerance() -> float:
	_load()
	return _range_tolerance


static func _load() -> void:
	if _version == Tuning.version:
		return
	_version = Tuning.version
	_kinds.clear()
	if not Tuning.has_file("gathering"):
		return
	var tps := float(Engine.physics_ticks_per_second)
	_range_tolerance = Tuning.get_value("gathering", "gather", "range_tolerance")
	for section in Tuning.get_sections("gathering"):
		if not section.begins_with(PREFIX):
			continue
		var p := GatherNodeParams.new()
		p.id = section.trim_prefix(PREFIX)
		p.name = Tuning.get_value("gathering", section, "name")
		p.action = Tuning.get_optional("gathering", section, "action", "Gather")
		p.resource = Tuning.get_value("gathering", section, "resource")
		p.tradeskill = Tuning.get_value("gathering", section, "tradeskill")
		p.yield_min = Tuning.get_value("gathering", section, "yield_min")
		p.yield_max = Tuning.get_value("gathering", section, "yield_max")
		p.charges = Tuning.get_value("gathering", section, "charges")
		p.gather_ticks = maxi(1, roundi(float(Tuning.get_value("gathering", section, "gather_time")) * tps))
		p.respawn_ticks = maxi(1, roundi(float(Tuning.get_value("gathering", section, "respawn_time")) * tps))
		p.reach = Tuning.get_value("gathering", section, "range")
		p.visual = Tuning.get_optional("gathering", section, "visual", p.id)
		_kinds[p.id] = p

class_name ZoneParams
extends RefCounted
## One kind of ground zone or summon (the AREA and SUMMON tags), from a
## [zone_<id>] section of data/zones.cfg, in simulation units (ticks).
## Explained key by key in that file. Tests build their own.

const AFFECTS_HOSTILE := "hostile"
const AFFECTS_ALLY := "ally"
const TRIGGER_PULSE := "pulse"
const TRIGGER_TRAP := "trap"
const TRIGGER_NONE := "none"

static var _kinds: Dictionary[String, ZoneParams] = {}

var id := ""
## Circle radius (m), and how far above or below its center a target's feet may
## be and still count.
var radius := 1.0
var height := 2.0
var duration_ticks := 60
## "pulse": every interval_ticks (the first after first_pulse_ticks) its effect
## reaches everything of `affects` inside. "trap": once armed (arm_ticks), the
## first hostile inside triggers it once; then it re-arms (rearms) or ends.
## "none": no effect of its own (a decoy, a wall).
var trigger := TRIGGER_PULSE
var interval_ticks := 30
var first_pulse_ticks := 0
var arm_ticks := 0
var rearms := 0
var affects := AFFECTS_HOSTILE
## Per pulse (or trigger): damage, healing, and a status.
var damage := 0.0
var heal := 0.0
var applies_status := ""
var status_stacks := 1
var status_duration_ticks := -1
## Decoy: while it lasts, enemies see its owner standing here.
var decoy := false
## Wall: a box width x depth x height (m) across the owner's facing that
## enemies can't walk through and hostile projectiles stop at.
var wall := false
var wall_width := 0.0
var wall_depth := 0.0
## Client look: "disc", "cloud", "rain", "trap", "decoy" or "wall", and its color.
var visual := "disc"
var color := Color.WHITE


static func get_kind(kind: String) -> ZoneParams:
	if _kinds.is_empty() and Tuning.has_file("zones"):
		var tps := float(Engine.physics_ticks_per_second)
		for section in Tuning.get_sections("zones"):
			if section.begins_with("zone_"):
				var p := from_tuning(section.trim_prefix("zone_"), tps)
				_kinds[p.id] = p
	return _kinds.get(kind)


static func from_tuning(kind: String, tps: float) -> ZoneParams:
	var f := "zones"
	var s := "zone_" + kind
	var p := ZoneParams.new()
	p.id = kind
	p.radius = Tuning.get_value(f, s, "radius")
	p.height = Tuning.get_optional(f, s, "height", 2.0)
	p.duration_ticks = maxi(1, roundi(float(Tuning.get_value(f, s, "duration")) * tps))
	p.trigger = Tuning.get_optional(f, s, "trigger", TRIGGER_PULSE)
	p.interval_ticks = maxi(1, roundi(float(Tuning.get_optional(f, s, "interval", 0.5)) * tps))
	p.first_pulse_ticks = roundi(float(Tuning.get_optional(f, s, "first_pulse", 0.0)) * tps)
	p.arm_ticks = roundi(float(Tuning.get_optional(f, s, "arm_time", 0.0)) * tps)
	p.rearms = Tuning.get_optional(f, s, "rearms", 0)
	p.affects = Tuning.get_optional(f, s, "affects", AFFECTS_HOSTILE)
	p.damage = Tuning.get_optional(f, s, "damage", 0.0)
	p.heal = Tuning.get_optional(f, s, "heal", 0.0)
	p.applies_status = Tuning.get_optional(f, s, "applies_status", "")
	p.status_stacks = Tuning.get_optional(f, s, "status_stacks", 1)
	var duration: float = Tuning.get_optional(f, s, "status_duration", -1.0)
	p.status_duration_ticks = roundi(duration * tps) if duration > 0.0 else -1
	p.decoy = Tuning.get_optional(f, s, "decoy", false)
	p.wall = Tuning.get_optional(f, s, "wall", false)
	p.wall_width = Tuning.get_optional(f, s, "width", 0.0)
	p.wall_depth = Tuning.get_optional(f, s, "depth", 0.0)
	p.visual = Tuning.get_optional(f, s, "visual", "disc")
	p.color = Tuning.get_optional(f, s, "color", Color.WHITE)
	return p

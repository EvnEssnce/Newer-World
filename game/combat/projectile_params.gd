class_name ProjectileParams
extends RefCounted
## One projectile kind's tuning in simulation units (ticks, meters, radians),
## from a [projectile_<id>] section of data/projectiles.cfg. Server and clients
## read the same file. Tests build their own.

const FILE := "projectiles"
const VISUAL_FEATHER := "feather"
const VISUAL_AXE := "axe"

var id := ""
## Meters per second at launch.
var speed := 0.0
## Meters per second squared, pulling down. 0 = straight.
var gravity := 0.0
## Radians above horizontal at launch.
var pitch := 0.0
## Ticks before it ends if nothing stopped it (the whole round trip for a
## returning one).
var lifetime_ticks := 1
## Meters, added to a target's body radius in hit tests.
var hit_radius := 0.0
## Targets it passes through before stopping (per leg for a returning one).
var pierce := 0
## The world (layer 1) stops it (a returning one turns back instead, and passes
## through the world on its way back).
var walls := true
## A blocked or parried hit stops it.
var stopped_by_guard := true
## Release point: meters above the thrower's feet, meters in front of its center.
var release_height := 1.3
var release_forward := 0.3
## Returning (a boomerang): turns after return_after_ticks and flies back at
## return_speed toward its thrower, caught within catch_radius.
var returns := false
var return_after_ticks := 0
var return_speed := 0.0
var catch_radius := 0.8
# Cosmetic
var visual := VISUAL_FEATHER
var length := 1.0
var color := Color.WHITE
## Radians per second around the vertical axis.
var spin := 0.0

static var _kinds: Dictionary[String, ProjectileParams] = {}
static var _loaded := false


## The kind with this id from data/projectiles.cfg (loaded once), or null.
static func get_kind(kind_id: String) -> ProjectileParams:
	if not _loaded:
		_loaded = true
		var tps := float(Engine.physics_ticks_per_second)
		for section in Tuning.get_sections(FILE):
			if section.begins_with("projectile_"):
				var p := from_tuning(section.trim_prefix("projectile_"), tps)
				var error := p.validate()
				if not error.is_empty():
					push_error("%s.cfg: %s" % [FILE, error])
				_kinds[p.id] = p
	return _kinds.get(kind_id)


static func from_tuning(kind_id: String, tps: float) -> ProjectileParams:
	var section := "projectile_" + kind_id
	var p := ProjectileParams.new()
	p.id = kind_id
	p.speed = Tuning.get_value(FILE, section, "speed")
	p.gravity = Tuning.get_value(FILE, section, "gravity")
	p.pitch = deg_to_rad(Tuning.get_optional(FILE, section, "pitch", 0.0))
	p.lifetime_ticks = maxi(1, roundi(Tuning.get_value(FILE, section, "lifetime") * tps))
	p.hit_radius = Tuning.get_value(FILE, section, "hit_radius")
	p.pierce = Tuning.get_value(FILE, section, "pierce")
	p.walls = Tuning.get_value(FILE, section, "walls")
	p.stopped_by_guard = Tuning.get_value(FILE, section, "stopped_by_guard")
	p.release_height = Tuning.get_value(FILE, section, "release_height")
	p.release_forward = Tuning.get_value(FILE, section, "release_forward")
	p.returns = Tuning.get_optional(FILE, section, "returns", false)
	if p.returns:
		p.return_after_ticks = maxi(1, roundi(Tuning.get_value(FILE, section, "return_after") * tps))
		p.return_speed = Tuning.get_value(FILE, section, "return_speed")
		p.catch_radius = Tuning.get_value(FILE, section, "catch_radius")
	p.visual = Tuning.get_value(FILE, section, "visual")
	p.length = Tuning.get_value(FILE, section, "length")
	p.color = Tuning.get_value(FILE, section, "color")
	p.spin = deg_to_rad(Tuning.get_optional(FILE, section, "spin", 0.0))
	return p


## Meters it reaches on flat ground before ending (lifetime) or turning back
## (a returning one), ignoring gravity. For the test bot's aim.
func reach() -> float:
	var ticks := return_after_ticks if returns else lifetime_ticks
	return speed * ticks / float(Engine.physics_ticks_per_second)


## "" if the values make sense, else the first problem.
func validate() -> String:
	if speed <= 0.0:
		return "%s: speed must be above 0" % id
	if hit_radius < 0.0 or pierce < 0:
		return "%s: hit_radius and pierce can't be negative" % id
	if returns and (return_speed <= 0.0 or return_after_ticks >= lifetime_ticks):
		return "%s: a returning projectile needs return_speed > 0 and return_after < lifetime" % id
	if not visual in [VISUAL_FEATHER, VISUAL_AXE]:
		return "%s: visual must be \"feather\" or \"axe\"" % id
	return ""

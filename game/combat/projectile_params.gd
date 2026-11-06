class_name ProjectileParams
extends RefCounted
## One projectile kind's tuning in simulation units (ticks, meters, radians),
## from a [projectile_<id>] section of data/projectiles.cfg. Server and clients
## read the same file. Tests build their own.

const FILE := "projectiles"
const VISUAL_FEATHER := "feather"
const VISUAL_AXE := "axe"
## A crescent rolling along the ground (Shockwave).
const VISUAL_WAVE := "wave"

var id := ""
## Meters per second at launch.
var speed := 0.0
## Meters per second squared, pulling down. 0 = straight.
var gravity := 0.0
## Radians above the aim at launch (above horizontal for an aim_pitch=false kind).
var pitch := 0.0
## Flies toward the aim point, up or down (AimRay); false = only its heading,
## launched level (a ground wave: Shockwave).
var aim_pitch := true
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
## How strongly it glows: scales its halo and trail (ProjectileVisual). 0 = none.
var glow := 1.0
## Server-side flight extras. bounces: after a hit that would stop it, it flies
## on to the nearest target it hasn't hit within bounce_range m, this many times
## (Ricochet). homing_turn: radians per second it turns toward the nearest
## hostile in front within homing_range m (Seeker Spark).
var bounces := 0
var bounce_range := 0.0
var homing_turn := 0.0
var homing_range := 0.0
## false = cosmetic: it flies (and is caught) but never hits anyone and nothing
## stops it, walls included (Recall's knives flying home).
var hits := true

static var _kinds: Dictionary[String, ProjectileParams] = {}
## Tuning.version the kinds were loaded from (-1 = not yet).
static var _loaded_version := -1


## The kind with this id from data/projectiles.cfg (loaded once, again when
## Tuning.version moves), or null.
static func get_kind(kind_id: String) -> ProjectileParams:
	if _loaded_version != Tuning.version:
		_loaded_version = Tuning.version
		_kinds.clear()
		var tps := float(Engine.physics_ticks_per_second)
		for section in Tuning.get_sections(FILE):
			if section.begins_with("projectile_"):
				var p := from_tuning(section.trim_prefix("projectile_"), tps)
				var error := p.validate()
				if not error.is_empty():
					push_error("%s.cfg: %s" % [FILE, error])
				_kinds[p.id] = p
	return _kinds.get(kind_id)


## Every kind in data/projectiles.cfg (for warming up their looks).
static func all_kinds() -> Array[ProjectileParams]:
	get_kind("")
	var kinds: Array[ProjectileParams] = []
	kinds.assign(_kinds.values())
	return kinds


static func from_tuning(kind_id: String, tps: float) -> ProjectileParams:
	var section := "projectile_" + kind_id
	var p := ProjectileParams.new()
	p.id = kind_id
	p.speed = _value(section, "speed")
	p.gravity = _value(section, "gravity")
	p.pitch = deg_to_rad(_optional(section, "pitch", 0.0))
	p.aim_pitch = _optional(section, "aim_pitch", true)
	p.lifetime_ticks = maxi(1, roundi(_value(section, "lifetime") * tps))
	p.hit_radius = _value(section, "hit_radius")
	p.pierce = _value(section, "pierce")
	p.walls = _value(section, "walls")
	p.stopped_by_guard = _value(section, "stopped_by_guard")
	p.release_height = _value(section, "release_height")
	p.release_forward = _value(section, "release_forward")
	p.returns = _optional(section, "returns", false)
	if p.returns:
		p.return_after_ticks = maxi(1, roundi(_value(section, "return_after") * tps))
		p.return_speed = _value(section, "return_speed")
		p.catch_radius = _value(section, "catch_radius")
	p.visual = _value(section, "visual")
	p.length = _value(section, "length")
	p.color = _value(section, "color")
	p.spin = deg_to_rad(_optional(section, "spin", 0.0))
	p.glow = maxf(0.0, _optional(section, "glow", 1.0))
	p.bounces = _optional(section, "bounces", 0)
	p.bounce_range = _optional(section, "bounce_range", 0.0)
	p.homing_turn = deg_to_rad(_optional(section, "homing_turn", 0.0))
	p.homing_range = _optional(section, "homing_range", 0.0)
	p.hits = _optional(section, "hits", true)
	return p


## The most `like` links followed (a loop of them is an error, not a hang).
const MAX_LIKE_DEPTH := 8


## The section `key` is read from: the kind's own, else the kind its `like` key
## names (and so on: a kind that copies another and changes only what it lists,
## e.g. an ability's arrow in its own color). "" if none has it.
static func _source(section: String, key: String) -> String:
	var current := section
	for i in MAX_LIKE_DEPTH:
		if Tuning.has_value(FILE, current, key):
			return current
		if not Tuning.has_value(FILE, current, "like"):
			return ""
		current = "projectile_" + str(Tuning.get_value(FILE, current, "like"))
	push_error("%s.cfg: [%s] has a loop of like keys (or more than %d)" % [FILE, section, MAX_LIKE_DEPTH])
	return ""


static func _value(section: String, key: String) -> Variant:
	var source := _source(section, key)
	return Tuning.get_value(FILE, section if source.is_empty() else source, key)


static func _optional(section: String, key: String, default: Variant) -> Variant:
	var source := _source(section, key)
	return default if source.is_empty() else Tuning.get_value(FILE, source, key)


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
	if not visual in [VISUAL_FEATHER, VISUAL_AXE, VISUAL_WAVE]:
		return "%s: visual must be \"feather\", \"axe\" or \"wave\"" % id
	return ""

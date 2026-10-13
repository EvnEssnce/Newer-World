class_name BeamVisual
extends Node3D
## Client look of a beam attack (an attack with `beam_color`: Searing Ray,
## Mending Beam, Siphon, Ward, Withering Touch, the Gauntlet heavy, Searing
## Glare). Purely cosmetic: Player._show hands it the attack and its tick from
## the (predicted or interpolated) PlayerState every frame, so everyone sees
## everyone's beams. A child of the player's model, so it follows the facing.
##
## Windup: a faint beam reaching out from the hands while an orb gathers there.
## Hit windows: bright, flaring at the start of each window (a channel pulses).
## Recovery: fades out. Drawn as a bright core inside a soft sheath as wide as
## the hitbox, from the hands to the hitbox's far end.

## Where the beam starts, in model space: the hands (the staff's orb and the
## gauntlet both sit on this line), chest high.
const START := Vector3(0.35, 1.15, -0.45)
## Radius of the bright core (m).
const CORE_RADIUS := 0.08
## The sheath is as wide as the hitbox, but at most this tall (radius, m).
const SHEATH_MAX_HEIGHT := 0.45
## Radius of the orb at the hands, and of the glow at the far end (m).
const ORB_RADIUS := 0.24
const TIP_RADIUS := 0.35
## Ticks a hit window's flare takes to settle (about 1/e).
const FLARE_TICKS := 7.0
## The fade at the start of recovery lasts at most this many ticks.
const FADE_TICKS := 15.0

var _core := MeshInstance3D.new()
var _sheath := MeshInstance3D.new()
var _orb := MeshInstance3D.new()
var _tip := MeshInstance3D.new()
var _core_material := _beam_material()
var _sheath_material := _beam_material()
var _orb_material := _beam_material()


func _init() -> void:
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 1.0
	cylinder.bottom_radius = 1.0
	cylinder.height = 1.0
	cylinder.radial_segments = 16
	cylinder.rings = 1
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 16
	sphere.rings = 8
	for part: Array in [[_sheath, cylinder, _sheath_material], [_core, cylinder, _core_material],
			[_orb, sphere, _orb_material], [_tip, sphere, _orb_material]]:
		var instance: MeshInstance3D = part[0]
		instance.mesh = part[1]
		instance.material_override = part[2]
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)
	visible = false


## Shows `attack` at `tick` (from its start; fractional while interpolated),
## or hides when it's null, not started or has no beam.
func update(attack: AttackParams, tick: float) -> void:
	if attack == null or tick < 0.0 or attack.beam_color.a <= 0.0:
		visible = false
		return
	var windup := float(attack.windup_ticks)
	var recovery_start := float(attack.recovery_start_tick())
	var reach := 1.0  # fraction of the length drawn
	var glow := 0.0  # 0..1 brightness
	var thickness := 1.0
	var charge := 1.0  # the orb at the hands
	var tip := 0.0
	if tick < windup:
		var t := tick / maxf(1.0, windup)
		reach = 1.0 - pow(1.0 - t, 3.0)
		glow = 0.12 + 0.25 * t
		thickness = 0.35
		charge = t
	elif tick < recovery_start:
		var since := fmod(tick - windup, float(maxi(1, attack.window_interval_ticks)))
		var flare := exp(-since / FLARE_TICKS)
		glow = 0.65 + 0.35 * flare
		thickness = 0.8 + 0.3 * flare
		tip = 0.7 + 0.5 * flare
	else:
		var fade := FADE_TICKS if attack.recovery_ticks <= 0 else minf(FADE_TICKS, float(attack.recovery_ticks))
		var t := (tick - recovery_start) / maxf(1.0, fade)
		if t >= 1.0:
			visible = false
			return
		glow = 0.65 * (1.0 - t)
		thickness = 1.0 - 0.6 * t
		charge = 1.0 - t
		tip = 0.7 * (1.0 - t)
	visible = true
	_draw(attack, reach, glow, thickness, charge, tip)


## Prewarm (ZoneSystem._prewarm_step): drawn fully transparent, so the GPU
## compiles the beam's shader before the first cast.
func show_invisible() -> void:
	var a := AttackParams.new()
	a.hitbox_range = 3.0
	a.hitbox_width = 1.0
	a.beam_color = Color.WHITE
	visible = true
	_draw(a, 1.0, 0.0, 1.0, 1.0, 1.0)


func _draw(attack: AttackParams, reach: float, glow: float, thickness: float, charge: float,
		tip: float) -> void:
	var color := attack.beam_color
	var length := maxf(0.3, (attack.hitbox_range + START.z) * reach)
	var half_width := maxf(CORE_RADIUS * 2.0, attack.hitbox_width / 2.0)
	_place_along(_core, length, CORE_RADIUS * thickness, CORE_RADIUS * thickness)
	_place_along(_sheath, length, half_width * thickness,
			minf(half_width, SHEATH_MAX_HEIGHT) * thickness)
	var orb := ORB_RADIUS * (0.3 + 0.7 * charge) * (0.85 + 0.3 * glow)
	_orb.transform = Transform3D(Basis.from_scale(Vector3.ONE * orb), START)
	_tip.visible = tip > 0.0
	_tip.transform = Transform3D(Basis.from_scale(Vector3.ONE * maxf(0.01, TIP_RADIUS * tip)),
			START + Vector3(0.0, 0.0, -length))
	_core_material.albedo_color = Color(color.lerp(Color.WHITE, 0.55), glow * color.a)
	_sheath_material.albedo_color = Color(color, glow * 0.35 * color.a)
	_orb_material.albedo_color = Color(color.lerp(Color.WHITE, 0.3), glow * 0.8 * color.a)


## A unit cylinder lying from START toward -Z for `length`, with these radii
## across (x) and up (y).
func _place_along(instance: MeshInstance3D, length: float, across: float, up: float) -> void:
	# The cylinder's axis is its Y: turned a quarter about X it points along Z,
	# and its own Z (scaled by `up`) then points down.
	var turned := Basis(Vector3.RIGHT, PI / 2.0) * Basis.from_scale(Vector3(across, length, up))
	instance.transform = Transform3D(turned, START + Vector3(0.0, 0.0, -length / 2.0))


## Unshaded, see-through and two-sided: one shader for every part, so one
## prewarm covers them all. Mixed rather than additive, so a beam keeps its
## color against the bright ground and sky.
static func _beam_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(1.0, 1.0, 1.0, 0.0)
	return m

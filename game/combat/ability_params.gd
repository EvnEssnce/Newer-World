class_name AbilityParams
extends AttackParams
## One weapon ability's tuning in simulation units, from an [ability_<id>]
## section of data/weapon_<weapon>.cfg (or a Wing ability's, from
## data/wings_<class>.cfg). An ability runs like an attack (windup,
## hit windows, recovery) and adds a cooldown, an optional dash, and optional
## parry. Tests build their own.

var id := ""
var display_name := ""
var cooldown_ticks := 0
## Radians per second the facing follows the aim during the ability; 0 = locked.
var turn_speed := 0.0
## Dash: moves the user forward at dash_speed (m/s) for ability ticks in
## [dash_start_tick, dash_end_tick). dash_speed 0 = no dash.
var dash_start_tick := 0
var dash_end_tick := 0
var dash_speed := 0.0
## The dash's speed ramps up from 0 over the dash (dash_ease="in": Diving
## Strike's swoop) instead of staying at dash_speed; the distance is the same.
var dash_ease_in := false
## The dash goes backward, away from where the ability faces.
var dash_backward := false
## The dash goes the way the movement input points as the ability starts;
## backward (away from the facing) with no input (Vault).
var dash_from_input := false
## The dash is aimed by the camera's pitch (Crashing Leap): at or below
## aim_full_pitch it goes the full distance, at or above aim_zero_pitch 0 m
## (straight up), scaled linearly in between. Radians, up = positive.
var dash_aim_pitch := false
var aim_full_pitch := 0.0
var aim_zero_pitch := 0.0
## I-frames: hits can't land in ability ticks [iframe_start_tick, iframe_end_tick).
## Equal = none.
var iframe_start_tick := 0
var iframe_end_tick := 0
## Peak height of a leap, meters. Cosmetic only.
var leap_height := 0.0
## Fraction of the dash at which the leap is highest (0.5 = a symmetric arc).
var leap_peak := 0.5
## A real jump (sim, unlike leap_height): launch_tick after the start the user
## is thrown upward fast enough to rise launch_height meters (Updraft). 0 = none.
var launch_height := 0.0
var launch_tick := 0
## Parry: during the hit windows, a hit from within parry_arc (full width,
## radians) in front is negated and answered with the `counter` ability.
var parry_arc := 0.0
var counter := ""
## Not slottable; only started by another ability (e.g. a parry's counter).
var internal := false
## Ember spent when it starts; it can't start with less (Wing abilities; 0 =
## free, as weapon abilities are so far).
var ember_cost := 0.0


func is_parry() -> bool:
	return parry_arc > 0.0


func has_iframes(tick: int) -> bool:
	return tick >= iframe_start_tick and tick < iframe_end_tick


func is_dashing(tick: int) -> bool:
	return dash_speed > 0.0 and tick >= dash_start_tick and tick < dash_end_tick


## The dash's speed (m/s) on this ability tick (one inside the dash). Eased in,
## the speed on dash tick i of n is dash_speed * (2i + 1) / n: the distance
## covered by the end of tick i grows with the square of the time, and the
## total is exactly the same as at a constant dash_speed.
func dash_speed_at(tick: int) -> float:
	if not dash_ease_in:
		return dash_speed
	var n := dash_end_tick - dash_start_tick
	return dash_speed * (2 * (tick - dash_start_tick) + 1) / float(n)


## Cosmetic height (meters) of a leap at this (fractional) ability tick: rises
## to leap_height at leap_peak of the dash, then falls back, each half a
## parabola. 0 outside the dash or without a leap.
func leap_lift(tick: float) -> float:
	if leap_height <= 0.0 or dash_speed <= 0.0:
		return 0.0
	var p := inverse_lerp(float(dash_start_tick), float(dash_end_tick), tick)
	if p < 0.0 or p > 1.0:
		return 0.0
	var peak := clampf(leap_peak, 0.01, 0.99)
	var off := (peak - p) / peak if p < peak else (p - peak) / (1.0 - peak)
	return leap_height * (1.0 - off * off)


## The fraction (0..1) of dash_distance a dash started at this camera pitch
## (radians, up = positive) covers. 1 unless dash_aim_pitch.
func dash_fraction(aim_pitch: float) -> float:
	if not dash_aim_pitch:
		return 1.0
	if aim_zero_pitch <= aim_full_pitch:
		return 1.0 if aim_pitch < aim_zero_pitch else 0.0
	return 1.0 - clampf(inverse_lerp(aim_full_pitch, aim_zero_pitch, aim_pitch), 0.0, 1.0)


static func ability_from_tuning(file: String, ability_id: String, tps: float) -> AbilityParams:
	var section := "ability_" + ability_id
	var a := AbilityParams.new()
	a.load_from(file, section, tps)
	a.id = ability_id
	a.display_name = Tuning.get_value(file, section, "name")
	a.cooldown_ticks = roundi(Tuning.get_value(file, section, "cooldown") * tps)
	a.turn_speed = deg_to_rad(Tuning.get_value(file, section, "turn_speed"))
	var dash_distance: float = Tuning.get_optional(file, section, "dash_distance", 0.0)
	if dash_distance > 0.0:
		a.dash_start_tick = roundi(Tuning.get_value(file, section, "dash_start") * tps)
		a.dash_end_tick = maxi(a.dash_start_tick + 1,
				roundi(Tuning.get_value(file, section, "dash_end") * tps))
		a.dash_speed = dash_distance / ((a.dash_end_tick - a.dash_start_tick) / tps)
		var direction: String = Tuning.get_optional(file, section, "dash_direction", "forward")
		a.dash_backward = direction == "back"
		a.dash_from_input = direction == "input"
		a.dash_ease_in = Tuning.get_optional(file, section, "dash_ease", "none") == "in"
		a.dash_aim_pitch = Tuning.get_optional(file, section, "dash_aim_pitch", false)
		if a.dash_aim_pitch:
			a.aim_full_pitch = deg_to_rad(Tuning.get_value(file, section, "aim_full_pitch"))
			a.aim_zero_pitch = deg_to_rad(Tuning.get_value(file, section, "aim_zero_pitch"))
	a.leap_height = Tuning.get_optional(file, section, "leap_height", 0.0)
	a.leap_peak = Tuning.get_optional(file, section, "leap_peak", 0.5)
	a.launch_height = Tuning.get_optional(file, section, "launch_height", 0.0)
	a.launch_tick = roundi(float(Tuning.get_optional(file, section, "launch_time", 0.0)) * tps)
	a.iframe_start_tick = roundi(float(Tuning.get_optional(file, section, "iframe_start", 0.0)) * tps)
	a.iframe_end_tick = roundi(float(Tuning.get_optional(file, section, "iframe_end", 0.0)) * tps)
	a.parry_arc = deg_to_rad(Tuning.get_optional(file, section, "parry_arc", 0.0))
	a.counter = Tuning.get_optional(file, section, "counter", "")
	a.internal = Tuning.get_optional(file, section, "internal", false)
	a.ember_cost = Tuning.get_optional(file, section, "ember_cost", 0.0)
	return a

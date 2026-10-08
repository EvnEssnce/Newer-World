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
## The dash goes backward, away from where the ability faces.
var dash_backward := false
## The dash goes the way the movement input points as the ability starts;
## backward (away from the facing) with no input (Vault).
var dash_from_input := false
## I-frames: hits can't land in ability ticks [iframe_start_tick, iframe_end_tick).
## Equal = none.
var iframe_start_tick := 0
var iframe_end_tick := 0
## Peak height of a leap, meters. Cosmetic only.
var leap_height := 0.0
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
	a.leap_height = Tuning.get_optional(file, section, "leap_height", 0.0)
	a.iframe_start_tick = roundi(float(Tuning.get_optional(file, section, "iframe_start", 0.0)) * tps)
	a.iframe_end_tick = roundi(float(Tuning.get_optional(file, section, "iframe_end", 0.0)) * tps)
	a.parry_arc = deg_to_rad(Tuning.get_optional(file, section, "parry_arc", 0.0))
	a.counter = Tuning.get_optional(file, section, "counter", "")
	a.internal = Tuning.get_optional(file, section, "internal", false)
	a.ember_cost = Tuning.get_optional(file, section, "ember_cost", 0.0)
	return a

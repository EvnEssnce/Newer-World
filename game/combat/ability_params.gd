class_name AbilityParams
extends AttackParams
## One weapon ability's tuning in simulation units, from an [ability_<id>]
## section of data/weapon_<weapon>.cfg. An ability runs like an attack (windup,
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
## The dash goes backward, away from where the ability faces (Vault).
var dash_backward := false
## Peak height of a leap, meters. Cosmetic only.
var leap_height := 0.0
## Parry: during the hit windows, a hit from within parry_arc (full width,
## radians) in front is negated and answered with the `counter` ability.
var parry_arc := 0.0
var counter := ""
## Not slottable; only started by another ability (e.g. a parry's counter).
var internal := false


func is_parry() -> bool:
	return parry_arc > 0.0


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
		a.dash_backward = Tuning.get_optional(file, section, "dash_direction", "forward") == "back"
	a.leap_height = Tuning.get_optional(file, section, "leap_height", 0.0)
	a.parry_arc = deg_to_rad(Tuning.get_optional(file, section, "parry_arc", 0.0))
	a.counter = Tuning.get_optional(file, section, "counter", "")
	a.internal = Tuning.get_optional(file, section, "internal", false)
	return a

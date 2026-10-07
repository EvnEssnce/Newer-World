class_name PlayerParams
extends RefCounted
## Player tuning in simulation units (ticks, m/s, radians). The game builds one
## from data/movement.cfg and data/combat.cfg with current(); tests build their
## own with fixed values.

# Movement
var move_speed := 0.0
var ground_acceleration := 0.0
var ground_deceleration := 0.0
var air_acceleration := 0.0
var jump_velocity := 0.0
var gravity := 0.0
## Radians per second.
var turn_speed := 0.0

# Stamina
var max_stamina := 0.0
var stamina_regen_per_tick := 0.0
var stamina_regen_delay_ticks := 0

# Dodge
var dodge_stamina_cost := 0.0
var dodge_ticks := 0
## Meters per second during the roll.
var dodge_speed := 0.0
## I-frames cover dodge ticks in [iframe_start_tick, iframe_end_tick).
var iframe_start_tick := 0
var iframe_end_tick := 0
var dodge_buffer_ticks := 0
## Dodges allowed per time in the air. 0 = ground only.
var max_air_dodges := 0

# Health
var max_health := 0.0
var respawn_ticks := 0

# Attacks (equipped weapon)
var light_attack: AttackParams
var heavy_attack: AttackParams
var attack_buffer_ticks := 0
## Radians per second the facing tracks the aim during an attack.
var attack_turn_speed := 0.0

static var _current: PlayerParams


## The game's tuning, loaded once. Tuning edits need a restart.
static func current() -> PlayerParams:
	if _current == null:
		_current = from_tuning()
	return _current


static func from_tuning() -> PlayerParams:
	var tps := float(Engine.physics_ticks_per_second)
	var p := PlayerParams.new()
	p.move_speed = Tuning.get_value("movement", "player", "move_speed")
	p.ground_acceleration = Tuning.get_value("movement", "player", "ground_acceleration")
	p.ground_deceleration = Tuning.get_value("movement", "player", "ground_deceleration")
	p.air_acceleration = Tuning.get_value("movement", "player", "air_acceleration")
	p.jump_velocity = Tuning.get_value("movement", "player", "jump_velocity")
	p.gravity = Tuning.get_value("movement", "player", "gravity")
	p.turn_speed = deg_to_rad(Tuning.get_value("movement", "player", "turn_speed"))

	p.max_stamina = Tuning.get_value("combat", "stamina", "max")
	p.stamina_regen_per_tick = Tuning.get_value("combat", "stamina", "regen_per_second") / tps
	p.stamina_regen_delay_ticks = roundi(Tuning.get_value("combat", "stamina", "regen_delay") * tps)

	var duration: float = Tuning.get_value("combat", "dodge", "duration")
	p.dodge_stamina_cost = Tuning.get_value("combat", "dodge", "stamina_cost")
	p.dodge_ticks = maxi(1, roundi(duration * tps))
	p.dodge_speed = Tuning.get_value("combat", "dodge", "distance") / (p.dodge_ticks / tps)
	p.iframe_start_tick = roundi(Tuning.get_value("combat", "dodge", "iframe_start") * tps)
	p.iframe_end_tick = roundi(Tuning.get_value("combat", "dodge", "iframe_end") * tps)
	p.dodge_buffer_ticks = roundi(Tuning.get_value("combat", "dodge", "buffer") * tps)
	p.max_air_dodges = Tuning.get_value("combat", "dodge", "air_dodges")

	p.max_health = Tuning.get_value("combat", "health", "max")
	p.respawn_ticks = roundi(Tuning.get_value("combat", "death", "respawn_time") * tps)

	# Only the sword exists so far; later this follows the equipped weapon.
	var weapon := "weapon_sword"
	p.light_attack = AttackParams.from_tuning(weapon, "light", tps)
	p.heavy_attack = AttackParams.from_tuning(weapon, "heavy", tps)
	p.attack_buffer_ticks = roundi(Tuning.get_value(weapon, "attacks", "buffer") * tps)
	p.attack_turn_speed = deg_to_rad(Tuning.get_value(weapon, "attacks", "turn_speed"))
	return p


## The params for PlayerState.ATTACK_LIGHT / ATTACK_HEAVY, or null.
func attack(attack_type: int) -> AttackParams:
	match attack_type:
		PlayerState.ATTACK_LIGHT:
			return light_attack
		PlayerState.ATTACK_HEAVY:
			return heavy_attack
	return null

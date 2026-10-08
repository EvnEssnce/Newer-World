class_name PlayerParams
extends RefCounted
## Player tuning in simulation units (ticks, m/s, radians). The game builds one
## from data/movement.cfg, data/combat.cfg and every data/weapon_*.cfg with
## current(); tests build their own with fixed values.

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

# Weapons. Attacks and abilities come from the equipped weapon
# (PlayerState.weapon()).
## Every weapon by id.
var weapons: Dictionary[String, WeaponParams] = {}
## Used for a weapon id that isn't in `weapons`: a state with no loadout yet
## (tests, or a client before its first snapshot).
var default_weapon := WeaponParams.new()
var swap_ticks := 0
var swap_buffer_ticks := 0
var ability_buffer_ticks := 0

# Block
## Full width of the protected arc in front of the blocker, radians.
var block_arc := 0.0
## Fraction of a blocked hit's damage that still gets through.
var block_damage_taken := 0.0
var block_move_multiplier := 0.0
var block_regen_multiplier := 0.0
## Radians per second the facing tracks the aim while blocking.
var block_turn_speed := 0.0
var guard_break_stagger_ticks := 0

# Statuses
## Every status effect (data/status_effects.cfg). PlayerState.statuses refers
## to them by index.
var statuses := StatusDefs.new()

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

	for file in Tuning.files_with_prefix("weapon_"):
		var weapon := WeaponParams.from_tuning(file.trim_prefix("weapon_"), tps)
		p.weapons[weapon.id] = weapon
	if not p.weapons.is_empty():
		p.default_weapon = p.weapons.values()[0]
	p.swap_ticks = maxi(1, roundi(Tuning.get_value("combat", "swap", "duration") * tps))
	p.swap_buffer_ticks = roundi(Tuning.get_value("combat", "swap", "buffer") * tps)
	p.ability_buffer_ticks = roundi(Tuning.get_value("combat", "abilities", "buffer") * tps)

	p.block_arc = deg_to_rad(Tuning.get_value("combat", "block", "arc"))
	p.block_damage_taken = Tuning.get_value("combat", "block", "damage_taken")
	p.block_move_multiplier = Tuning.get_value("combat", "block", "move_multiplier")
	p.block_regen_multiplier = Tuning.get_value("combat", "block", "regen_multiplier")
	p.block_turn_speed = deg_to_rad(Tuning.get_value("combat", "block", "turn_speed"))
	p.guard_break_stagger_ticks = roundi(
			Tuning.get_value("combat", "block", "guard_break_stagger") * tps)
	p.statuses = StatusDefs.current()
	return p


## The weapon with this id, or default_weapon.
func weapon(weapon_id: String) -> WeaponParams:
	return weapons.get(weapon_id, default_weapon)

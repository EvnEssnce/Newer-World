class_name World
extends Node3D
## The shared game world, at /root/Main/World on the server and every client.
##
## Server: spawns a player when a client says it's ready, simulates players from
## their inputs every physics tick, runs enemies (one per marker under
## EnemySpawns), resolves melee hits and sends snapshots of everyone.
## Client: sends its inputs every tick, predicts its own player, draws other
## players and enemies interpolated between snapshots, and shows hits the server
## reports.
## Builds (class, weapons, mastery) live in the BuildService child "Builds".

## Results sent with each hit event.
const HIT_DAMAGED := 0
const HIT_EVADED := 1
const HIT_DEFEATED := 2
const HIT_BLOCKED := 3
const HIT_GUARD_BROKEN := 4
## Negated by the target's parry (Riposte), which answers with a counter.
const HIT_PARRIED := 5
## Damage over time from a status (bleed).
const HIT_STATUS_DAMAGE := 6
## Healing (damage = health restored; attacker = the healer). Pyre Heart, the
## Mantle of Renewal capstone.
const HIT_HEALED := 7
## A damaging hit that crit (Headsman). Only ever sent to clients (for the
## label): on the server the strike's result is HIT_DAMAGED.
const HIT_CRITICAL := 8
## A hit a Ward shield took all of (only on the wire, like HIT_CRITICAL).
const HIT_ABSORBED := 9
const HIT_NAMES := ["hit", "evaded", "defeated", "blocked", "guard broken", "parried",
		"status damage", "healed", "critical", "absorbed"]

const PLAYER_SCENE := preload("res://game/player/player.tscn")
const ENEMY_SCENE := preload("res://game/enemy/enemy.tscn")
const HUD_SCENE := preload("res://ui/hud.tscn")
## Inputs per packet the server accepts; anything larger is dropped as malformed.
const MAX_INPUTS_PER_PACKET := 8
const SPAWN_RADIUS := 3.0
## Bot fight phase: walk to this distance from the target before swinging.
const BOT_ATTACK_DISTANCE := 1.6
## The bot fights enemies within this many meters rather than other players.
const BOT_ENEMY_RANGE := 15.0
## The bot uses a self-buff (Bloodlust) once its target is this close.
const BOT_BUFF_REACH := 2.0
## Ability phase: the first press waits (briefly) until the target is this close.
const BOT_ABILITY_REACH := 2.5
## Bot: throws a projectile ability at a target at least this far away
## (meters), and within this fraction of the projectile's reach.
const BOT_THROW_MIN := 3.0
const BOT_THROW_REACH := 0.75
const ABILITY_BUTTONS := (PlayerState.BUTTON_ABILITY_1 | PlayerState.BUTTON_ABILITY_2
		| PlayerState.BUTTON_ABILITY_3 | PlayerState.BUTTON_WING_1 | PlayerState.BUTTON_WING_2)

# Server
var _tick := 0
var _snapshot_interval := 3
var _max_input_buffer := 8
var _max_inputs_per_tick := 2
var _hits := 0
var _deaths := 0
var _respawns := 0
var _blocks := 0
var _guard_breaks := 0
## Enemy swings that connected with a player (including blocked ones).
var _enemy_hits := 0
## Player hits on enemies.
var _enemy_damaged := 0
var _enemy_kills := 0
## Taunts (forces_target statuses) applied to enemies.
var _taunts := 0
## Enemies that gained threat from a heal (one per enemy per heal).
var _heal_threat := 0
## Player attacks that connected with another player (including evaded/blocked).
var _pvp_hits := 0
## Player attacks that touched an ally and were ignored (once per attack and ally).
var _ally_hits_ignored := 0
var _ability_uses := 0
## Ability hits that connected with a player or enemy (including blocked/parried).
var _ability_hits := 0
var _parries := 0
var _swaps := 0
# Statuses (for the smoke test summary)
## Statuses applied by the server (debuffs from hits, on-hit bleeds), and how
## many of those landed on enemies.
var _statuses_applied := 0
var _statuses_on_enemies := 0
## Abilities started that buff their user (applied inside the sim).
var _self_buffs := 0
## Damage-over-time ticks (bleed) that dealt damage, and their total damage.
var _status_ticks := 0
var _status_damage := 0.0
## Debuffs between allies: refused by _give_status (should never even be tried,
## since hits on allies are ignored), and applied (must stay 0).
var _ally_statuses_refused := 0
var _ally_statuses_applied := 0
## Forced movement started (see _force_player / _force_enemy): on players (by
## anyone), on players by another player, on enemies, and launches among them.
var _forced_players := 0
var _forced_pvp := 0
var _forced_enemies := 0
var _launches := 0
## Weapon id -> abilities started with it.
var _ability_uses_by_weapon: Dictionary[String, int] = {}
# Ember, Wings and Rebirth (for the smoke test summary)
## Ember the server granted (damage dealt/taken, healing) and Ember spent on
## Wing abilities (in the sim), totals over all players.
var _ember_gained := 0.0
var _ember_spent := 0.0
var _wing_uses := 0
## Rebirths started (died with enough Ember) and finished (rose again).
var _rebirths_started := 0
var _rebirths := 0
## Heals that restored health, and the health restored.
var _heals := 0
var _healed := 0.0
## Hits on an ally that a Shield Wall holder blocked for them.
var _shield_wall_covers := 0
## Hold the Line pokes (Spear capstone).
var _line_pokes := 0
## Juggernaut (server): critical hits (Headsman), Hooked targets staggered
## (Warden), chargers staggered by Brace, Bloodied stacks gained.
var _crits := 0
## Crits from gear crit chance (Sear), a subset of _crits.
var _gear_crits := 0
## Hits on players that their armor reduced, and the damage it stopped.
var _armored_hits := 0
var _armor_stopped := 0.0
var _hook_staggers := 0
var _brace_staggers := 0
var _ramp_stacks := 0
## Juggernaut: Earthshaker aftershocks sent, Tempest Wings wall stuns, Anchor
## Defiant stacks given (one per taunted enemy).
var _aftershocks := 0
var _wall_stuns := 0
var _roar_guards := 0
## Assassin (server): backstabs (hits from behind or on an unaware enemy),
## Primed crits used, Feint reads (a blocked/evaded Feint, or one landing on
## an enemy mid-swing).
var _backstabs := 0
var _primed_crits := 0
var _feint_reads := 0
## Throwing Knives (server): Marked hits used, free Fans of Knives (Flurry),
## heals cut by poison (Venom).
var _marked_hits := 0
var _flurry_fans := 0
var _heal_cuts := 0
## Ranger (server): Ignites that detonated stacks (and stacks used), loaded
## chamber shots (Siege), heavy shots that pierce (Marksman), Parting Shot
## buffs from rolls, hits on a Hunter's Mark target by its marker.
var _ignites := 0
var _ignited_stacks := 0
var _loaded_shots := 0
var _piercing_heavies := 0
var _parting_shots := 0
var _hunted_hits := 0
## Zones (server): Mirror Image decoy bursts, Shadow Swaps.
var _decoy_bursts := 0
var _shadow_swaps := 0
## Mage (server): ally heals/shields from beams, Wards given, damage absorbed,
## Focus and Ascendant refunds.
var _ally_supports := 0
var _shields := 0
var _absorbed := 0.0
var _focus_refunds := 0
var _aura_refunds := 0

## Parties (World/Party, both sides). See are_allies.
var party: PartySystem
## World/Loot: drops, pickup, inventories (both sides).
var loot: LootSystem
## Projectiles (World/Projectiles, both sides).
var _projectiles: ProjectileSystem
## World/Zones: ground zones and summons (the AREA and SUMMON tags).
var zones: ZoneSystem

# Client
var _hud: Hud
var _local_player: Player
var _render_time := -1.0
var _interpolation_delay := 0.1
var _input_redundancy := 3
var _snapshots_received := 0
## Remote players that left: peer id -> meters seen moving (for the summary,
## since the other bot can quit a moment before this one prints it).
var _departed_seen := {}
## The click that captures the mouse mustn't also attack: after capturing, the
## attack button has to be released once before it counts.
var _attack_blocked := true
var _hits_landed := 0
var _hits_taken := 0
## Local time (msec) when the local player respawns, or -1 when alive.
var _respawn_at_msec := -1
var _bot := false
var _bot_last_phase := 0.0
var _bot_swaps_before := 0
## The bot slots its status abilities once, when its first build arrives.
var _bot_status_slots_sent := false
## Wing presses already made this cycle ("<cycle>:<ability id>").
var _bot_wing_pressed := {}
## Time (s) of the hitting ability that follows a self-buff, or -1.
var _bot_followup_at := -1.0
var _bot_first_ability_pressed := false
var _bot_next_weapon_msec := 0
var _verbose := false
var _log_timer := 0.0
var _last_screenshot_slot := -1
var _mastery_panel: MasteryPanel

@onready var _players: Node3D = $Players
@onready var _enemies: Node3D = $Enemies
var _builds: BuildService


func _ready() -> void:
	_verbose = LaunchArgs.has_flag("verbose")
	_add_party_system()
	_add_projectile_system()
	_add_zone_system()
	_builds = BuildService.new()
	_builds.name = "Builds"
	add_child(_builds)
	_add_loot_system()
	if multiplayer.is_server():
		var snapshot_rate: int = Tuning.get_value("network", "server", "snapshot_rate")
		_snapshot_interval = maxi(1, roundi(Engine.physics_ticks_per_second / float(snapshot_rate)))
		_max_input_buffer = Tuning.get_value("network", "server", "max_input_buffer")
		_max_inputs_per_tick = Tuning.get_value("network", "server", "max_inputs_per_tick")
		Net.peer_left.connect(_on_peer_left)
		_spawn_enemies()
	else:
		_interpolation_delay = Tuning.get_value("network", "client", "interpolation_delay")
		_input_redundancy = Tuning.get_value("network", "client", "input_redundancy")
		_bot = LaunchArgs.has_flag("bot")
		Player.show_hitboxes = LaunchArgs.has_flag("hitboxes")
		_hud = HUD_SCENE.instantiate()
		add_child(_hud)
		_mastery_panel = MasteryPanel.new()
		_hud.add_child(_mastery_panel)
		_mastery_panel.setup(_builds)
		# For checking the panel from --screenshot-dir frames; =wings opens the Wings tab.
		if LaunchArgs.has_flag("mastery-panel") or LaunchArgs.get_value("mastery-panel") == "wings":
			_mastery_panel.toggle()
			if LaunchArgs.get_value("mastery-panel") == "wings":
				_mastery_panel.show_wings()
		_client_ready.rpc_id(1, LaunchArgs.get_value("class", ClassDef.DEFAULT_CLASS))


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		_server_tick(delta)
	elif _local_player:
		_client_tick(delta)


func _process(delta: float) -> void:
	if multiplayer.is_server():
		return
	if _render_time >= 0.0:
		_render_time += delta
		for player: Player in _players.get_children():
			if not player.is_local:
				player.interpolate(_render_time)
		for enemy: Enemy in _enemies.get_children():
			enemy.interpolate(_render_time)
	_update_hud()
	_maybe_save_screenshot()
	if _verbose:
		_log_timer += delta
		if _log_timer >= 2.0:
			_log_timer = 0.0
			print(_describe_players())


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"toggle_hitboxes"):
		Player.show_hitboxes = not Player.show_hitboxes
	elif event.is_action_pressed(&"toggle_mastery") and _mastery_panel:
		_mastery_panel.toggle()


# --- Server ---

func _server_tick(delta: float) -> void:
	_tick += 1
	for player: Player in _players.get_children():
		if player.state.dead:
			_server_dead_player(player)
		player.server_process_inputs(_max_inputs_per_tick, delta)
		_check_wall_stun(player)
		_apply_player_status_damage(player)
		_apply_player_status_heal(player)
	var targets := _enemy_targets()
	for enemy: Enemy in _enemies.get_children():
		if enemy.dead:
			if _tick >= enemy.respawn_at_tick:
				enemy.respawn()
				if _verbose:
					print("[server] enemy %d respawned" % enemy.enemy_id)
		else:
			enemy.server_step(targets, delta)
			_check_wall_stun(enemy)
			_apply_enemy_status_damage(enemy)
	for player: Player in _players.get_children():
		_hold_the_line(player)
	_projectiles.server_step(delta)
	zones.server_step()
	if _tick % _snapshot_interval == 0:
		_broadcast_snapshot()


func _broadcast_snapshot() -> void:
	var states: Array = []
	for player: Player in _players.get_children():
		states.append(player.get_snapshot())
	var enemy_states: Array = []
	for enemy: Enemy in _enemies.get_children():
		enemy_states.append(enemy.get_snapshot())
	for peer_id in _connected_player_ids():
		_receive_snapshot.rpc_id(peer_id, _tick, states, enemy_states)


## Peers with a player in the world. A peer can be mid-disconnect for a moment
## before peer_left fires, so check the connection too.
func _connected_player_ids() -> Array[int]:
	var connected := multiplayer.get_peers()
	var ids: Array[int] = []
	for player: Player in _players.get_children():
		if player.peer_id in connected:
			ids.append(player.peer_id)
	return ids


## class_id: the character's class (--class=, see ClassDef).
@rpc("any_peer", "call_remote", "reliable")
func _client_ready(class_id: String) -> void:
	if not multiplayer.is_server():
		return
	var peer_id := multiplayer.get_remote_sender_id()
	if _players.has_node(str(peer_id)):
		return
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.peer_id = peer_id
	var angle := _players.get_child_count() * TAU / 8.0
	player.position = Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS + Vector3.UP * 0.1
	player.attack_stepped.connect(_on_attack_stepped)
	player.ability_started.connect(_on_ability_started)
	player.weapon_swapped.connect(func(_p: Player) -> void: _swaps += 1)
	player.projectile_released.connect(_projectiles.server_fire)
	player.projectile_released.connect(_knife_flurry)
	player.dodged.connect(_parting_shot)
	player.dodged.connect(_roll_zone)
	player.zone_placed.connect(func(p: Player) -> void:
		zones.server_place_for_attack(p, p.state.current_attack(p.params)))
	player.equip_finished.connect(loot.finish_equip)
	_builds.setup_player(player, class_id)
	_players.add_child(player)
	_builds.send_build(player)
	loot.add_player(peer_id)
	print("[server] peer %d joined as %s (%d players)" % [
			peer_id, player.build.class_def.id, _players.get_child_count()])


@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func _submit_inputs(inputs: Array) -> void:
	if not multiplayer.is_server() or inputs.size() > MAX_INPUTS_PER_PACKET:
		return
	var player := _players.get_node_or_null(str(multiplayer.get_remote_sender_id())) as Player
	if player:
		player.server_queue_inputs(inputs, _max_input_buffer)


func _on_peer_left(peer_id: int) -> void:
	var player := _players.get_node_or_null(str(peer_id))
	if player:
		_players.remove_child(player)
		player.queue_free()
	print("[server] peer %d left (%d players)" % [peer_id, _players.get_child_count()])


## Server: a player's hitbox (attack or ability) is live this step. It can hit
## other players and enemies, each at most once per hit window. An attack with
## max_targets skips to its recovery once it has hit that many (Shield Charge
## stops at its first contact), but everything its hitbox touches on the step it
## reaches the limit is still hit, and so is everything within its impact_radius
## then, so a charge into a group hits the whole group.
func _on_attack_stepped(attacker: Player) -> void:
	var attack := _with_range_upgrade(attacker, attacker.state.current_attack(attacker.params))
	if _target_limit_reached(attacker, attack):
		return
	var damage_scale := (attacker.damage_multiplier(attack)
			* attacker.state.statuses.damage_dealt_multiplier(attacker.params.statuses))
	if attack.window_ramp != 0.0:  # Searing Ray: later windows hit harder
		damage_scale *= 1.0 + attack.window_ramp * maxi(0, attack.window_at(attacker.state.attack_tick))
	# After damage_multiplier: it tells a heavy apart by identity.
	attack = _with_hammer_capstones(attacker, attack)
	var connected := _hit_targets(attacker, attack, damage_scale)
	if (connected > 0 and attack.impact_radius > 0.0
			and _target_limit_reached(attacker, attack)):
		connected += _hit_targets(attacker, attack.radial_copy(attack.impact_radius),
				damage_scale)
	if connected > 0:
		_on_player_attack_connected(attacker, attack, connected)


## Server: one pass of an attacker's hitbox (`attack`, which may be a radial
## impact copy) over every player and enemy not yet hit this window. Returns
## how many it connected with.
func _hit_targets(attacker: Player, attack: AttackParams, damage_scale: float) -> int:
	var connected := 0
	var read := false
	var execute := attacker.execute_bonus()
	if attack.ally_shield > 0.0 and not attacker.attack_results.has(attacker.peer_id):
		attacker.attack_results[attacker.peer_id] = true  # Ward: the caster too
		_shield_player(attacker, attack.ally_shield, attacker.peer_id)
	for target: Player in _players.get_children():
		if target == attacker:
			continue
		if _ally_support(attacker, attack, target) or attack.allies_only:
			continue
		var result := _strike_player(attacker.peer_id, attacker.global_position,
				attacker.state.yaw, attack, attacker.attack_results, target, damage_scale, execute)
		if result in [HIT_BLOCKED, HIT_GUARD_BROKEN, HIT_EVADED]:
			read = true
		if result >= 0:
			_pvp_hits += 1
		if result >= 0 and result != HIT_EVADED:
			connected += 1
		if result == HIT_DAMAGED:
			_give_hit_statuses(attacker.peer_id, attack,
					attacker.on_hit_statuses_for_window(), target)
	for enemy: Enemy in _enemies.get_children():
		if enemy.dead or attacker.attack_results.has(enemy.enemy_id) or attack.allies_only:
			continue
		if not MeleeHitbox.hits(attacker.global_position, attacker.state.yaw, attack,
				enemy.global_position, Enemy.BODY_RADIUS, Enemy.BODY_HEIGHT):
			continue
		attacker.attack_results[enemy.enemy_id] = true
		connected += 1
		if enemy.brain.mode == EnemyBrain.Mode.ATTACK:
			read = true
		strike_enemy(attacker.peer_id, attacker.global_position, attacker.state.yaw, attack,
				enemy, damage_scale, attacker.on_hit_statuses_for_window, execute)
	if read:
		_feint_read(attacker, attack)
	return connected


## Server: a player's attack (or projectile) connected with a living enemy:
## damage (× its damage-taken statuses), Ember, stagger, and if it survives the
## attack's statuses (plus on_hit's, e.g. Bloodlust's bleed; on_hit returns
## Array[Vector2i]) and force away from attacker_pos. execute: the attacker's
## execute bonus (Finishing Thrust, MasteryTree.execute_multiplier on the
## enemy's health). Returns true if it died.
func strike_enemy(attacker_id: int, attacker_pos: Vector3, attacker_yaw: float,
		attack: AttackParams, enemy: Enemy, damage_scale: float, on_hit: Callable,
		execute := Vector2.ZERO) -> bool:
	var was_staggered := enemy.brain.mode == EnemyBrain.Mode.STAGGERED
	var backstab := _is_backstab(attacker_id, attacker_pos, enemy)
	var crit := _crit_multiplier(attacker_id, attack, was_staggered, backstab)
	var base := attack.damage + _detonate(attacker_id, attack, enemy.statuses, enemy.status_defs, null)
	var damage := (base * damage_scale * crit
			* _backstab_scale(attacker_id, attack, backstab)
			* _marked_scale(attacker_id, attack, enemy.statuses, enemy.status_defs, null)
			* _hunted_scale(attacker_id, enemy.statuses, enemy.status_defs)
			* _execute_scale(execute, attack, enemy.health / enemy.params.max_health)
			* enemy.statuses.damage_taken_multiplier(enemy.status_defs))
	_enemy_damaged += 1
	_ember_from_damage(attacker_id, null, damage)
	var stagger := _with_hook_stagger(attacker_id, enemy,
			_with_surge_stagger(attacker_id, attack.stagger_ticks))
	_lifesteal(attacker_id, attack, damage)
	if _damage_enemy(enemy, damage, stagger, attacker_id,
			HIT_CRITICAL if crit > 1.0 else HIT_DAMAGED):
		return true
	_give_hit_statuses(attacker_id, attack, on_hit.call(), enemy)
	_force_enemy(attacker_pos, attacker_yaw, attack, enemy, was_staggered, attacker_id)
	return false


func _on_ability_started(player: Player) -> void:
	var started := player.state.current_ability(player.params)
	if started and started.swap_places:
		_shadow_swap(player, started)
	if started:
		_mage_ability_started(player, started)
	if player.state.is_using_wing():
		_on_wing_started(player)
		return
	_ability_uses += 1
	if not player.state.current_ability(player.params).self_status.is_empty():
		_self_buffs += 1
	var weapon_id := player.state.weapon_id()
	_ability_uses_by_weapon[weapon_id] = _ability_uses_by_weapon.get(weapon_id, 0) + 1
	if _verbose:
		print("[server] peer %d uses %s" % [player.peer_id,
				player.state.current_ability(player.params).id])


## Server: a player's attack or ability connected with `count` targets this step.
func _on_player_attack_connected(attacker: Player, attack: AttackParams, count: int) -> void:
	if attacker.state.is_using_ability():
		_ability_hits += count
	elif attacker.state.attack_type == PlayerState.ATTACK_HEAVY:
		attacker.last_heavy_hit_tick = _tick
	_ramp_on_hit(attacker)
	if _target_limit_reached(attacker, attack):
		attacker.state.end_active_window(attacker.params)


## True once an attack with max_targets has connected with that many targets.
func _target_limit_reached(attacker: Player, attack: AttackParams) -> bool:
	if attack.max_targets <= 0:
		return false
	var connected := 0
	for hit: bool in attacker.attack_results.values():
		if hit:
			connected += 1
	return connected >= attack.max_targets


## Server: an enemy's swing is live this tick.
func _on_enemy_attack_stepped(enemy: Enemy) -> void:
	if enemy.swing_misses:
		return
	var damage_scale := enemy.statuses.damage_dealt_multiplier(enemy.status_defs)
	for target: Player in _players.get_children():
		var result := _strike_player(enemy.enemy_id, enemy.global_position, enemy.brain.yaw,
				enemy.params.attack, enemy.attack_results, target, damage_scale)
		if result >= 0 and result != HIT_EVADED:
			_enemy_hits += 1
		if result == HIT_DAMAGED:
			_give_hit_statuses(enemy.enemy_id, enemy.params.attack,
					enemy.statuses.take_on_hit_statuses(enemy.status_defs), target)


## Server: resolves one attack against one player, at most once per hit window
## (`results`, keyed by target id). A player in i-frames evades but can still be
## hit later in the same active window if their i-frames run out first. A
## parrying player (Riposte) facing the attacker negates it and counters. A
## blocking player facing the attacker takes stamina damage instead. Allies
## (are_allies) are ignored entirely: no damage, stagger, block cost or label.
## damage_scale: the attacker's damage modifiers; execute: its execute bonus
## (Finishing Thrust, scaled by the target's health). Returns the HIT_* result,
## or -1 if the attack didn't connect (or already did).
func _strike_player(attacker_id: int, attacker_pos: Vector3, attacker_yaw: float,
		attack: AttackParams, results: Dictionary[int, bool], target: Player,
		damage_scale: float = 1.0, execute := Vector2.ZERO) -> int:
	if target.state.dead or results.get(target.peer_id, false):
		return -1
	if not MeleeHitbox.hits(attacker_pos, attacker_yaw, attack, target.global_position,
			Player.BODY_RADIUS, Player.BODY_HEIGHT):
		return -1
	var result := resolve_strike(attacker_id, attacker_pos, attacker_yaw, attack, results, target,
			damage_scale, execute)
	if result in [HIT_DAMAGED, HIT_BLOCKED, HIT_GUARD_BROKEN]:
		_brace_counter(attacker_id, target)
	return result


## Server: the rest of _strike_player once something touched the target (a
## hitbox, or a projectile: then attacker_pos is a point back along its path,
## so a guard or a parry must face where it came from, and knockback pushes
## along it). Same rules and results. A target that isn't guarding against it
## but stands behind a blocking ally's Shield Wall is covered (_covered_hit).
func resolve_strike(attacker_id: int, attacker_pos: Vector3, attacker_yaw: float,
		attack: AttackParams, results: Dictionary[int, bool], target: Player,
		damage_scale: float = 1.0, execute := Vector2.ZERO) -> int:
	if target.state.dead or results.get(target.peer_id, false):
		return -1
	if are_allies(attacker_id, target.peer_id):
		results[target.peer_id] = true  # counted once per attack
		_ally_hits_ignored += 1
		return -1
	if target.state.is_invulnerable(target.params):
		if results.has(target.peer_id):
			return -1
		results[target.peer_id] = false
		_send_hit(attacker_id, target.peer_id, 0.0, HIT_EVADED)
		return HIT_EVADED
	results[target.peer_id] = true
	if _try_parry(attacker_id, attacker_pos, target):
		return HIT_PARRIED
	var guarded := _guards_against(target, attacker_pos)
	if not guarded:
		var holder := _shield_wall_holder(attacker_id, attacker_pos, target)
		if holder:
			return _covered_hit(attacker_id, attacker_pos, attacker_yaw, attack, damage_scale,
					execute, holder, target)
	var was_staggered := target.state.is_staggered()
	var backstab := _is_backstab(attacker_id, attacker_pos, target)
	var crit := _crit_multiplier(attacker_id, attack, was_staggered, backstab)
	var base_damage := ((attack.damage
			+ _detonate(attacker_id, attack, target.state.statuses, target.params.statuses, target))
			* damage_scale * crit
			* _backstab_scale(attacker_id, attack, backstab)
			* _marked_scale(attacker_id, attack, target.state.statuses, target.params.statuses, target)
			* _hunted_scale(attacker_id, target.state.statuses, target.params.statuses)
			* _execute_scale(execute, attack, target.health / target.max_health()))
	var damage := _after_armor(base_damage
			* target.state.statuses.damage_taken_multiplier(target.params.statuses)
			* target.damage_taken_multiplier() * _crowd_multiplier(target), attacker_id, target)
	var result := HIT_DAMAGED
	if guarded:
		var broke := target.state.take_blocked_hit(attack, target.params,
				target.block_stamina_multiplier())
		damage *= target.params.block_damage_taken
		result = HIT_GUARD_BROKEN if broke else HIT_BLOCKED
		if broke:
			_guard_breaks += 1
		else:
			_blocks += 1
	var absorbed := _absorb(target, damage)
	damage -= absorbed
	target.health = maxf(0.0, target.health - damage)
	# Before a fatal hit kills: its Ember counts toward a Rebirth.
	_ember_from_damage(attacker_id, target, damage)
	if target.health <= 0.0:
		result = HIT_DEFEATED
		_kill_player(target)
	elif result == HIT_DAMAGED:
		target.state.apply_stagger(_with_hook_stagger(attacker_id, target,
				_with_surge_stagger(attacker_id, attack.stagger_ticks)), target.params)
	if result == HIT_DAMAGED or result == HIT_GUARD_BROKEN:
		_force_player(attacker_id, attacker_pos, attacker_yaw, attack, target, was_staggered)
	_hits += 1
	var shown := result
	if result == HIT_DAMAGED:
		shown = HIT_ABSORBED if damage <= 0.0 and absorbed > 0.0 else (
				HIT_CRITICAL if crit > 1.0 else HIT_DAMAGED)
	_send_hit(attacker_id, target.peer_id, damage, shown)
	if result != HIT_DEFEATED:
		_mantle_heal(target, base_damage, result != HIT_DAMAGED)
	if result == HIT_DAMAGED or result == HIT_DEFEATED:
		_lifesteal(attacker_id, attack, damage + absorbed)
	return result


## True if a player's own guard is up and faces attacker_pos (within its block arc).
func _guards_against(player: Player, attacker_pos: Vector3) -> bool:
	return player.state.blocking and MeleeHitbox.is_in_front(player.global_position,
			player.state.yaw, attacker_pos, player.params.block_arc)


## Shield Wall: a living ally of target (not target itself, and not an ally of
## the attacker) that is blocking with a cover status (StatusEffects.cover_box),
## facing attacker_pos within its block arc, with target inside the box
## straight behind it (MeleeHitbox.is_behind). Null if none.
func _shield_wall_holder(attacker_id: int, attacker_pos: Vector3, target: Player) -> Player:
	for holder: Player in _players.get_children():
		if holder == target or holder.state.dead or not holder.state.blocking:
			continue
		if (not are_allies(holder.peer_id, target.peer_id)
				or are_allies(attacker_id, holder.peer_id)):
			continue
		var box := holder.state.statuses.cover_box(holder.params.statuses)
		if box.x <= 0.0:
			continue
		if (_guards_against(holder, attacker_pos)
				and MeleeHitbox.is_behind(holder.global_position, holder.state.yaw,
					target.global_position, box.x, box.y)):
			return holder
	return null


## Server: Shield Wall. holder blocks a hit meant for target (an ally behind
## it) through the normal blocked-hit path: the holder's stamina (its block
## modifiers), block_damage_taken of the damage, a guard break (stagger, and
## the attack's force) if it runs out or the attack breaks blocks. The target
## takes nothing. Both are reported (the target as a 0-damage HIT_BLOCKED, so
## its client shows "Blocked"). Returns HIT_BLOCKED for the target, so a
## projectile that guards stop stops here.
func _covered_hit(attacker_id: int, attacker_pos: Vector3, attacker_yaw: float,
		attack: AttackParams, damage_scale: float, execute: Vector2, holder: Player,
		target: Player) -> int:
	_shield_wall_covers += 1
	var was_staggered := holder.state.is_staggered()
	var damage := _after_armor(attack.damage * damage_scale
			* _execute_scale(execute, attack, holder.health / holder.max_health())
			* holder.state.statuses.damage_taken_multiplier(holder.params.statuses)
			* holder.damage_taken_multiplier() * _crowd_multiplier(holder)
			* holder.params.block_damage_taken, attacker_id, holder)
	var broke := holder.state.take_blocked_hit(attack, holder.params,
			holder.block_stamina_multiplier())
	var result := HIT_GUARD_BROKEN if broke else HIT_BLOCKED
	if broke:
		_guard_breaks += 1
	else:
		_blocks += 1
	holder.health = maxf(0.0, holder.health - damage)
	_ember_from_damage(attacker_id, holder, damage)
	if holder.health <= 0.0:
		result = HIT_DEFEATED
		_kill_player(holder)
	elif broke:
		_force_player(attacker_id, attacker_pos, attacker_yaw, attack, holder, was_staggered)
	_hits += 1
	if _verbose:
		print("[server] peer %d's Shield Wall covers peer %d" % [holder.peer_id, target.peer_id])
	_send_hit(attacker_id, holder.peer_id, damage, result)
	_send_hit(attacker_id, target.peer_id, 0.0, HIT_BLOCKED)
	return HIT_BLOCKED


# --- Hold the Line (Spear capstone) ---

## Server, every tick after players and enemies have moved: a player with a
## "hold_the_line" node in the tree of the weapon that's out, while blocking,
## strikes each hostile player or living enemy that enters (outside last tick,
## inside now) the reach box of the node's internal ability (`applies_to`,
## e.g. line_poke) once, then not that target again for the ability's cooldown.
## Server only: it never touches the holder's PlayerState, so nothing to
## predict. The strike goes through resolve_strike / strike_enemy (blocks,
## i-frames, parries, statuses, Ember, execute bonus as usual).
func _hold_the_line(player: Player) -> void:
	var poke: AbilityParams = null
	if player.build and not player.state.dead:
		var node := player.build.weapon_effect(player.state.weapon_id(), "hold_the_line")
		if node:
			var weapon := player.state.weapon(player.params)
			poke = weapon.ability(weapon.ability_index(node.applies_to))
	if poke == null:
		player.line_inside.clear()
		return
	var pos := player.global_position
	var yaw := player.state.yaw
	var inside: Dictionary[int, bool] = {}
	for target: Player in _players.get_children():
		if (target != player and not target.state.dead
				and not are_allies(player.peer_id, target.peer_id)
				and MeleeHitbox.hits(pos, yaw, poke, target.global_position,
					Player.BODY_RADIUS, Player.BODY_HEIGHT)):
			inside[target.peer_id] = true
	for enemy: Enemy in _enemies.get_children():
		if not enemy.dead and MeleeHitbox.hits(pos, yaw, poke, enemy.global_position,
				Enemy.BODY_RADIUS, Enemy.BODY_HEIGHT):
			inside[enemy.enemy_id] = true
	if player.state.blocking:
		for id: int in inside:
			if player.line_inside.has(id) or _tick < player.line_ready_at.get(id, 0):
				continue
			player.line_ready_at[id] = _tick + poke.cooldown_ticks
			_line_poke(player, poke, id)
	player.line_inside = inside


## Server: one Hold the Line poke on a player (id > 0) or an enemy (id < 0).
func _line_poke(player: Player, poke: AbilityParams, target_id: int) -> void:
	_line_pokes += 1
	if _verbose:
		print("[server] peer %d holds the line: pokes %d" % [player.peer_id, target_id])
	var scale := (player.damage_multiplier(poke)
			* player.state.statuses.damage_dealt_multiplier(player.params.statuses))
	var execute := player.execute_bonus()
	if target_id > 0:
		var target := _player_by_id(target_id)
		var results: Dictionary[int, bool] = {}
		if target and resolve_strike(player.peer_id, player.global_position, player.state.yaw,
				poke, results, target, scale, execute) == HIT_DAMAGED:
			_give_hit_statuses(player.peer_id, poke, _no_on_hit_statuses(), target)
		return
	for enemy: Enemy in _enemies.get_children():
		if enemy.enemy_id == target_id and not enemy.dead:
			strike_enemy(player.peer_id, player.global_position, player.state.yaw, poke, enemy,
					scale, _no_on_hit_statuses, execute)


## No on-hit statuses (Hold the Line's pokes don't use up Bloodlust charges).
func _no_on_hit_statuses() -> Array[Vector2i]:
	return []


# --- Juggernaut: Halberd and Greataxe mechanics (server only) ---

## The execute bonuses on one hit: the attacker's tree bonus (Finishing
## Thrust, captured as `execute`) times the attack's own (Executioner's Swing,
## AttackParams.execute), each MasteryTree.execute_multiplier on the target's
## health fraction.
func _execute_scale(execute: Vector2, attack: AttackParams, health_fraction: float) -> float:
	return (MasteryTree.execute_multiplier(execute, health_fraction)
			* MasteryTree.execute_multiplier(attack.execute, health_fraction))


## Crits: the [crit] multiplier if the attacking player's tree covers this
## attack and its condition holds (the Halberd's Headsman capstone,
## "crit_staggered": the target was staggered before the hit; the Dual
## Talons' Predator capstone, "crit_backstab": a backstab), or the attacker is
## Primed (Feint: its next hit crits, using the status up), or else on a roll
## of its gear's crit chance (Sear); else 1. Enemies never crit.
func _crit_multiplier(attacker_id: int, attack: AttackParams, target_staggered: bool,
		backstab := false) -> float:
	var attacker := _player_by_id(attacker_id)
	if attacker == null:
		return 1.0
	var crit := attacker.crit_multiplier(attack, target_staggered, backstab)
	if crit <= 1.0:
		var primed := attacker.state.statuses.next_hit_crit_status(attacker.params.statuses)
		if primed >= 0:
			attacker.state.remove_status(primed)
			crit = attacker.params.crit_damage_multiplier
			_primed_crits += 1
	if crit <= 1.0 and randf() < attacker.gear.bonus("crit_chance"):
		crit = attacker.params.crit_damage_multiplier
		_gear_crits += 1
	if crit > 1.0:
		_crits += 1
	return crit


## Armor: the fraction of a hit's damage that gets through the target's armor
## (GearScore.mitigation), against the attacker's weapon gear score (a
## player's weapon or Wing Enhancement item, an enemy's [stats] gear_score).
## Hits only; damage over time ignores armor.
func _armor_multiplier(attacker_id: int, target: Player) -> float:
	if target.gear.armor <= 0.0:
		return 1.0
	var curve := GearScore.current()
	var attacker_gs := curve.base
	var attacker := _player_by_id(attacker_id)
	if attacker:
		attacker_gs = attacker.attack_gear_score(curve.base)
	elif attacker_id < 0:
		var enemy := _enemies.get_node_or_null(str(attacker_id)) as Enemy
		if enemy:
			attacker_gs = enemy.params.gear_score
	return 1.0 - curve.mitigation(target.gear.armor, attacker_gs)


## The damage a hit does after the target's armor, counted for the summary.
func _after_armor(damage: float, attacker_id: int, target: Player) -> float:
	var through := damage * _armor_multiplier(attacker_id, target)
	if through < damage:
		_armored_hits += 1
		_armor_stopped += damage - through
	return through


## Maelstrom ("ability_range"): the ability in use with its hitbox range times
## the weapon tree's multiplier for it (Vortex reaches twice as far). Only the
## server tests hits, so nothing to predict; F3 still draws the base range.
func _with_range_upgrade(player: Player, attack: AttackParams) -> AttackParams:
	var ability := attack as AbilityParams
	if ability == null or player.build == null or player.state.is_using_wing():
		return attack
	var factor := player.build.range_multiplier(player.state.weapon_id(), ability.id)
	return attack if is_equal_approx(factor, 1.0) else attack.range_copy(attack.hitbox_range * factor)


## The Warden capstone ("hook_stagger"): a hit from a player whose weapon tree
## (of the weapon that's out) has it, on a target carrying the node's mark
## status (applies_to: Hooked, from Hooking Pull) applied by that same player,
## staggers for at least the node's amount (seconds) and uses the mark up.
## Returns the stagger ticks to apply. target: a Player or an Enemy.
func _with_hook_stagger(attacker_id: int, target: Node3D, stagger_ticks: int) -> int:
	var attacker := _player_by_id(attacker_id)
	if attacker == null or attacker.build == null or attacker.state.is_using_wing():
		return stagger_ticks
	var node := attacker.build.weapon_effect(attacker.state.weapon_id(), "hook_stagger")
	if node == null:
		return stagger_ticks
	var index := attacker.params.statuses.index_of(node.applies_to)
	var player := target as Player
	var statuses: StatusEffects = player.state.statuses if player else (target as Enemy).statuses
	if index < 0 or statuses.source_of(index) != attacker_id:
		return stagger_ticks
	if player:
		player.state.remove_status(index)
	else:
		statuses.remove(index)
	_hook_staggers += 1
	if _verbose:
		print("[server] peer %d's hook staggers %s" % [attacker_id, target.name])
	return maxi(stagger_ticks, roundi(node.amount * Engine.physics_ticks_per_second))


## Brace: a melee hit (a hitbox, not a projectile) landed on a player. If the
## target's statuses stagger chargers (Braced: charge_stagger) and this hit
## counts as a charge (the attacking player was dashing, or it landed within
## the status's charge_window), the attacker is staggered: a player through
## apply_stagger (immunities apply; a server event), an enemy's brain.
func _brace_counter(attacker_id: int, target: Player) -> void:
	var attacker := _player_by_id(attacker_id)
	var dashing := attacker != null and attacker.state.is_dashing(attacker.params)
	var ticks := target.state.statuses.charge_stagger_ticks(target.params.statuses, dashing)
	if ticks <= 0:
		return
	if attacker:
		if attacker.state.dead or attacker.state.statuses.stagger_immune(attacker.params.statuses):
			return
		attacker.state.apply_stagger(ticks, attacker.params)
	else:
		var enemy := _enemies.get_node_or_null(str(attacker_id)) as Enemy
		if enemy == null or enemy.dead or enemy.statuses.stagger_immune(enemy.status_defs):
			return
		enemy.brain.stagger(ticks)
	_brace_staggers += 1
	if _verbose:
		print("[server] peer %d's Brace staggers %d" % [target.peer_id, attacker_id])


## Iron Hide: the multiplier on damage a player takes from its crowd statuses
## (StatusEffects.crowd_damage_taken_multiplier), counting living enemies and
## hostile players within the largest crowd_radius. 1 without one.
func _crowd_multiplier(player: Player) -> float:
	var defs := player.params.statuses
	var radius := player.state.statuses.crowd_radius(defs)
	if radius <= 0.0:
		return 1.0
	var pos := player.global_position
	var nearby := 0
	for enemy: Enemy in _enemies.get_children():
		if not enemy.dead and enemy.global_position.distance_to(pos) <= radius:
			nearby += 1
	for other: Player in _players.get_children():
		if (other != player and not other.state.dead and not are_allies(player.peer_id, other.peer_id)
				and other.global_position.distance_to(pos) <= radius):
			nearby += 1
	return player.state.statuses.crowd_damage_taken_multiplier(defs, nearby)


## The Greataxe's Bloodied capstone ("ramp_on_hit"): each step a player's
## melee attack or ability connects (with the weapon whose tree has it out)
## gives it a stack of the node's status (applies_to: Bloodied, more damage
## per stack, refreshed by every hit, so it falls off soon after the hits stop).
func _ramp_on_hit(attacker: Player) -> void:
	if attacker.build == null or attacker.state.is_using_wing():
		return
	var node := attacker.build.weapon_effect(attacker.state.weapon_id(), "ramp_on_hit")
	if node and _give_status(attacker.peer_id, attacker,
			attacker.params.statuses.index_of(node.applies_to), 1, -1):
		_ramp_stacks += 1


# --- Assassin: Dual Talons mechanics (server only) ---

## A backstab: a player's hit (attacker_id > 0) from within [backstab]
## rear_arc behind the target's facing (attacker_pos: for a projectile, a
## point back along its path), or on an enemy whose threat target isn't the
## attacker (idle, or fighting someone else) when unaware_enemies is on.
## target: a Player or an Enemy.
func _is_backstab(attacker_id: int, attacker_pos: Vector3, target: Node3D) -> bool:
	var attacker := _player_by_id(attacker_id) if attacker_id > 0 else null
	if attacker == null:
		return false
	var p := attacker.params
	var player := target as Player
	var yaw: float = player.state.yaw if player else (target as Enemy).brain.yaw
	var behind := MeleeHitbox.is_in_front(target.global_position, yaw + PI, attacker_pos,
			p.backstab_rear_arc)
	if not behind and player == null and p.backstab_unaware_enemies:
		behind = (target as Enemy).brain.target_id != attacker_id
	if behind:
		_backstabs += 1
	return behind


## The attacker's backstab damage multiplier for this attack (Backstab
## passives, Player.backstab_multiplier) when `backstab`, else 1.
func _backstab_scale(attacker_id: int, attack: AttackParams, backstab: bool) -> float:
	if not backstab:
		return 1.0
	var attacker := _player_by_id(attacker_id)
	return attacker.backstab_multiplier(attack) if attacker else 1.0


## Feint ("read_status"): a player's attack that a player blocked or evaded,
## or that landed on an enemy mid-swing, gives the attacker its read_status
## (Primed: the next hit crits). Once per step.
func _feint_read(attacker: Player, attack: AttackParams) -> void:
	if attack.read_status.is_empty():
		return
	if _give_status(attacker.peer_id, attacker,
			attacker.params.statuses.index_of(attack.read_status), 1, -1):
		_feint_reads += 1
		if _verbose:
			print("[server] peer %d reads its target: %s" % [attacker.peer_id, attack.read_status])


# --- Assassin: Throwing Knives mechanics (server only) ---

## Marked Blade: a melee hit (not a projectile: its attack has no
## `projectile`) from the player who marked the target (a mark status,
## StatusEffects.mark_from) deals 1 + marked_bonus as much and uses the mark
## up. target_player: the target if it's a player (removing a status is then
## a server event), null for an enemy. Else 1.
func _marked_scale(attacker_id: int, attack: AttackParams, statuses: StatusEffects,
		defs: StatusDefs, target_player: Player) -> float:
	if attacker_id <= 0 or not attack.projectile.is_empty():
		return 1.0
	var index := statuses.mark_from(defs, attacker_id)
	if index < 0:
		return 1.0
	var bonus := defs.get_def(index).marked_bonus
	if target_player:
		target_player.state.remove_status(index)
	else:
		statuses.remove(index)
	_marked_hits += 1
	return 1.0 + bonus


## Venom capstone ("heal_cut"): healing on a target carrying a status
## (applies_to: Poison) applied by a player with the node in the tree of one of
## its equipped weapons is cut by its amount (the biggest cut counts). 1 = no cut.
func _heal_cut(target: Player) -> float:
	var cut := 0.0
	for source: Player in _players.get_children():
		if source.build == null or source == target:
			continue
		for weapon_id in source.build.weapons:
			var node := source.build.weapon_effect(weapon_id, "heal_cut")
			if node == null:
				continue
			var index := source.params.statuses.index_of(node.applies_to)
			if index >= 0 and target.state.statuses.source_of(index) == source.peer_id:
				cut = maxf(cut, node.amount)
	if cut > 0.0:
		_heal_cuts += 1
	return maxf(0.0, 1.0 - cut)


## Flurry capstone ("knife_flurry"), on every projectile release: a light or
## heavy throw (not an ability) with the weapon whose tree has it is counted
## (Player.throw_counter, once per attack); every amount-th also sends out the
## ability applies_to (Fan of Knives) from where the player stands, for free.
func _knife_flurry(player: Player) -> void:
	if player.build == null or player.state.is_using_ability():
		return
	var node := player.build.weapon_effect(player.state.weapon_id(), "knife_flurry")
	if node == null or not player.throw_counter.register(player.state.attack_serial, roundi(node.amount)):
		return
	var weapon := player.state.weapon(player.params)
	var fan := weapon.ability(weapon.ability_index(node.applies_to))
	if fan:
		_flurry_fans += 1
		_projectiles.server_fire_attack(player, fan)


# --- Ranger: Longbow, Crossbow and Firebolts mechanics (server only) ---

## Hunter's Mark: the target's damage_taken_from_source statuses applied by
## this attacker (StatusEffects.damage_taken_from). 1 without one.
func _hunted_scale(attacker_id: int, statuses: StatusEffects, defs: StatusDefs) -> float:
	if attacker_id <= 0:
		return 1.0
	var scale := statuses.damage_taken_from(defs, attacker_id)
	if scale != 1.0:
		_hunted_hits += 1
	return scale


## Ignite ("detonates_status"): uses up every stack of that status on the
## target and returns detonate_damage per stack (added to the hit's base
## damage). The Flashfire capstone ("ignite_ember", the weapon tree that's
## out) gives the attacker amount Ember per stack. target_player: the target if
## it's a player (removing is a server event), null for an enemy.
func _detonate(attacker_id: int, attack: AttackParams, statuses: StatusEffects,
		defs: StatusDefs, target_player: Player) -> float:
	if attack.detonates_status.is_empty():
		return 0.0
	var index := defs.index_of(attack.detonates_status)
	var stacks := statuses.stacks_of(index) if index >= 0 else 0
	if stacks <= 0:
		return 0.0
	if target_player:
		target_player.state.remove_status(index)
	else:
		statuses.remove(index)
	_ignites += 1
	_ignited_stacks += stacks
	var attacker := _player_by_id(attacker_id)
	if attacker and attacker.build:
		var refund := attacker.build.weapon_effect(attacker.state.weapon_id(), "ignite_ember")
		if refund:
			_give_ember(attacker, refund.amount * stacks, true)
	return attack.detonate_damage * stacks


## The most stacks source_id's application of `def` may reach: the Kindling
## capstone ("status_cap" with applies_to = the status, in the tree of one of
## the source's equipped weapons) multiplies max_stacks by its amount. 0 = the
## status's own.
func _stack_cap(source_id: int, def: StatusDef) -> int:
	var source := _player_by_id(source_id) if source_id > 0 else null
	if source == null or source.build == null:
		return 0
	for weapon_id in source.build.weapons:
		var node := source.build.weapon_effect(weapon_id, "status_cap")
		if node and node.applies_to == def.id:
			return roundi(def.max_stacks * node.amount)
	return 0


## Server, as a player's projectiles are thrown (ProjectileSystem.server_fire_attack):
## [damage factor, pierce at least] from the weapon tree that's out. Marksman
## ("heavy_pierce"): heavy shots pierce amount targets. Siege
## ("loaded_chamber"): a light or heavy shot released at least `threshold`
## seconds after this player's previous one deals 1 + amount as much (a
## reloaded crossbow). Abilities and server-side throws get [1, 0].
func release_mods(player: Player, attack: AttackParams) -> Vector2:
	var kind := player.attack_kind(attack)
	if player.build == null or kind == "ability" or player.state.is_using_ability():
		return Vector2(1.0, 0.0)
	var weapon_id := player.state.weapon_id()
	var result := Vector2(1.0, 0.0)
	var pierce := player.build.weapon_effect(weapon_id, "heavy_pierce")
	if pierce and kind == "heavy":
		result.y = pierce.amount
		_piercing_heavies += 1
	var chamber := player.build.weapon_effect(weapon_id, "loaded_chamber")
	var now := server_tick()
	if chamber and (player.last_release_tick < 0 or now - player.last_release_tick
			>= chamber.threshold * Engine.physics_ticks_per_second):
		result.x = 1.0 + chamber.amount
		_loaded_shots += 1
	player.last_release_tick = now
	return result


## The Ranger Wings' Parting Shot capstone ("roll_empower"): every roll gives the
## player the node's status (Parting Shot: more damage on the next hit).
func _parting_shot(player: Player) -> void:
	if player.build == null:
		return
	var node := player.build.wing_effect("roll_empower")
	if node and _give_status(player.peer_id, player,
			player.params.statuses.index_of(node.status), 1, -1):
		_parting_shots += 1


# --- Mage: heals, shields, channels (server only) ---

## Mending Beam / Ward ("ally_heal", "ally_shield"): an ally of the attacker (not
## itself) that the hitbox touches is healed or shielded once per hit window
## instead of struck. Returns true if `target` is such an ally (handled or not).
func _ally_support(attacker: Player, attack: AttackParams, target: Player) -> bool:
	if attack.ally_heal <= 0.0 and attack.ally_shield <= 0.0:
		return false
	if not are_allies(attacker.peer_id, target.peer_id):
		return false
	if (target.state.dead or attacker.attack_results.has(target.peer_id)
			or not MeleeHitbox.hits(attacker.global_position, attacker.state.yaw, attack,
				target.global_position, Player.BODY_RADIUS, Player.BODY_HEIGHT)):
		return true
	attacker.attack_results[target.peer_id] = true
	if attack.ally_heal > 0.0:
		_heal_player(target, attack.ally_heal * attacker.damage_multiplier(attack), attacker.peer_id)
	if attack.ally_shield > 0.0:
		_shield_player(target, attack.ally_shield, attacker.peer_id)
	_ally_supports += 1
	return true


## Ward: gives `target` the absorb status (absorbs) and an absorb pool of at
## least `amount` (Player.absorb), from `source_id`.
func _shield_player(target: Player, amount: float, source_id: int) -> void:
	var index := target.params.statuses.index_of("ward")
	if amount <= 0.0 or target.state.dead or index < 0:
		return
	if _give_status(source_id, target, index, 1, -1):
		target.absorb = maxf(target.absorb, amount)
		_shields += 1


## How much of `damage` the target's Ward absorbs (taking it from the pool and
## removing the status once it's empty). A pool without the status is gone.
func _absorb(target: Player, damage: float) -> float:
	var index := target.state.statuses.absorb_status(target.params.statuses)
	if index < 0:
		target.absorb = 0.0
		return 0.0
	var taken := minf(damage, target.absorb)
	target.absorb -= taken
	_absorbed += taken
	if target.absorb <= 0.0:
		target.state.remove_status(index)
	return taken


## Siphon ("lifesteal"): heals the attacking player a fraction of the damage it
## dealt; with the Siphon capstone ("siphon_share", the weapon tree that's out)
## its allies within the node's threshold (m) get the same.
func _lifesteal(attacker_id: int, attack: AttackParams, damage: float) -> void:
	if attack.lifesteal <= 0.0 or damage <= 0.0:
		return
	var attacker := _player_by_id(attacker_id)
	if attacker == null:
		return
	var amount := damage * attack.lifesteal
	_heal_player(attacker, amount, attacker_id)
	var share := attacker.build.weapon_effect(attacker.state.weapon_id(), "siphon_share") if attacker.build else null
	if share == null:
		return
	for ally: Player in _players.get_children():
		if (ally != attacker and are_allies(attacker_id, ally.peer_id)
				and ally.global_position.distance_to(attacker.global_position) <= share.threshold):
			_heal_player(ally, amount, attacker_id)


## Lifeweaver capstone ("overheal_shield", in the healer's weapon tree that's
## out): healing past max health becomes a Ward of that much x amount.
func _overheal_shield(healer: Player, target: Player, excess: float) -> void:
	if healer == null or healer.build == null or excess <= 0.0:
		return
	var node := healer.build.weapon_effect(healer.state.weapon_id(), "overheal_shield")
	if node:
		_shield_player(target, excess * node.amount, healer.peer_id)


## Server, as any ability starts: the Focus capstone ("focus_refund": an ability
## started within threshold s of landing a heavy refunds its Ember cost) and the
## Ascendant capstone ("aura_refund": the Wing ability applies_to cuts your
## weapon ability cooldowns by amount).
func _mage_ability_started(player: Player, started: AbilityParams) -> void:
	if player.build == null:
		return
	if started.ember_cost > 0.0 and not player.state.is_using_wing():
		var focus := player.build.weapon_effect(player.state.weapon_id(), "focus_refund")
		if (focus and player.last_heavy_hit_tick >= 0
				and _tick - player.last_heavy_hit_tick <= focus.threshold * Engine.physics_ticks_per_second):
			player.state.gain_ember(player.params, started.ember_cost, false)
			_focus_refunds += 1
	var aura := player.build.wing_effect("aura_refund")
	if aura and player.state.is_using_wing() and started.id == aura.applies_to:
		player.state.reduce_ability_cooldowns(aura.amount)
		_aura_refunds += 1


# --- Zones and summons (server; ZoneSystem places and ticks them) ---

## Where each living player stands, as enemies see it (peer id -> position):
## a player with a live decoy (Ember Double) is seen at the decoy instead.
func _enemy_targets() -> Dictionary:
	var targets := {}
	for player: Player in _players.get_children():
		if player.state.dead:
			continue
		var decoy := zones.decoy_for(player.peer_id)
		targets[player.peer_id] = decoy.position if decoy else player.global_position
	return targets


## A zone's pulse (or a trap firing) reaches `target` (a Player or an Enemy):
## its damage (like damage over time: no block, crit or armor; × damage taken),
## healing (_heal_player), and status (_give_status, which refuses debuffs on
## allies), all from the zone's owner.
func zone_effect(zone: Zone, target: Node3D) -> void:
	var p := zone.params
	var player := target as Player
	var enemy := target as Enemy
	if p.damage > 0.0:
		if player:
			var damage := (p.damage * player.state.statuses.damage_taken_multiplier(player.params.statuses)
					* player.damage_taken_multiplier() * _crowd_multiplier(player))
			player.health = maxf(0.0, player.health - damage)
			_ember_from_damage(zone.owner_id, player, damage)
			var result := HIT_STATUS_DAMAGE
			if player.health <= 0.0:
				result = HIT_DEFEATED
				_kill_player(player)
			_send_hit(zone.owner_id, player.peer_id, damage, result)
		elif enemy:
			var damage := p.damage * enemy.statuses.damage_taken_multiplier(enemy.status_defs)
			_ember_from_damage(zone.owner_id, null, damage)
			if _damage_enemy(enemy, damage, 0, zone.owner_id, HIT_STATUS_DAMAGE):
				return
	if p.heal > 0.0 and player:
		_heal_player(player, p.heal, zone.owner_id)
	if not p.applies_status.is_empty() and not (player and player.state.dead):
		_give_status(zone.owner_id, target, StatusDefs.current().index_of(p.applies_status),
				p.status_stacks, p.status_duration_ticks)
	# The Mage Wings' Binder capstone ("bind_silence"): its zone (applies_to)
	# also gives the node's status (silence) to hostiles.
	var owner := _player_by_id(zone.owner_id)
	var bind := owner.build.wing_effect("bind_silence") if owner and owner.build else null
	if (bind and bind.applies_to == p.id and p.affects == ZoneParams.AFFECTS_HOSTILE
			and not (player and player.state.dead)):
		_give_status(zone.owner_id, target, StatusDefs.current().index_of(bind.status), 1, -1)


## Conflagration capstone ("zone_grow", applies_to = a status): the owner's
## pulse zones that apply that status (burning ground) grow by amount x their
## size each pulse, up to threshold x. 0 = no growth.
func zone_growth(zone: Zone) -> Vector2:
	var owner := _player_by_id(zone.owner_id)
	if owner == null or owner.build == null:
		return Vector2.ZERO
	for weapon_id in owner.build.weapons:
		var node := owner.build.weapon_effect(weapon_id, "zone_grow")
		if node and node.applies_to == zone.params.applies_status:
			return Vector2(node.amount, node.threshold)
	return Vector2.ZERO


## Extra re-arms for a trap `owner_id` places (the Crossbow's Trapper capstone,
## "trap_rearm" in the tree of one of its equipped weapons). 0 for other zones.
func trap_rearms(owner_id: int, p: ZoneParams) -> int:
	var owner := _player_by_id(owner_id)
	if owner == null or owner.build == null or p.trigger != ZoneParams.TRIGGER_TRAP:
		return 0
	for weapon_id in owner.build.weapons:
		var node := owner.build.weapon_effect(weapon_id, "trap_rearm")
		if node:
			return roundi(node.amount)
	return 0


## A decoy ended. The Assassin Wings' Mirror Image capstone ("decoy_burst"):
## it bursts, dealing the node's amount to every hostile within its threshold
## (m) and giving them its status.
func on_decoy_ended(zone: Zone) -> void:
	var owner := _player_by_id(zone.owner_id)
	var node := owner.build.wing_effect("decoy_burst") if owner and owner.build else null
	if node == null:
		return
	_decoy_bursts += 1
	var status := StatusDefs.current().index_of(node.status)
	for enemy: Enemy in _enemies.get_children():
		if enemy.dead or enemy.global_position.distance_to(zone.position) > node.threshold:
			continue
		if not _damage_enemy(enemy, node.amount * enemy.statuses.damage_taken_multiplier(
				enemy.status_defs), 0, owner.peer_id, HIT_DAMAGED) and status >= 0:
			_give_status(owner.peer_id, enemy, status, 1, -1)
	for player: Player in _players.get_children():
		if (player.state.dead or are_allies(owner.peer_id, player.peer_id)
				or player.global_position.distance_to(zone.position) > node.threshold):
			continue
		player.health = maxf(0.0, player.health - node.amount)
		if player.health <= 0.0:
			_kill_player(player)
			_send_hit(owner.peer_id, player.peer_id, node.amount, HIT_DEFEATED)
			continue
		_send_hit(owner.peer_id, player.peer_id, node.amount, HIT_DAMAGED)
		if status >= 0:
			_give_status(owner.peer_id, player, status, 1, -1)


## Fire Trail: a roll while the player has a status with roll_zone places that
## zone where the roll starts and uses up one stack.
func _roll_zone(player: Player) -> void:
	var defs := player.params.statuses
	for e in player.state.statuses.entries:
		var def := defs.get_def(e.status)
		if def and not def.roll_zone.is_empty():
			zones.server_spawn(def.roll_zone, player.peer_id, player.global_position, player.state.yaw)
			player.state.use_status_stack(e.status)
			return


## Shadow Swap ("swap_places"): the player trades places with its newest decoy,
## or else with the nearest living target it Marked (StatusEffects.mark_from)
## within swap_range. Teleports are server events (PlayerState.note_teleport).
func _shadow_swap(player: Player, ability: AbilityParams) -> void:
	var from := player.global_position
	var decoy := zones.decoy_for(player.peer_id)
	if decoy:
		_teleport(player, decoy.position)
		zones.server_move(decoy, from)
		_shadow_swaps += 1
		return
	var best: Node3D = null
	var best_distance := ability.swap_range
	for enemy: Enemy in _enemies.get_children():
		var d := enemy.global_position.distance_to(from)
		if not enemy.dead and d <= best_distance and enemy.statuses.mark_from(enemy.status_defs, player.peer_id) >= 0:
			best = enemy
			best_distance = d
	for other: Player in _players.get_children():
		var d := other.global_position.distance_to(from)
		if (other != player and not other.state.dead and d <= best_distance
				and other.state.statuses.mark_from(other.params.statuses, player.peer_id) >= 0):
			best = other
			best_distance = d
	if best == null:
		return
	var to := best.global_position
	_teleport(player, to)
	if best is Player:
		_teleport(best as Player, from)
	else:
		best.global_position = from
	_shadow_swaps += 1


func _teleport(player: Player, to: Vector3) -> void:
	player.global_position = to
	player.velocity = Vector3.ZERO
	player.state.note_teleport()


# --- Juggernaut: War Hammer capstones, Wing tree effects (server only) ---

## Server, every live tick of a player's attack: the War Hammer capstones of
## the weapon that's out. Earthshaker ("heavy_shockwave"): each heavy is
## counted once (HeavyCounter); every amount-th sends out the internal ability
## applies_to's projectile from where the player stands (the spawn reaches
## every client, the thrower's included). Breaker ("heavy_breaks_block"):
## returns a copy of the heavy that always breaks blocks. Otherwise returns
## `attack` unchanged. Never touches the predicted sim.
func _with_hammer_capstones(attacker: Player, attack: AttackParams) -> AttackParams:
	if attacker.build == null or attacker.state.attack_type != PlayerState.ATTACK_HEAVY:
		return attack
	var weapon_id := attacker.state.weapon_id()
	var shock := attacker.build.weapon_effect(weapon_id, "heavy_shockwave")
	if shock and attacker.heavy_counter.register(attacker.state.attack_serial, roundi(shock.amount)):
		var weapon := attacker.state.weapon(attacker.params)
		var wave := weapon.ability(weapon.ability_index(shock.applies_to))
		if wave:
			_aftershocks += 1
			_projectiles.server_fire_attack(attacker, wave)
	if attacker.build.weapon_effect(weapon_id, "heavy_breaks_block") and not attack.breaks_block:
		var breaking := attack.copy()
		breaking.breaks_block = true
		return breaking
	return attack


## Server: where a hit's force moves its target (ForceParams.displacement). A
## player attacker's "force_distance" Wing passives (Tempest Wings) push
## knockbacks and shoves farther (ForceParams.scaled), never pulls.
func _force_displacement(attacker_id: int, force: ForceParams, attacker_pos: Vector3,
		attacker_yaw: float, target_pos: Vector3, p: PlayerParams) -> Vector2:
	var moved := force.displacement(attacker_pos, attacker_yaw, target_pos, p.force_max_distance,
			p.force_pull_gap)
	var attacker := _player_by_id(attacker_id) if attacker_id > 0 else null
	if attacker == null or attacker.build == null or force.direction == ForceParams.DIRECTION_TOWARD:
		return moved
	return ForceParams.scaled(moved, attacker.build.wing_effect_amount("force_distance"),
			p.force_max_distance)


## The wall_stun_source for a force a player (attacker_id) just started: the
## attacker if it has the Tempest Wings capstone ("wall_stun") and it isn't a
## pull, else 0.
func _wall_stun_source(attacker_id: int, force: ForceParams) -> int:
	var attacker := _player_by_id(attacker_id) if attacker_id > 0 else null
	if (attacker == null or attacker.build == null or force.direction == ForceParams.DIRECTION_TOWARD
			or attacker.build.wing_effect("wall_stun") == null):
		return 0
	return attacker_id


## Server, after a player or enemy moved this tick: Tempest Wings. A target
## knocked back by a player with the capstone (wall_stun_source) that was
## driven into a wall (ForcedMotion.pushed_into_wall) gets the capstone's
## status (a stun) for amount seconds, once per knockback, through
## _give_status (allies and immunities refuse it).
func _check_wall_stun(target: Node3D) -> void:
	var player := target as Player
	var enemy := target as Enemy
	var source_id: int = player.wall_stun_source if player else enemy.wall_stun_source
	if source_id == 0:
		return
	var force: ForcedMotion = player.state.force if player else enemy.force
	var body := target as CharacterBody3D
	var dead: bool = player.state.dead if player else enemy.dead
	if not dead and force.is_active() and not (body.is_on_wall()
			and ForcedMotion.pushed_into_wall(force.velocity, body.get_wall_normal())):
		return  # still being pushed, no wall yet
	if player:
		player.wall_stun_source = 0
	else:
		enemy.wall_stun_source = 0
	if dead or not force.is_active():
		return
	var source := _player_by_id(source_id)
	var node := source.build.wing_effect("wall_stun") if source and source.build else null
	if node == null:
		return
	var ticks := roundi(node.amount * Engine.physics_ticks_per_second)
	if _give_status(source_id, target, StatusDefs.current().index_of(node.status), 1, ticks):
		_wall_stuns += 1
		if _verbose:
			print("[server] %d knocked into a wall: stunned" % (player.peer_id if player else enemy.enemy_id))


## Server: a taunt from source_id landed on an enemy. With the Anchor capstone
## ("roar_guard") and the taunt coming from its ability (applies_to, i.e.
## Challenger's Roar is running), the source gains amount stacks of the
## capstone's status (Defiant: stacking damage reduction).
func _roar_guard(source_id: int) -> void:
	var source := _player_by_id(source_id) if source_id > 0 else null
	if source == null or source.build == null or source.state.dead:
		return
	var node := source.build.wing_effect("roar_guard")
	if node == null or not source.state.is_using_ability():
		return
	if source.state.current_ability(source.params).id != node.applies_to:
		return
	if _give_status(source_id, source, StatusDefs.current().index_of(node.status),
			maxi(1, roundi(node.amount)), -1):
		_roar_guards += 1


func _print_juggernaut_summary() -> void:
	print("SUMMARY juggernaut crits=%d hook_staggers=%d brace_staggers=%d bloodied_stacks=%d aftershocks=%d wall_stuns=%d roar_guards=%d" % [
			_crits, _hook_staggers, _brace_staggers, _ramp_stacks, _aftershocks, _wall_stuns,
			_roar_guards])
	print("SUMMARY summons decoy_bursts=%d shadow_swaps=%d" % [_decoy_bursts, _shadow_swaps])
	print("SUMMARY mage ally_supports=%d shields=%d absorbed=%d focus_refunds=%d aura_refunds=%d" % [
			_ally_supports, _shields, roundi(_absorbed), _focus_refunds, _aura_refunds])
	print("SUMMARY ranger ignites=%d ignited_stacks=%d loaded_shots=%d piercing_heavies=%d parting_shots=%d hunted_hits=%d" % [
			_ignites, _ignited_stacks, _loaded_shots, _piercing_heavies, _parting_shots, _hunted_hits])
	print("SUMMARY assassin backstabs=%d primed_crits=%d feint_reads=%d marked_hits=%d flurry_fans=%d heal_cuts=%d" % [
			_backstabs, _primed_crits, _feint_reads, _marked_hits, _flurry_fans, _heal_cuts])


## Server: a player's health reached 0 (a hit or damage over time). With
## enough Ember and Rebirth ready, a Rebirth starts (_server_dead_player raises
## them when it's done); otherwise the respawn timer.
func _kill_player(target: Player) -> void:
	target.state.kill()
	_deaths += 1
	if target.state.start_rebirth(target.params):
		target.respawn_at_tick = -1
		_rebirths_started += 1
		print("[server] peer %d rebirth started" % target.peer_id)
		return
	target.respawn_at_tick = _tick + target.params.respawn_ticks


## Server: damages an enemy (a hit, or damage over time) and reports it with
## alive_result, or HIT_DEFEATED if it died. Returns true if it died.
func _damage_enemy(enemy: Enemy, damage: float, stagger_ticks: int, attacker_id: int,
		alive_result: int) -> bool:
	var killed := enemy.take_hit(damage, stagger_ticks, attacker_id)
	if killed:
		enemy.respawn_at_tick = _tick + enemy.params.respawn_ticks
		_enemy_kills += 1
		loot.on_enemy_killed(enemy)
	_send_hit(attacker_id, enemy.enemy_id, damage, HIT_DEFEATED if killed else alive_result)
	return killed


## Server: if the target is in a parry window (Riposte) and the attacker is in
## front of it, the hit is negated and the target starts its counter strike,
## turned toward the attacker. Returns true if parried.
func _try_parry(attacker_id: int, attacker_pos: Vector3, target: Player) -> bool:
	if not target.state.is_parrying(target.params):
		return false
	var parry := target.state.current_ability(target.params)
	if not MeleeHitbox.is_in_front(target.global_position, target.state.yaw, attacker_pos,
			parry.parry_arc):
		return false
	var to_attacker := Vector2(attacker_pos.x - target.global_position.x,
			attacker_pos.z - target.global_position.z)
	var face := target.state.yaw
	if not to_attacker.is_zero_approx():
		face = PlayerState.yaw_for_direction(to_attacker)
	target.state.start_counter(target.params, face)
	_parries += 1
	_send_hit(attacker_id, target.peer_id, 0.0, HIT_PARRIED)
	return true


# --- Forced movement (the FORCE tag) ---

## Server: a hit from `attack` landed on a player (damaged or guard broken, not
## evaded, blocked, parried or fatal): starts its knockback / pull / launch, if
## it has one. Allies never move each other (checked here too, though
## _strike_player already skips them). An attack with force_needs_stagger only
## moves a target that was staggered before this hit. PlayerState.start_force
## refuses targets in i-frames, dead or immune. A server event, so the target's
## client reconciles without counting a correction.
func _force_player(attacker_id: int, attacker_pos: Vector3, attacker_yaw: float,
		attack: AttackParams, target: Player, was_staggered: bool) -> void:
	var force := attack.force
	if force == null or (force.needs_stagger and not was_staggered):
		return
	if are_allies(attacker_id, target.peer_id):
		return
	var p := target.params
	var tps := float(Engine.physics_ticks_per_second)
	var moved := target.state.start_force(p,
			_force_displacement(attacker_id, force, attacker_pos, attacker_yaw,
					target.global_position, p),
			force.ticks(p.gravity, p.force_max_height, tps),
			force.launch_speed(p.gravity, p.force_max_height), 1.0 / tps)
	if not moved:
		return
	target.wall_stun_source = _wall_stun_source(attacker_id, force)
	_forced_players += 1
	if attacker_id > 0:
		_forced_pvp += 1
	if force.height > 0.0:
		_launches += 1
	if _verbose:
		print("[server] %d moves %d (force)" % [attacker_id, target.peer_id])


## Server: like _force_player, for a player's hit on an enemy (which survived).
func _force_enemy(attacker_pos: Vector3, attacker_yaw: float, attack: AttackParams, enemy: Enemy,
		was_staggered: bool, attacker_id := 0) -> void:
	var force := attack.force
	if force == null or (force.needs_stagger and not was_staggered):
		return
	var p := PlayerParams.current()
	var tps := float(Engine.physics_ticks_per_second)
	var moved := enemy.start_force(
			_force_displacement(attacker_id, force, attacker_pos, attacker_yaw,
					enemy.global_position, p),
			force.ticks(p.gravity, p.force_max_height, tps),
			force.launch_speed(p.gravity, p.force_max_height), 1.0 / tps)
	if not moved:
		return
	enemy.wall_stun_source = _wall_stun_source(attacker_id, force)
	_forced_enemies += 1
	if force.height > 0.0:
		_launches += 1
	if _verbose:
		print("[server] enemy %d moved (force)" % enemy.enemy_id)


func _print_force_summary() -> void:
	var uses := PackedStringArray()
	for weapon_id: String in _ability_uses_by_weapon:
		uses.append("%s=%d" % [weapon_id, _ability_uses_by_weapon[weapon_id]])
	print("SUMMARY force players=%d pvp=%d enemies=%d launches=%d" % [
			_forced_players, _forced_pvp, _forced_enemies, _launches])
	print("SUMMARY ability_uses_by_weapon %s" % " ".join(uses))


func _spawn_enemies() -> void:
	var next_id := -1
	for marker: Marker3D in $EnemySpawns.get_children():
		var enemy: Enemy = ENEMY_SCENE.instantiate()
		enemy.enemy_id = next_id
		enemy.name = str(next_id)
		enemy.kind = marker.get_meta("kind", "husk")
		enemy.home = marker.position
		enemy.position = marker.position
		enemy.attack_stepped.connect(_on_enemy_attack_stepped)
		_enemies.add_child(enemy)
		next_id -= 1


## Server: brings a dead player back at a random spawn point with full health.
## The point must be exactly on the ground: the body's on-floor flag isn't synced,
## so a mid-air teleport makes the client's prediction disagree for a tick.
func _respawn(player: Player) -> void:
	var angle := randf() * TAU
	player.global_position = Vector3(cos(angle), 0.0, sin(angle)) * SPAWN_RADIUS
	player.velocity = Vector3.ZERO
	player.health = player.max_health()
	player.state.revive(player.params)
	player.respawn_at_tick = -1
	_respawns += 1
	print("[server] peer %d respawned" % player.peer_id)


## Ids are peer ids for players and negative ids for enemies.
func _send_hit(attacker_id: int, target_id: int, damage: float, result: int) -> void:
	if _verbose:
		print("[server] %d -> %d: %s %d" % [attacker_id, target_id, HIT_NAMES[result], damage])
	for peer_id in _connected_player_ids():
		_receive_hit.rpc_id(peer_id, attacker_id, target_id, damage, result)


# --- Statuses ---

## Server: a hit damaged target (a Player or an Enemy). Applies the attack's
## own status (applies_status) and the attacker's on-hit statuses (on_hit:
## [index, stacks] each, from StatusEffects.take_on_hit_statuses, e.g.
## Bloodlust's bleed).
func _give_hit_statuses(source_id: int, attack: AttackParams, on_hit: Array[Vector2i],
		target: Node3D) -> void:
	var defs := StatusDefs.current()
	for status: Array in attack.target_statuses():
		_give_status(source_id, target, defs.index_of(status[0]), status[1], status[2])
	for status in on_hit:
		_give_status(source_id, target, status.x, status.y, -1)


## Server: applies one status from source_id to target (a Player or an Enemy).
## Allies never debuff each other. A player's status is a server event.
## Returns true if applied.
func _give_status(source_id: int, target: Node3D, index: int, stacks: int,
		duration_ticks: int) -> bool:
	var def := StatusDefs.current().get_def(index)
	if def == null:
		return false
	var player := target as Player
	var enemy := target as Enemy
	var target_id := player.peer_id if player else enemy.enemy_id
	var between_allies := source_id != target_id and are_allies(source_id, target_id)
	if def.is_debuff() and between_allies:
		_ally_statuses_refused += 1
		return false
	var applied := false
	var cap := _stack_cap(source_id, def)
	if player:
		applied = player.state.apply_status(player.params, index, stacks, duration_ticks, source_id,
				cap)
	else:
		applied = enemy.apply_status(index, stacks, duration_ticks, source_id, cap)
	if not applied:
		return false
	_statuses_applied += 1
	if enemy:
		_statuses_on_enemies += 1
		if def.forces_target:
			_taunts += 1
			_roar_guard(source_id)
	if def.is_debuff() and between_allies:
		_ally_statuses_applied += 1
	if _verbose:
		print("[server] %d -> %d: status %s x%d" % [source_id, target_id, def.id, stacks])
	return true


## Server: damage over time (bleed) from a player's sim steps this tick.
## Multiplied by its damage_taken statuses (Exposed); can kill.
func _apply_player_status_damage(player: Player) -> void:
	var raw := player.status_damage_pending
	player.status_damage_pending = 0.0
	if raw <= 0.0 or player.state.dead:
		return
	var damage := (raw * player.state.statuses.damage_taken_multiplier(player.params.statuses)
			* player.damage_taken_multiplier() * _crowd_multiplier(player))
	player.health = maxf(0.0, player.health - damage)
	_status_ticks += 1
	_status_damage += damage
	_ember_from_damage(player.state.statuses.last_damage_source, player, damage)
	var result := HIT_STATUS_DAMAGE
	if player.health <= 0.0:
		result = HIT_DEFEATED
		_kill_player(player)
	_send_hit(player.state.statuses.last_damage_source, player.peer_id, damage, result)


## Server: damage over time (bleed) from an enemy's server_step this tick.
func _apply_enemy_status_damage(enemy: Enemy) -> void:
	var raw := enemy.status_damage
	enemy.status_damage = 0.0
	if raw <= 0.0 or enemy.dead:
		return
	var damage := raw * enemy.statuses.damage_taken_multiplier(enemy.status_defs)
	_status_ticks += 1
	_status_damage += damage
	_ember_from_damage(enemy.statuses.last_damage_source, null, damage)
	_damage_enemy(enemy, damage, 0, enemy.statuses.last_damage_source, HIT_STATUS_DAMAGE)


# --- Ember, Wings and Rebirth ---

## Server: a dead player. A finished Rebirth rises where it fell; otherwise
## the normal respawn timer.
func _server_dead_player(player: Player) -> void:
	if player.state.is_rebirthing():
		if player.state.rebirth_done():
			_rebirth(player)
	elif _tick >= player.respawn_at_tick:
		_respawn(player)


## Server: a Rebirth is over: back where they fell with rebirth_health, the
## Ember left after its cost, and the Rebirth cooldown running.
func _rebirth(player: Player) -> void:
	player.health = player.max_health() * player.params.rebirth_health_fraction
	player.state.finish_rebirth(player.params)
	_rebirths += 1
	print("[server] peer %d rose again (rebirth)" % player.peer_id)


## Server: Ember for damage. The target (a Player; null for an enemy) gains
## for damage taken, the attacker (if it's a player) for damage dealt; both are
## then in combat (even for a fully blocked hit).
func _ember_from_damage(attacker_id: int, target: Player, damage: float) -> void:
	if target:
		_give_ember(target, damage * target.params.ember_per_damage_taken, true)
	var attacker := _player_by_id(attacker_id)
	if attacker and attacker != target:
		_give_ember(attacker, damage * attacker.params.ember_per_damage_dealt, true)


## Server: adds Ember to a player (a server event; nothing while dead).
func _give_ember(player: Player, amount: float, in_combat: bool) -> void:
	if player.state.dead:
		return
	var before := player.state.ember
	amount *= 1.0 + player.gear.bonus("ember_gain_pct")  # Kindle
	if player.build:
		amount *= player.build.class_def.ember_gain  # the Mage gains more
	player.state.gain_ember(player.params, amount, in_combat)
	_ember_gained += player.state.ember - before


## Server: heals a player, capped at max health, and gives the healer Ember for
## the health really restored (the one place every heal goes through: Pyre
## Heart and the Mantle of Renewal now, allies' heals later). healer_id: a peer
## id, or 0 for the target itself. Healing isn't combat. Returns the health
## restored.
func _heal_player(target: Player, amount: float, healer_id: int) -> float:
	if target.state.dead or amount <= 0.0:
		return 0.0
	amount *= (1.0 + target.gear.bonus("healing_pct")) * _heal_cut(target)  # Tend, Venom
	amount *= target.state.statuses.healing_multiplier(target.params.statuses, false)  # Withering
	var source := _player_by_id(healer_id)
	if source:
		amount *= source.state.statuses.healing_multiplier(source.params.statuses, true)  # Aura
	var healed := minf(amount, target.max_health() - target.health)
	_overheal_shield(source, target, amount - maxf(healed, 0.0))
	if healed <= 0.0:
		return 0.0
	target.health += healed
	_heals += 1
	_healed += healed
	var healer := _player_by_id(healer_id)
	if healer == null:
		healer = target
	_give_ember(healer, healed * healer.params.ember_per_heal, false)
	# Healing someone an enemy is fighting draws its attention to the healer.
	for enemy: Enemy in _enemies.get_children():
		if not enemy.dead and enemy.brain.threat.has(target.peer_id):
			enemy.on_heal(target.peer_id, healer.peer_id, healed)
			_heal_threat += 1
	_send_hit(healer.peer_id, target.peer_id, healed, HIT_HEALED)
	return healed


## Server: healing over time (Pyre Heart) from a player's sim steps this tick.
func _apply_player_status_heal(player: Player) -> void:
	var amount := player.status_heal_pending
	player.status_heal_pending = 0.0
	if amount > 0.0:
		_heal_player(player, amount, player.state.statuses.last_heal_source)


func _on_wing_started(player: Player) -> void:
	var wing := player.state.current_ability(player.params)
	_wing_uses += 1
	_ember_spent += wing.ember_cost
	if _verbose:
		print("[server] peer %d uses wing %s (ember %.0f left)" % [player.peer_id, wing.id,
				player.state.ember])


## The status index of the self-buff a player's Wing ability gives (e.g. Ember
## Mantle's Warded), or -1.
func _wing_self_status(player: Player, ability_id: String) -> int:
	var pool := player.state.wings(player.params)
	var wing := pool.ability(pool.ability_index(ability_id))
	if wing == null or wing.self_status.is_empty():
		return -1
	return player.params.statuses.index_of(wing.self_status)


## Server: an attacker's stagger, with the Crushing Wingbeat capstone
## ("surge_stagger"): while its Wing ability's self-buff (Wingbeat Surge's
## Empowered) is on, hits stagger for at least the node's amount (seconds).
func _with_surge_stagger(attacker_id: int, stagger_ticks: int) -> int:
	var attacker := _player_by_id(attacker_id)
	if attacker == null or attacker.build == null:
		return stagger_ticks
	var node := attacker.build.wing_effect("surge_stagger")
	if node == null or not attacker.state.statuses.has(_wing_self_status(attacker, node.applies_to)):
		return stagger_ticks
	return maxi(stagger_ticks, roundi(node.amount * Engine.physics_ticks_per_second))


## Server, after a hit the target survived: the Mantle of Renewal capstone
## ("mantle_heal") heals the node's amount x the damage its Wing ability's
## self-buff (Ember Mantle's Warded) prevented.
func _mantle_heal(target: Player, base_damage: float, guarded: bool) -> void:
	if target.build == null:
		return
	var node := target.build.wing_effect("mantle_heal")
	if node == null:
		return
	var index := _wing_self_status(target, node.applies_to)
	var stacks := target.state.statuses.stacks(index)
	if stacks <= 0:
		return
	var prevented := base_damage * maxf(0.0, -target.params.statuses.get_def(index).damage_taken * stacks)
	if guarded:
		prevented *= target.params.block_damage_taken
	_heal_player(target, prevented * node.amount, target.peer_id)


## A player by peer id (null for enemies' ids, 0 or a player who left).
func _player_by_id(id: int) -> Player:
	if id <= 0:
		return null
	return _players.get_node_or_null(str(id)) as Player


func _print_ember_summary() -> void:
	print("SUMMARY ember gained=%d spent=%d wing_uses=%d rebirths_started=%d rebirths=%d heals=%d healed=%d" % [
			roundi(_ember_gained), roundi(_ember_spent), _wing_uses, _rebirths_started, _rebirths,
			_heals, roundi(_healed)])


# --- Parties and allies ---

## The single answer to "are these two on the same side?". Ids are peer ids for
## players and negative ids for enemies: a player is its own ally, members of
## the same party are allies, and enemies are never allies (PartyRules.allied).
## Authoritative on the server; a client only knows its own party.
func are_allies(a: int, b: int) -> bool:
	return party.are_allies(a, b)


## World/Party must exist on the server and every client: its RPCs are matched
## by node path.
func _add_party_system() -> void:
	party = PartySystem.new()
	party.name = "Party"
	party.players = _players
	add_child(party)


## World/Zones must exist on the server and every client (RPCs by path).
func _add_zone_system() -> void:
	zones = ZoneSystem.new()
	zones.name = "Zones"
	zones.world = self
	zones.players = _players
	zones.enemies = _enemies
	add_child(zones)


## World/Loot must exist on the server and every client (RPCs by path).
func _add_loot_system() -> void:
	loot = LootSystem.new()
	loot.name = "Loot"
	loot.players = _players
	loot.builds = _builds
	_builds.loot = loot
	add_child(loot)


# --- Projectiles (the PROJ tag; see ProjectileSystem) ---

## World/Projectiles must exist on the server and every client (RPCs by path).
func _add_projectile_system() -> void:
	_projectiles = ProjectileSystem.new()
	_projectiles.name = "Projectiles"
	_projectiles.world = self
	_projectiles.players = _players
	_projectiles.enemies = _enemies
	add_child(_projectiles)


func server_tick() -> int:
	return _tick


func is_verbose() -> bool:
	return _verbose


## Client: the render clock in server ticks (what remote players are drawn
## at), or -1 before the first snapshot.
func render_tick() -> float:
	return _render_time * Engine.physics_ticks_per_second if _render_time >= 0.0 else -1.0


## Bot: seconds into its 8 s cycle (see _bot_input).
func bot_phase() -> float:
	return fmod(Time.get_ticks_msec() / 1000.0, 8.0)


## Server: a projectile connected (any result but an ally pass), for the same
## counters melee hits feed (the party check's pvp_hits, ability_hits).
func note_projectile_hit(from_ability: bool, on_player: bool) -> void:
	if on_player:
		_pvp_hits += 1
	if from_ability:
		_ability_hits += 1


# --- Client ---

func _client_tick(delta: float) -> void:
	var move := Vector2.ZERO
	var buttons := 0
	var aim_yaw := _local_player.get_camera_yaw()
	var aim_pitch := _local_player.get_camera_pitch()
	if _bot:
		aim_pitch = 0.0  # level: pitch-aimed leaps go their full distance
		if (not _bot_status_slots_sent and _builds.local_build
				and _local_player.state.can_change_loadout()):
			_builds.bot_slot_status_abilities(_local_player.params)
			_bot_status_slots_sent = true
		var bot := _bot_input()
		move = bot[0]
		buttons = bot[1]
		aim_yaw = bot[2]
		if not LaunchArgs.get_value("screenshot-dir").is_empty():
			# Screenshots look where the bot aims (its throws fly away from the
			# camera); its move is world space, so undo the camera's turn.
			_local_player.set_camera_yaw(aim_yaw)
			var world_move := Vector3(move.x, 0.0, move.y).rotated(Vector3.UP, -aim_yaw)
			move = Vector2(world_move.x, world_move.z)
		if not party.bot_may_attack():
			buttons &= ~(PlayerState.BUTTON_ATTACK | PlayerState.BUTTON_ABILITY_1
					| PlayerState.BUTTON_ABILITY_2 | PlayerState.BUTTON_ABILITY_3
					| PlayerState.BUTTON_WING_1 | PlayerState.BUTTON_WING_2)
	else:
		move = Input.get_vector(&"move_left", &"move_right", &"move_forward", &"move_back")
		if Input.is_action_pressed(&"jump"):
			buttons |= PlayerState.BUTTON_JUMP
		if Input.is_action_just_pressed(&"dodge"):
			buttons |= PlayerState.BUTTON_DODGE
		buttons |= _ability_and_swap_buttons()
		var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
		var attack_held := Input.is_action_pressed(&"attack")
		if not captured or not attack_held:
			_attack_blocked = not captured
		if captured and attack_held and not _attack_blocked:
			buttons |= PlayerState.BUTTON_ATTACK
		if captured and Input.is_action_pressed(&"block"):
			buttons |= PlayerState.BUTTON_BLOCK
	var inputs := _local_player.client_predict(move, buttons, aim_yaw, aim_pitch, delta,
			_input_redundancy)
	_submit_inputs.rpc_id(1, inputs)


## Keys for this tick: Q / E / R (abilities), Z / C (Wings) and X (weapon
## swap), sent only on the tick they're pressed.
func _ability_and_swap_buttons() -> int:
	var buttons := 0
	if Input.is_action_just_pressed(&"swap_weapon"):
		buttons |= PlayerState.BUTTON_SWAP
	for slot in PlayerState.ABILITY_SLOTS:
		if Input.is_action_just_pressed(StringName("ability_%d" % (slot + 1))):
			buttons |= PlayerState.BUTTON_ABILITY_1 << slot
	for slot in PlayerState.WING_SLOTS:
		if Input.is_action_just_pressed(StringName("wing_%d" % (slot + 1))):
			buttons |= PlayerState.BUTTON_WING_1 << slot
	return buttons


## Bot input for testing without a second person. Repeats every 8 s:
## 0–4 s: fight. The target is the nearest living enemy within BOT_ENEMY_RANGE,
## or else the nearest other player. The fight has two 2 s turns; the bot with
## the lower peer id (compared with the nearest other player) attacks in the
## first, the other in the second. On its turn a bot holds for a heavy, then taps
## two lights; off its turn it holds block.
## 4–6 s: abilities, same target. Both bots hold block and each presses two
## different ability slots, about 1 s apart: the first bot at 4.0 and 5.0, the
## other at 4.5 and 5.5 (each first press waits up to 0.3 s for the target to
## be within BOT_ABILITY_REACH; see _bot_ability_button for which ability).
## On its own turn and in the ability phase, a ready self-buff (Bloodlust) is
## used once the target is within BOT_BUFF_REACH (_bot_self_buff_input).
## Wing abilities: see _bot_wing_input (Surge, Mantle, Diving Strike); at 7.6
## it also respecs its Wing slots for the next cycle (BuildService.bot_respec_wings).
## 6–8 s: walk in circles; swap weapons at 6.95 (after any ability; again at
## 7.2 if that press didn't swap), jump at
## 7.25, air dodge at 7.4, ground dodge at 7.95, and a free respec at 7.6
## of the next cycle's focus weapon (BuildService.bot_respec; odd cycles also
## learn and slot new abilities, e.g. Rising Cut) and that cycle's weapons.
## Weapons: the default loadout in the first cycle, then a focus weapon is out
## for the fight and abilities, two cycles at a time, starting with the Spear
## (BuildService.bot_weapons_for_cycle); X swaps to the other one for the
## circling, and the 7.6 request puts the next focus out.
## Fighting comes first because players spawn close together.
## Returns [move, buttons, aim_yaw].
func _bot_input() -> Array:
	var t := Time.get_ticks_msec() / 1000.0
	var phase := bot_phase()
	var cycle := floori(t / 8.0)
	if phase < 3.5:
		_bot_sync_weapons(cycle)
	var crossed := func(at: float) -> bool: return _bot_last_phase < at and phase >= at
	var move := Vector2.ZERO
	var buttons := 0
	var aim_yaw := 0.0
	if phase < 4.0:
		_bot_first_ability_pressed = false
	if phase >= 6.0:
		var circle_t := t + float(multiplayer.get_unique_id() % 100)
		move = Vector2(cos(circle_t * 0.8), sin(circle_t * 0.8))
		if crossed.call(6.95):
			buttons |= PlayerState.BUTTON_SWAP
			_bot_swaps_before = _local_player.swaps
		elif crossed.call(7.2) and _local_player.swaps == _bot_swaps_before:
			buttons |= PlayerState.BUTTON_SWAP  # the first press didn't swap (e.g. staggered)
		if phase >= 7.25 and phase < 7.3:
			buttons |= PlayerState.BUTTON_JUMP
		if crossed.call(7.4) or crossed.call(7.95):
			buttons |= PlayerState.BUTTON_DODGE
		if crossed.call(7.6):
			var next := _builds.bot_weapons_for_cycle(cycle + 1)
			if not next.is_empty():
				_builds.bot_respec(next[0], cycle)
				_builds.bot_request_weapons(next, _local_player.state.equipped)
			_builds.bot_respec_wings(cycle + 1)
	else:
		var other_player := _nearest_remote_player()
		var target: Node3D = _nearest_enemy(BOT_ENEMY_RANGE)
		if target == null:
			target = other_player
		if target:
			var to := target.global_position - _local_player.global_position
			var flat := Vector2(to.x, to.z)
			aim_yaw = PlayerState.yaw_for_direction(flat)
			if flat.length() > BOT_ATTACK_DISTANCE:
				move = flat.normalized()
			var first_turn := other_player == null or multiplayer.get_unique_id() < other_player.peer_id
			var turn_start := 0.0 if first_turn else 2.0
			var turn_time := phase - turn_start
			if phase >= 4.0:
				# Abilities: guard up between them (an ability drops it, holding block
				# brings it back), alternating with the other bot every 0.5 s. The
				# first waits up to 0.3 s for the target to be within reach.
				buttons |= PlayerState.BUTTON_BLOCK
				var offset := 0.0 if first_turn else 0.5
				if (not _bot_first_ability_pressed and phase >= 4.0 + offset
						and (flat.length() <= BOT_ABILITY_REACH or phase >= 4.3 + offset)):
					_bot_first_ability_pressed = true
					buttons |= _bot_ability_button(cycle * 2, true)
				elif crossed.call(5.0 + offset):
					buttons |= _bot_ability_button(cycle * 2 + 1, false)
			elif turn_time < 0.0 or turn_time >= 2.0:
				# Guard up for the whole off turn: other players are drawn ~0.1 s in
				# the past, too late to react to a light attack's windup.
				buttons |= PlayerState.BUTTON_BLOCK
			elif turn_time < 0.3:
				buttons |= PlayerState.BUTTON_ATTACK  # held 0.3 s: heavy
			elif crossed.call(turn_start + 1.35) or crossed.call(turn_start + 1.75):
				buttons |= PlayerState.BUTTON_ATTACK  # one tick: light on release
			if phase >= 4.0 or (turn_time >= 0.0 and turn_time < 2.0):
				# Not on the off turn: that guard stays up.
				buttons |= _bot_self_buff_input(flat.length(), t, cycle)
			buttons |= _bot_wing_input(cycle, phase, turn_time, flat.length())
			if (buttons & ABILITY_BUTTONS) == 0:
				buttons |= _bot_projectile_button(flat.length())
	_bot_last_phase = phase
	return [move, buttons, aim_yaw]


## One of the equipped weapon's filled ability slots. The farthest-knockback
## ability (one whose force doesn't need a staggered target, e.g. Low Sweep) is
## always the first press of a cycle (even turns), and the second press uses it
## again only if it's off cooldown (the smoke test shortens Low Sweep's), so
## forced movement gets exercised whenever that weapon is out. Otherwise the
## first press of the phase (irst) prefers a ready self-buff (Bloodlust, so
## the second press's hits carry it), else a ready ability that applies a status
## (Opening Strike); the rest rotate through the ready abilities without a
## self-buff with 	urn (offset by peer id so two bots differ).
func _bot_ability_button(turn: int, first: bool = false) -> int:
	var state := _local_player.state
	var weapon := state.weapon(_local_player.params)
	var filled: Array[int] = []
	var hitting: Array[int] = []
	var force_slot := -1
	var farthest := 0.0
	for slot in PlayerState.ABILITY_SLOTS:
		var ability := weapon.ability(state.slot_ability(slot))
		if ability == null:
			continue
		filled.append(slot)
		if ability.self_status.is_empty() and state.cooldown_left(state.slot_ability(slot)) == 0:
			hitting.append(slot)
		var force := ability.force
		if force != null and not force.needs_stagger and force.distance > farthest:
			farthest = force.distance
			force_slot = slot
	if force_slot >= 0:
		if turn % 2 == 0 or state.cooldown_left(state.slot_ability(force_slot)) == 0:
			return PlayerState.BUTTON_ABILITY_1 << force_slot
		filled.erase(force_slot)
		hitting.erase(force_slot)
	if filled.is_empty():
		return 0
	if first:
		for key in ["self_status", "applies_status"]:
			for slot in filled:
				var index := state.slot_ability(slot)
				if not str(weapon.ability(index).get(key)).is_empty() and state.cooldown_left(index) == 0:
					return PlayerState.BUTTON_ABILITY_1 << slot
	var pool := hitting if not hitting.is_empty() else filled
	var slot := pool[(turn + multiplayer.get_unique_id()) % pool.size()]
	return PlayerState.BUTTON_ABILITY_1 << slot


## Bot, on its own fight turn and in the ability phase: a ready self-buff
## (Bloodlust) is used as soon as the target is within BOT_BUFF_REACH, followed
## 0.4 s later by a hitting ability, so the buffed hits land while the target
## is close.
func _bot_self_buff_input(distance: float, t: float, cycle: int) -> int:
	if _bot_followup_at > 0.0 and t >= _bot_followup_at:
		_bot_followup_at = -1.0
		return _bot_ability_button(cycle * 2 + 1, false)
	if distance > BOT_BUFF_REACH or _local_player.state.is_attacking():
		return 0
	var button := _bot_self_buff_button()
	if button != 0:
		_bot_followup_at = t + 0.4
	return button


## Bot Wing abilities (Z / C), at most one press of each ability per cycle, by
## role (_bot_wing_role, so it works for every class's Wings): a damage buff
## (Wingbeat Surge) as its attack turn starts, a burst around it (Gale Burst,
## Challenger's Roar) later in that turn, after its heavy, a
## guard (Ember Mantle, Unbowed) as its block turn starts (or a heal, Pyre
## Heart, if that's slotted and it's hurt), and a dive (Diving Strike, Meteor
## Drop) whenever the target is 3-7 m away before the circling phase. While a
## Rebirth is ready it only spends Ember above the Rebirth threshold, so it
## keeps a Rebirth for its next death (the decision the design asks players to
## make). turn_time: seconds into its attack turn (outside 0-2 = its block turn).
func _bot_wing_input(cycle: int, phase: float, turn_time: float, distance: float) -> int:
	var state := _local_player.state
	if state.is_attacking() or state.dead:
		return 0
	if not _bot_wing_pressed.has("cycle") or _bot_wing_pressed["cycle"] != cycle:
		_bot_wing_pressed = {"cycle": cycle}
	var roles: Array[String] = []
	if distance >= 3.0 and distance <= 7.0:
		roles.append("dive")
	if phase < 4.0 and turn_time >= 0.0 and turn_time < 0.3:
		roles.append("offense")
	if phase < 4.0 and turn_time >= 1.0 and turn_time < 2.0:
		roles.append("burst")  # after its heavy (a press at once would replace it)
	var off_time := turn_time + 2.0 if turn_time < 0.0 else turn_time - 2.0
	if phase < 4.0 and off_time >= 0.0 and off_time < 0.3:
		if _local_player.health < _local_player.max_health() * 0.8:
			roles.append("heal")
		roles.append("guard")
	var wanted: Array[String] = []
	var pool := state.wings(_local_player.params)
	for role in roles:
		for index in (pool.abilities.size() if pool else 0):
			var wing := pool.ability(index)
			if wing and _bot_wing_role(wing) == role:
				wanted.append(wing.id)
	for ability_id in wanted:
		if _bot_wing_pressed.has(ability_id):
			continue
		var slot := _bot_wing_slot(ability_id)
		if slot >= 0:
			_bot_wing_pressed[ability_id] = true
			return PlayerState.BUTTON_WING_1 << slot
	return 0


## Bot: what a Wing ability is for. "dive": it dashes (Diving Strike, Meteor
## Drop); "burst": it hits around you (Gale Burst, Challenger's Roar); "heal":
## its self-buff heals (Pyre Heart); "offense": its self-buff adds damage
## (Wingbeat Surge); "guard": any other self-buff (Ember Mantle, Unbowed).
func _bot_wing_role(wing: AbilityParams) -> String:
	if wing.dash_speed > 0.0:
		return "dive"
	if wing.shape != AttackParams.SHAPE_NONE:
		return "burst"
	var defs := _local_player.params.statuses
	var buff := defs.get_def(defs.index_of(wing.self_status)) if not wing.self_status.is_empty() else null
	if buff and buff.heal_per_interval > 0.0:
		return "heal"
	if buff and buff.damage_dealt > 0.0:
		return "offense"
	return "guard"


## The Wing slot holding a ready, affordable Wing ability, or -1. While a
## Rebirth is ready, affordable means Ember stays at the Rebirth threshold.
func _bot_wing_slot(ability_id: String) -> int:
	var state := _local_player.state
	var params := _local_player.params
	var pool := state.wings(params)
	for slot in PlayerState.WING_SLOTS:
		var index := state.wing_slot_ability(slot)
		var wing := pool.ability(index)
		if wing == null or wing.id != ability_id or state.wing_cooldown_left(index) > 0:
			continue
		var keep := state.rebirth_ember_needed(params) if state.can_rebirth(params) else 0.0
		if state.ember - wing.ember_cost >= keep:
			return slot
	return -1


## Bot, before the circling phase: a ready projectile ability (Javelin Cast,
## Boomerang Axe) is thrown whenever the target is at least BOT_THROW_MIN
## meters away and within BOT_THROW_REACH of the projectile's reach. Returns its
## button, or 0.
func _bot_projectile_button(distance: float) -> int:
	var state := _local_player.state
	if distance < BOT_THROW_MIN or state.is_attacking() or state.dead:
		return 0
	var weapon := state.weapon(_local_player.params)
	for slot in PlayerState.ABILITY_SLOTS:
		var index := state.slot_ability(slot)
		var ability := weapon.ability(index)
		if ability == null or ability.projectile.is_empty() or state.cooldown_left(index) > 0:
			continue
		var kind := ProjectileParams.get_kind(ability.projectile)
		if kind and distance <= kind.reach() * BOT_THROW_REACH:
			return PlayerState.BUTTON_ABILITY_1 << slot
	return 0


## The slot of a ready ability with a self_status (Bloodlust), or 0.
func _bot_self_buff_button() -> int:
	var state := _local_player.state
	var weapon := state.weapon(_local_player.params)
	for slot in PlayerState.ABILITY_SLOTS:
		var index := state.slot_ability(slot)
		var ability := weapon.ability(index)
		if ability and not ability.self_status.is_empty() and state.cooldown_left(index) == 0:
			return PlayerState.BUTTON_ABILITY_1 << slot
	return 0
## Bot: makes sure this cycle's weapons are equipped with the focus weapon out
## (right after joining, or if the 7.6 s request was refused). At most one
## request every 0.5 s, and never mid-attack or mid-swap.
func _bot_sync_weapons(cycle: int) -> void:
	var now := Time.get_ticks_msec()
	if now < _bot_next_weapon_msec or not _local_player.state.can_change_loadout():
		return
	if _builds.bot_request_weapons(_builds.bot_weapons_for_cycle(cycle), _local_player.state.equipped):
		_bot_next_weapon_msec = now + 500


## Skips the training dummy (stationary), so bots fight Husks and each other.
func _nearest_enemy(max_distance: float) -> Enemy:
	var nearest: Enemy
	var best := max_distance
	for enemy: Enemy in _enemies.get_children():
		var distance := enemy.global_position.distance_to(_local_player.global_position)
		if not enemy.dead and not enemy.params.stationary and distance < best:
			best = distance
			nearest = enemy
	return nearest


func _nearest_remote_player() -> Player:
	var nearest: Player
	var best := INF
	for player: Player in _players.get_children():
		if player.is_local:
			continue
		var distance := player.global_position.distance_to(_local_player.global_position)
		if distance < best:
			best = distance
			nearest = player
	return nearest


@rpc("authority", "call_remote", "unreliable_ordered", 2)
func _receive_snapshot(tick: int, states: Array, enemy_states: Array) -> void:
	_snapshots_received += 1
	var server_time := tick / float(Engine.physics_ticks_per_second)
	_sync_render_clock(server_time)
	var my_id := multiplayer.get_unique_id()
	var seen := {}
	for state: Array in states:
		var peer_id: int = state[0]
		seen[peer_id] = true
		var player := _players.get_node_or_null(str(peer_id)) as Player
		if player == null:
			player = _spawn_client_player(peer_id, peer_id == my_id, state[1])
		if player.is_local:
			player.client_receive_ack(state[1], state[2], state[3], state[4])
		else:
			player.push_snapshot(server_time, state[1], state[4])
		var health: Vector2 = state[5]  # (health, max health)
		player.bonus_max_health = health.y - player.params.max_health
		player.set_health(health.x)
	for player: Player in _players.get_children():
		if not seen.has(player.peer_id):
			print("[client] peer %d left" % player.peer_id)
			_departed_seen[player.peer_id] = player.distance_seen
			_players.remove_child(player)
			player.queue_free()
	_receive_enemy_states(server_time, enemy_states)


## Enemy snapshot entries: Enemy.get_snapshot().
func _receive_enemy_states(server_time: float, enemy_states: Array) -> void:
	var seen := {}
	for state: Array in enemy_states:
		var enemy_id: int = state[0]
		seen[enemy_id] = true
		var enemy := _enemies.get_node_or_null(str(enemy_id)) as Enemy
		if enemy == null:
			enemy = ENEMY_SCENE.instantiate()
			enemy.enemy_id = enemy_id
			enemy.name = str(enemy_id)
			enemy.kind = state[1]
			enemy.position = state[2]
			_enemies.add_child(enemy)
		enemy.push_snapshot(server_time, state[2], state[3], state[4], state[5], state[7])
		enemy.set_health(state[6])
		enemy.set_statuses(state[8])
	for enemy: Enemy in _enemies.get_children():
		if not seen.has(enemy.enemy_id):
			_enemies.remove_child(enemy)
			enemy.queue_free()


@rpc("authority", "call_remote", "reliable")
func _receive_hit(attacker_id: int, target_id: int, damage: float, result: int) -> void:
	var my_id := multiplayer.get_unique_id()
	if result in [HIT_DAMAGED, HIT_CRITICAL, HIT_DEFEATED, HIT_GUARD_BROKEN]:
		if attacker_id == my_id:
			_hits_landed += 1
		if target_id == my_id:
			_hits_taken += 1
			if result == HIT_DEFEATED and _local_player:
				var respawn_seconds := _local_player.params.respawn_ticks / float(Engine.physics_ticks_per_second)
				_respawn_at_msec = Time.get_ticks_msec() + roundi(respawn_seconds * 1000.0)
	var container := _enemies if target_id < 0 else _players
	var target := container.get_node_or_null(str(target_id))
	if target:
		target.show_hit(damage, result)
		if target_id < 0 and attacker_id == my_id:
			(target as Enemy).record_my_damage(damage, result)


func _spawn_client_player(peer_id: int, local: bool, pos: Vector3) -> Player:
	var player: Player = PLAYER_SCENE.instantiate()
	player.name = str(peer_id)
	player.peer_id = peer_id
	player.is_local = local
	player.position = pos
	_players.add_child(player)
	if local:
		_local_player = player
		player.projectile_released.connect(_projectiles.client_fire)
	else:
		print("[client %d] sees peer %d" % [multiplayer.get_unique_id(), peer_id])
	return player


## Remote players are drawn at (latest server time - interpolation delay). The
## clock runs on local time and is nudged toward the server's to absorb jitter.
func _sync_render_clock(server_time: float) -> void:
	var target := server_time - _interpolation_delay
	if _render_time < 0.0 or absf(_render_time - target) > 0.25:
		_render_time = target
	else:
		_render_time = lerpf(_render_time, target, 0.05)


func _update_hud() -> void:
	if _hud == null:
		return
	var lines := PackedStringArray([
		"Peer %d   Players: %d   Ping: %d ms" % [
				multiplayer.get_unique_id(), _players.get_child_count(), Net.get_ping_ms()],
		"Snapshots: %d   Prediction corrections: %d" % [
				_snapshots_received, _local_player.corrections if _local_player else 0],
		"Hits landed: %d   Hits taken: %d   F3: hitboxes %s" % [
				_hits_landed, _hits_taken, "on" if Player.show_hitboxes else "off"],
	])
	if _bot:
		lines.append("BOT MODE")
	_hud.set_info("\n".join(lines))
	if _local_player:
		_hud.set_health(_local_player.health, _local_player.max_health())
		_hud.set_stamina(_local_player.state.stamina, _local_player.params.max_stamina)
		var banner := ""
		if _local_player.state.is_rebirthing():
			var rebirth_seconds := ceili(_local_player.state.rebirth_left
					/ float(Engine.physics_ticks_per_second))
			banner = "Rebirth\nRising from the ashes in %d" % rebirth_seconds
		elif _local_player.state.dead:
			var seconds_left := maxi(0, ceili((_respawn_at_msec - Time.get_ticks_msec()) / 1000.0))
			banner = "Defeated\nRespawning in %d" % seconds_left
		_hud.set_banner(banner)
		_update_loadout_hud()
		_update_wing_hud()
		_update_status_hud()


## The ability bar and weapon line, from the local player's predicted state.
func _update_loadout_hud() -> void:
	var state := _local_player.state
	var params := _local_player.params
	var weapon := state.weapon(params)
	var other := ""
	if state.weapons.size() >= PlayerState.WEAPON_SLOTS:
		other = params.weapon(state.weapons[1 - state.equipped]).display_name
	_hud.set_weapons(weapon.display_name, other, state.is_swapping())
	var tps := float(Engine.physics_ticks_per_second)
	for slot in PlayerState.ABILITY_SLOTS:
		var ability := weapon.ability(state.slot_ability(slot))
		if ability == null:
			_hud.set_ability(slot, "", 0.0, 0.0)
			continue
		var left := state.cooldown_left(state.slot_ability(slot))
		_hud.set_ability(slot, ability.display_name,
				left / float(maxi(1, ability.cooldown_ticks)), left / tps)


## The Wing slots, Ember bar and Rebirth line, from the local player's
## predicted state.
func _update_wing_hud() -> void:
	var state := _local_player.state
	var params := _local_player.params
	var tps := float(Engine.physics_ticks_per_second)
	var pool := state.wings(params)
	for slot in PlayerState.WING_SLOTS:
		var index := state.wing_slot_ability(slot)
		var wing := pool.ability(index)
		if wing == null:
			_hud.set_wing(slot, "", 0.0, 0.0, 0.0, false)
			continue
		var left := state.wing_cooldown_left(index)
		_hud.set_wing(slot, wing.display_name, left / float(maxi(1, wing.cooldown_ticks)), left / tps,
				wing.ember_cost, state.can_afford(wing))
	var rebirth := ""
	if state.is_rebirthing():
		rebirth = "Rebirthing..."
	elif state.rebirth_cooldown > 0:
		var seconds := ceili(state.rebirth_cooldown / tps)
		@warning_ignore("integer_division")
		rebirth = "Rebirth in %d:%02d" % [seconds / 60, seconds % 60]
	elif state.ember >= state.rebirth_ember_needed(params):
		rebirth = "Rebirth ready"
	else:
		rebirth = "Rebirth needs %d Ember" % roundi(state.rebirth_ember_needed(params))
	if state.rebirth_charges > 0:
		rebirth += "  (+%d extra)" % state.rebirth_charges
	_hud.set_ember(state.ember, state.ember_cap(params), state.rebirth_ember_needed(params),
			rebirth, state.can_rebirth(params))


## The status row, from the local player's predicted state.
func _update_status_hud() -> void:
	var defs := _local_player.params.statuses
	var tps := float(Engine.physics_ticks_per_second)
	var entries: Array = []
	for e in _local_player.state.statuses.entries:
		var def := defs.get_def(e.status)
		if def:
			entries.append([def.display_name, e.stacks, e.ticks_left / tps, def.is_debuff()])
	_hud.set_statuses(entries)
	_hud.set_blind(_local_player.state.statuses.blind_amount(defs))


## Debug: with --screenshot-dir=PATH, saves this game window's image every 0.25 s
## (game pixels only, not the desktop), for checking visuals without a person.
func _maybe_save_screenshot() -> void:
	var dir := LaunchArgs.get_value("screenshot-dir")
	if dir.is_empty() or _local_player == null:
		return
	var slot := Time.get_ticks_msec() / 250
	if slot == _last_screenshot_slot:
		return
	_last_screenshot_slot = slot
	var image := get_viewport().get_texture().get_image()
	image.save_png(dir.path_join("frame_%04d.png" % slot))


func _describe_players() -> String:
	var parts := PackedStringArray()
	for player: Player in _players.get_children():
		var p := player.global_position
		parts.append("%s%d@(%.1f, %.1f)" % ["*" if player.is_local else "", player.peer_id, p.x, p.z])
	return "[client %d] %s" % [multiplayer.get_unique_id(), "  ".join(parts)]


## Printed when the process exits via --quit-after; used by tools/smoke_test.ps1.
func print_summary() -> void:
	if multiplayer.is_server():
		print("SUMMARY server players=%d ticks=%d hits=%d deaths=%d respawns=%d blocks=%d guard_breaks=%d" % [
				_players.get_child_count(), _tick, _hits, _deaths, _respawns, _blocks, _guard_breaks])
		var switches := 0
		for enemy: Enemy in _enemies.get_children():
			switches += enemy.brain.target_switches
		print("SUMMARY enemies count=%d enemy_hits=%d enemy_damaged=%d enemy_kills=%d target_switches=%d taunts=%d heal_threat=%d" % [
				_enemies.get_child_count(), _enemy_hits, _enemy_damaged, _enemy_kills, switches,
				_taunts, _heal_threat])
		print("SUMMARY party formed=%d parties=%d pvp_hits=%d ally_hits_ignored=%d shield_wall_covers=%d" % [
				party.rules.formed_count, party.rules.party_count(), _pvp_hits, _ally_hits_ignored,
				_shield_wall_covers])
		print("SUMMARY abilities uses=%d ability_hits=%d parries=%d swaps=%d builds=%d builds_refused=%d line_pokes=%d" % [
				_ability_uses, _ability_hits, _parries, _swaps, _builds.accepted, _builds.rejected,
				_line_pokes])
		print("SUMMARY statuses applied=%d on_enemies=%d self_buffs=%d dot_ticks=%d dot_damage=%d ally_refused=%d ally_applied=%d" % [
				_statuses_applied, _statuses_on_enemies, _self_buffs, _status_ticks,
				roundi(_status_damage), _ally_statuses_refused, _ally_statuses_applied])
		_print_force_summary()
		_print_ember_summary()
		_print_juggernaut_summary()
		zones.print_summary()
		_projectiles.print_summary()
		loot.print_summary()
		print("SUMMARY gear_combat gear_crits=%d armored_hits=%d armor_stopped=%d" % [
				_gear_crits, _armored_hits, roundi(_armor_stopped)])
		return
	_projectiles.print_client_summary()
	loot.print_client_summary()
	if _local_player:
		print("SUMMARY client=%d snapshots=%d corrections=%d dodges=%d air_dodges=%d attacks=%d hits_landed=%d abilities=%d swaps=%d" % [
				multiplayer.get_unique_id(), _snapshots_received, _local_player.corrections,
				_local_player.dodges, _local_player.air_dodges, _local_player.attacks, _hits_landed,
				_local_player.abilities_used, _local_player.swaps])
		print("SUMMARY client=%d party_members=%d" % [
				multiplayer.get_unique_id(), party.member_count()])
	var seen := _departed_seen.duplicate()
	for player: Player in _players.get_children():
		if not player.is_local:
			seen[player.peer_id] = player.distance_seen
	for peer_id: int in seen:
		print("SUMMARY client=%d remote=%d moved=%.1f" % [
				multiplayer.get_unique_id(), peer_id, seen[peer_id]])
